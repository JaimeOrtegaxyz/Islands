import AppKit
import ApplicationServices
import IslandsCore

// MARK: - Data Types

enum CycleDirection {
    case forward, backward
}

enum CenterDirection {
    case shrink, grow
}

/// The axis a directional (arrow) command steps along. Off-grid snap targets on
/// this axis exclude centered slots, so a Left/Right press never jumps the window
/// toward the screen center or flips it into centered mode — a mode only the
/// center commands enter.
enum ActionAxis {
    case horizontal, vertical
}

/// A directional (arrow) command.
enum ArrowDirection {
    case left, right, up, down

    var axis: ActionAxis {
        switch self {
        case .left, .right: return .horizontal
        case .up, .down: return .vertical
        }
    }

    /// Toward increasing AX coordinates (top-left origin): right and down.
    var isForward: Bool { self == .right || self == .down }
}

// MARK: - Window Manager

final class WindowManager {
    private let engine: WindowEngine
    private let screens: ScreenManager
    private let settingsStore: SettingsStore
    private let monitorOverflowEnabled = true

    private var horizontalLayout: AxisLayout
    private var verticalLayout: AxisLayout
    private var markerStyle: StackMarkerStyle
    private let markers: StackMarkerController
    private let observer = WindowObserver()

    // Per-window state
    private var winState: [CGWindowID: WindowState] = [:]

    // Zone tracking (stacks). Each zone's members in their stable order — the order the
    // marker shows and Tab steps through; switching never reorders it.
    private var zoneWindows: [String: [CGWindowID]] = [:]

    /// Each stack's visible member. All members share one frame, so it is whichever is on top.
    private var zoneFront: [String: CGWindowID] = [:]

    /// When the window list will have caught up with a front Islands just focused: the window
    /// server reorders ~100–150ms after an activation, and until then `refreshStackFronts`
    /// would read the old front back off it and undo the switch on the marker.
    private var frontSettlesAt: [String: Date] = [:]

    /// Stacks with a member-moved check already scheduled (see `handle(_:)`).
    private var pendingReconciles: Set<String> = []

    // Cleanup timer
    private var cleanupTimer: Timer?
    private var markerTimer: Timer?
    private var settingsObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?

    init(engine: WindowEngine, screens: ScreenManager, settingsStore: SettingsStore) {
        self.engine = engine
        self.screens = screens
        self.settingsStore = settingsStore

        let settings = settingsStore.snapshot
        horizontalLayout = AxisLayout.make(for: settings.snapProfile)
        verticalLayout = AxisLayout.make(for: settings.snapProfile)
        markerStyle = settings.stackMarker
        markers = StackMarkerController(style: settings.stackMarker)

        markers.onSelect = { [weak self] zoneKey, windowID in
            self?.selectStackMember(windowID, in: zoneKey)
        }
        markers.onReorder = { [weak self] zoneKey, order in
            self?.reorderStack(zoneKey, to: order)
        }
        observer.onEvent = { [weak self] event in
            // Out of the AX callback first: handling it re-enters AX.
            DispatchQueue.main.async { self?.handle(event) }
        }

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleWindows()
        }

        // Backstop for what the AX notifications miss (an app that doesn't post them): faster than
        // the cleanup sweep, which never sees a closed Finder window go — Finder keeps it listed.
        markerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshStackMarkers()
        }

        // A stack's front can change without Islands — ⌘-Tab, a Dock click. The window list
        // shows the activation ~100–150ms after this notification, so read it a little later.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self?.refreshStackFronts()
            }
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: settingsStore,
            queue: .main
        ) { [weak self] _ in
            self?.applyLatestSettings()
        }
    }

    deinit {
        cleanupTimer?.invalidate()
        markerTimer?.invalidate()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    // MARK: - State Management

    private func makeInitialState() -> WindowState {
        WindowState(hIdx: horizontalLayout.fullEdgeIndex, vIdx: verticalLayout.fullEdgeIndex)
    }

    /// The snap state whose slots most closely match a window's actual frame, so an
    /// off-grid window enters the cycle from wherever the user left it.
    private func inferredState(
        from actualFrame: CGRect,
        screenFrame: CGRect,
        hIncludeCentered: Bool = true,
        vIncludeCentered: Bool = true
    ) -> WindowState {
        LayoutGeometry.nearestState(
            for: actualFrame,
            horizontal: horizontalLayout,
            vertical: verticalLayout,
            screenFrame: screenFrame,
            hIncludeCentered: hIncludeCentered,
            vIncludeCentered: vIncludeCentered
        )
    }

    /// A non-zoned window resting exactly on a slot where a stack lives
    /// should rejoin the stack — the same first press that snaps a near-miss window
    /// into it — rather than step away from it.
    private func shouldRejoinStack(_ state: WindowState, windowID: CGWindowID, actualFrame: CGRect) -> Bool {
        guard state.currentZone == nil else { return false }
        let zoneKey = getZoneKey(state: state, screenID: screens.screenID(for: actualFrame))
        return zoneWindows[zoneKey]?.contains { $0 != windowID } == true
    }

    /// The state a window action starts from. A window whose tracked state matches its
    /// actual frame is on-grid and cycles normally. A window that is untracked — or was
    /// moved/resized by hand since it was last snapped — instead gets a state inferred
    /// from its geometry, and `onGrid: false` tells the caller the first press should
    /// snap to that nearest slot rather than step beyond it. `onGrid: true` with an
    /// inferred state means the user parked the window exactly on a slot, so a step
    /// from there is never a visible no-op — unless a stack lives on that slot, in
    /// which case the first press rejoins it (`shouldRejoinStack`). An off-grid window
    /// under an arrow whose nearest-slot snap would go against the arrow also gets
    /// `onGrid: true`: the press steps from that slot, as if the window were on it.
    ///
    /// `zoneVerified` is `synchronizeZoneMembership`'s return value: the zone
    /// fast-path is only sound when the sync actually read the frame this press.
    private func resolveState(
        for windowID: CGWindowID,
        window: AXUIElement,
        zoneVerified: Bool,
        arrow: ArrowDirection? = nil
    ) -> (state: WindowState, onGrid: Bool) {
        let tracked = winState[windowID]

        // Still in a zone: synchronizeZoneMembership verified frame == slot just now.
        if let tracked, tracked.currentZone != nil, zoneVerified {
            return (tracked, true)
        }

        guard let actualFrame = engine.getFrame(window),
              let screenFrame = screens.screenFrame(for: actualFrame) else {
            return (tracked ?? makeInitialState(), true)
        }

        if let tracked, LayoutGeometry.framesApproximatelyEqual(actualFrame, frame(for: tracked, screenFrame: screenFrame)) {
            return (tracked, !shouldRejoinStack(tracked, windowID: windowID, actualFrame: actualFrame))
        }

        // No settledFrame check here: a zoned window that an app clamps or quantizes off its
        // slot never reaches this point — synchronizeZoneMembership already matched it against
        // its settledFrame (isInPlace) and the zone fast path above returned. Zone-less tracked
        // windows have had their settledFrame cleared by eviction.
        var inferred = inferredState(from: actualFrame, screenFrame: screenFrame)
        inferred.currentZone = tracked?.currentZone
        if LayoutGeometry.framesApproximatelyEqual(actualFrame, frame(for: inferred, screenFrame: screenFrame)) {
            return (inferred, !shouldRejoinStack(inferred, windowID: windowID, actualFrame: actualFrame))
        }

        // Off-grid: pick the snap target. Arrows keep their own axis on edge slots
        // (see `ActionAxis`); the cross axis still snaps to whatever is nearest.
        guard let arrow else { return (inferred, false) }
        var target = inferredState(
            from: actualFrame,
            screenFrame: screenFrame,
            hIncludeCentered: arrow.axis != .horizontal,
            vIncludeCentered: arrow.axis != .vertical
        )
        target.currentZone = tracked?.currentZone

        // Snap onto the nearest slot only when that snap itself goes the way the arrow
        // points. A window nudged just past a slot would otherwise be pulled back against
        // the press — Right on a window hanging slightly right of the left half would land
        // it on the left half. Otherwise the press steps from that slot, as if the window
        // were already on it.
        let targetFrame = frame(for: target, screenFrame: screenFrame)
        let follows = arrow.axis == .horizontal
            ? LayoutGeometry.snapFollowsDirection(
                actualMin: actualFrame.minX, actualMax: actualFrame.maxX,
                targetMin: targetFrame.minX, targetMax: targetFrame.maxX,
                forward: arrow.isForward)
            : LayoutGeometry.snapFollowsDirection(
                actualMin: actualFrame.minY, actualMax: actualFrame.maxY,
                targetMin: targetFrame.minY, targetMax: targetFrame.maxY,
                forward: arrow.isForward)
        return (target, !follows)
    }

    private func applyLatestSettings() {
        let settings = settingsStore.snapshot
        let oldFullIndex = horizontalLayout.fullEdgeIndex
        let newHorizontalLayout = AxisLayout.make(for: settings.snapProfile)
        let newVerticalLayout = AxisLayout.make(for: settings.snapProfile)
        let layoutChanged = newHorizontalLayout.fullEdgeIndex != oldFullIndex
            || newHorizontalLayout.edgePositions.count != horizontalLayout.edgePositions.count

        horizontalLayout = newHorizontalLayout
        verticalLayout = newVerticalLayout

        let newStyle = settings.stackMarker

        if layoutChanged {
            markerStyle = newStyle
            markers.style = newStyle
            markers.removeAll()
            observer.watch([:])
            winState.removeAll()
            zoneWindows.removeAll()
            zoneFront.removeAll()
            return
        }

        if markerStyle != newStyle {
            // Members physically wear the OLD style's band, so evict any the user has moved
            // while expected frames still match what was applied — reconciling after the
            // switch would mis-evict healthy members. Then lay the survivors out again under
            // the new band (the marker controller drops the old markers on the style change).
            for zoneKey in Array(zoneWindows.keys) {
                reconcileZoneMembers(zoneKey: zoneKey)
            }
            markerStyle = newStyle
            markers.style = newStyle
            refreshAllZones()
        }
    }

    // MARK: - Zone Tracking

    private func getZoneKey(state: WindowState, screenID: String) -> String {
        let horizontalPart = state.hCentered ? "ch\(state.hCenterIdx)" : "h\(state.hIdx)"
        let verticalPart = state.vCentered ? "cv\(state.vCenterIdx)" : "v\(state.vIdx)"
        return "\(screenID)_\(horizontalPart)_\(verticalPart)"
    }

    private func removeFromZone(windowID: CGWindowID, zoneKey: String?) {
        guard let zoneKey, zoneWindows[zoneKey] != nil else { return }
        zoneWindows[zoneKey]?.removeAll { $0 == windowID }
        if zoneFront[zoneKey] == windowID {
            zoneFront[zoneKey] = nil
        }
        if zoneWindows[zoneKey]?.isEmpty == true {
            zoneWindows[zoneKey] = nil
            frontSettlesAt[zoneKey] = nil
            markers.remove(zoneKey: zoneKey)
        }
    }

    /// Put a window in a stack as its front. A newcomer goes to the end of the order, like a
    /// new tab; a window snapped back onto its own stack keeps its place.
    private func addToZone(windowID: CGWindowID, zoneKey: String) {
        if zoneWindows[zoneKey] == nil {
            zoneWindows[zoneKey] = []
        }
        if zoneWindows[zoneKey]?.contains(windowID) == false {
            zoneWindows[zoneKey]?.append(windowID)
        }
        zoneFront[zoneKey] = windowID
    }

    /// Take a window out of its stack. Also clears `settledFrame`: a fresh snap
    /// re-establishes it, and keeping it would let a stale "where we left it" frame
    /// masquerade as user intent after the stack rearranges.
    private func evictFromZone(windowID: CGWindowID, zoneKey: String) {
        removeFromZone(windowID: windowID, zoneKey: zoneKey)
        winState[windowID]?.currentZone = nil
        winState[windowID]?.settledFrame = nil
    }

    private func refreshAllZones() {
        for zoneKey in Array(zoneWindows.keys) {
            layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
        }
    }

    // MARK: - Frame Calculation

    private func frame(for state: WindowState, screenFrame: CGRect, topInset: CGFloat = 0) -> CGRect {
        LayoutGeometry.frame(
            for: state,
            horizontal: horizontalLayout,
            vertical: verticalLayout,
            screenFrame: screenFrame,
            topInset: topInset
        )
    }

    private func applyFrame(window: AXUIElement, state: WindowState, targetScreen: NSScreen?, topInset: CGFloat = 0) {
        let screenFrame: CGRect
        if let targetScreen {
            screenFrame = screens.visibleFrame(of: targetScreen)
        } else if let currentFrame = engine.getFrame(window),
                  let currentScreenFrame = screens.screenFrame(for: currentFrame) {
            screenFrame = currentScreenFrame
        } else if let position = engine.getPosition(window),
                  let currentScreenFrame = screens.screenFrame(for: position) {
            screenFrame = currentScreenFrame
        } else {
            return
        }

        engine.setFrame(window, frame: frame(for: state, screenFrame: screenFrame, topInset: topInset), visibleFrame: screenFrame)
    }

    /// The top inset a zone's members wear as last laid out: the marker band, if it is a stack.
    private func stackInset(zoneKey: String) -> CGFloat {
        LayoutGeometry.stackInset(count: zoneWindows[zoneKey]?.count ?? 0, bandHeight: markerStyle.bandHeight)
    }

    /// Whether a window physically sits where the manager last put it: on its expected
    /// slot frame, or — for apps that clamp/quantize our frames — on the frame it
    /// actually settled at after the last snap.
    private func isInPlace(actualFrame: CGRect, expectedFrame: CGRect, settledFrame: CGRect?) -> Bool {
        if LayoutGeometry.framesApproximatelyEqual(actualFrame, expectedFrame) { return true }
        if let settledFrame { return LayoutGeometry.framesApproximatelyEqual(actualFrame, settledFrame) }
        return false
    }

    /// Reconcile the focused window's tracked zone membership against where the window
    /// actually is (the user may have moved, resized, or minimized it by hand).
    /// Returns `false` only when the frame could not be read this press, meaning the
    /// membership was NOT verified — `resolveState` must not trust `currentZone` then.
    @discardableResult
    private func synchronizeZoneMembership(for windowID: CGWindowID, window: AXUIElement) -> Bool {
        guard var state = winState[windowID],
              let oldZone = state.currentZone else {
            return true
        }

        // A minimized member reports a stale frame; don't reconcile against it. Evict it
        // from the zone (consistent with layoutStack) and lay the rest out again.
        if engine.isMinimized(window) {
            evictFromZone(windowID: windowID, zoneKey: oldZone)
            layoutStack(zoneKey: oldZone, shouldFocusFront: false)
            return true
        }

        guard let actualFrame = engine.getFrame(window),
              let screenFrame = screens.screenFrame(for: actualFrame) else {
            return false
        }

        let expectedFrame = frame(for: state, screenFrame: screenFrame, topInset: stackInset(zoneKey: oldZone))

        guard isInPlace(actualFrame: actualFrame, expectedFrame: expectedFrame, settledFrame: state.settledFrame) else {
            evictFromZone(windowID: windowID, zoneKey: oldZone)
            layoutStack(zoneKey: oldZone, shouldFocusFront: false)
            return true
        }

        let liveZone = getZoneKey(state: state, screenID: screens.screenID(for: actualFrame))
        guard liveZone != oldZone else { return true }

        removeFromZone(windowID: windowID, zoneKey: oldZone)
        addToZone(windowID: windowID, zoneKey: liveZone)
        state.currentZone = liveZone
        winState[windowID] = state
        layoutStack(zoneKey: oldZone, shouldFocusFront: false)
        layoutStack(zoneKey: liveZone, shouldFocusFront: false)
        return true
    }

    /// Evict from a stack any tracked member (minus the window being acted on) that
    /// the user has moved, resized, or minimized since the stack was last laid out.
    /// Pure bookkeeping — no frames are applied here, callers lay the stack out once afterwards —
    /// so one member's eviction can't disturb the checks, or the placement, of the
    /// members after it. All expected frames are computed before the first eviction,
    /// while the stack's inset still reflects the stack as last laid out; for
    /// the same reason this must run before the zone's membership changes. A member
    /// whose frame can't be read (hung or just-closed app) is left for the cleanup
    /// timer. Returns whether anything was evicted.
    @discardableResult
    private func reconcileZoneMembers(zoneKey: String?, excluding excludedID: CGWindowID? = nil) -> Bool {
        guard let zoneKey, let members = zoneWindows[zoneKey] else { return false }

        var stale: [CGWindowID] = []
        for memberID in members where memberID != excludedID {
            guard let state = winState[memberID],
                  let memberWindow = engine.windowElement(for: memberID) else { continue }
            if engine.isMinimized(memberWindow) {
                stale.append(memberID)
                continue
            }
            guard let actualFrame = engine.getFrame(memberWindow),
                  let screenFrame = screens.screenFrame(for: actualFrame) else { continue }
            let expectedFrame = frame(for: state, screenFrame: screenFrame, topInset: stackInset(zoneKey: zoneKey))
            if !isInPlace(actualFrame: actualFrame, expectedFrame: expectedFrame, settledFrame: state.settledFrame)
                || getZoneKey(state: state, screenID: screens.screenID(for: actualFrame)) != zoneKey {
                stale.append(memberID)
            }
        }

        for memberID in stale {
            evictFromZone(windowID: memberID, zoneKey: zoneKey)
        }
        return !stale.isEmpty
    }

    // MARK: - Stacks

    /// Lay a stack out: every visible member gets the same frame — the slot, minus the marker
    /// band when there is more than one — so only the front is ever seen and switching never
    /// moves a window. Then (re)draw the marker.
    private func layoutStack(zoneKey: String, shouldFocusFront: Bool = true) {
        guard let windowIDs = zoneWindows[zoneKey] else {
            markers.remove(zoneKey: zoneKey)
            return
        }

        // Resolve members, evicting any that are minimized: applying a frame, raising,
        // or focusing a Dock-minimized window un-minimizes it. Evicting (rather than
        // keeping it parked in the zone) keeps the layout deterministic — the band and
        // the marker then cover the visible members only.
        //
        // Intended consequence, not a bug: a minimized window leaves its stack. If the
        // stack is rearranged while it's away, restoring it returns it to its last position
        // but zone-less — re-snap to rejoin. "Remembering" across minimize would have to
        // follow a moved stack (or resurrect a closed one), breaking the expectation that a
        // restored window comes back where it was.
        var visible: [(window: AXUIElement, id: CGWindowID)] = []
        var sawExisting = false
        for windowID in windowIDs {
            guard winState[windowID] != nil, let window = engine.windowElement(for: windowID) else {
                continue
            }
            sawExisting = true
            // A closed member's cached element still resolves until the cleanup sweep; evict it
            // too, so it can't take a place in the marker or be focused as the front.
            if engine.presence(of: window) != .visible {
                evictFromZone(windowID: windowID, zoneKey: zoneKey)
                continue
            }
            visible.append((window: window, id: windowID))
        }

        // No member exists anymore (all closed) — tear the zone down.
        guard sawExisting else {
            zoneWindows[zoneKey] = nil
            zoneFront[zoneKey] = nil
            markers.remove(zoneKey: zoneKey)
            return
        }

        // Members exist but all are minimized — nothing to lay out. Don't nil the zone
        // here; removeFromZone above already nils it if it emptied, and any still-tracked
        // window may be re-snapped later.
        guard !visible.isEmpty else {
            markers.remove(zoneKey: zoneKey)
            return
        }

        let inset = LayoutGeometry.stackInset(count: visible.count, bandHeight: markerStyle.bandHeight)
        for entry in visible {
            applyFrame(window: entry.window, state: winState[entry.id]!, targetScreen: nil, topInset: inset)

            // Record where the window actually landed — for every member, not just the one
            // being acted on. A re-layout (a neighbour joining or leaving, a marker style change)
            // can change the band, and an app that clamps or quantizes lands off-slot at a new
            // place; a frame left over from the previous layout would fail the next in-place
            // check (see isInPlace) and evict a member the user never touched.
            winState[entry.id]?.settledFrame = engine.getFrame(entry.window)
        }

        // The front left (moved away, closed): the member now showing is whichever is on top.
        let front = visible.first { $0.id == zoneFront[zoneKey] } ?? topmost(of: visible)
        zoneFront[zoneKey] = front.id

        // Focus only when the front changed (a member joined) — the shouldFocusFront calls.
        // Maintenance re-layouts (member left/evicted, style change, cleanup) leave the
        // stack's windows where they are in the z-order.
        if shouldFocusFront {
            focusFront(front.window, zoneKey: zoneKey)
        }
        updateMarker(zoneKey: zoneKey)
        watchStackMembers()
    }

    /// The member highest in the window server's z-order — the one on screen.
    private func topmost(of members: [(window: AXUIElement, id: CGWindowID)]) -> (window: AXUIElement, id: CGWindowID) {
        let order = engine.onScreenWindowOrder()
        let rank = { (id: CGWindowID) in order.firstIndex(of: id) ?? Int.max }
        return members.min { rank($0.id) < rank($1.id) } ?? members[0]
    }

    private func focusFront(_ window: AXUIElement, zoneKey: String) {
        frontSettlesAt[zoneKey] = Date().addingTimeInterval(0.6)
        engine.focus(window)
    }

    /// Make `windowID` the stack's front: focus it and move the marker's highlight to it.
    private func bringForward(_ windowID: CGWindowID, window: AXUIElement, zoneKey: String) {
        zoneFront[zoneKey] = windowID
        focusFront(window, zoneKey: zoneKey)
        markers.setFront(zoneKey: zoneKey, frontID: windowID)
        // Right for a same-app switch, which lands at once; another app's window comes up with
        // its app's activation, and refreshStackFronts restacks again once that lands.
        markers.restack(zoneKey: zoneKey)
        if markerStyle == .slim {
            markers.showSwitcher(zoneKey: zoneKey)
        }
    }

    /// The slot a stack occupies, band included, and its screen's visible frame — from the front
    /// member's state and where it settled, so no AX read is needed.
    private func slotFrame(zoneKey: String) -> (slot: CGRect, screen: CGRect)? {
        guard let frontID = zoneFront[zoneKey],
              let state = winState[frontID],
              let settled = state.settledFrame,
              let screenFrame = screens.screenFrame(for: settled) else { return nil }
        return (frame(for: state, screenFrame: screenFrame), screenFrame)
    }

    /// Redraw a stack's marker from its members as they are now (titles re-read), or take it
    /// down when the zone is no longer a stack. Cheap when nothing changed: the controller
    /// skips identical content.
    private func updateMarker(zoneKey: String) {
        guard let ids = zoneWindows[zoneKey], ids.count > 1,
              let frontID = zoneFront[zoneKey],
              let (slot, screenFrame) = slotFrame(zoneKey: zoneKey) else {
            markers.remove(zoneKey: zoneKey)
            return
        }
        let members = ids.compactMap { id -> StackMarkerMember? in
            guard let window = engine.windowElement(for: id), let pid = engine.getOwnerPID(window) else { return nil }
            return StackMarkerMember(id: id, pid: pid, title: engine.title(of: window))
        }
        guard members.count > 1 else {
            markers.remove(zoneKey: zoneKey)
            return
        }
        // Every width the snap profile can give a window on this screen: the tab strip ends on one.
        let snapWidths = Set(horizontalLayout.edgePositions.map { $0.size * screenFrame.width }).sorted()
        markers.show(
            zoneKey: zoneKey,
            slot: screens.cocoaFrame(fromTopLeft: slot),
            snapWidths: snapWidths,
            members: members,
            frontID: frontID
        )
    }

    /// Point the AX observer at exactly the windows in stacks.
    private func watchStackMembers() {
        var targets: [CGWindowID: (element: AXUIElement, pid: pid_t)] = [:]
        for ids in zoneWindows.values where ids.count > 1 {
            for id in ids {
                guard let element = engine.windowElement(for: id), let pid = engine.getOwnerPID(element) else { continue }
                targets[id] = (element, pid)
            }
        }
        observer.watch(targets)
    }

    /// A change to a stack member made outside Islands.
    private func handle(_ event: WindowObserver.Event) {
        switch event {
        case .closed(let windowID), .minimized(let windowID):
            // Re-laying out evicts members that are gone or minimized.
            guard let zoneKey = winState[windowID]?.currentZone, zoneWindows[zoneKey] != nil else { return }
            layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
        case .moved(let windowID):
            // Islands' own layouts post these too, and a drag posts a stream of them, so check
            // once shortly after the first; members still in place are left alone.
            guard let zoneKey = winState[windowID]?.currentZone,
                  pendingReconciles.insert(zoneKey).inserted else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.pendingReconciles.remove(zoneKey)
                if self.reconcileZoneMembers(zoneKey: zoneKey) {
                    self.layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
                }
            }
        case .focusChanged:
            // A same-app switch (⌘-`) reorders right away; read the result a beat later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.refreshStackFronts()
            }
        }
    }

    /// A click on a marker: bring that member forward. Members the user has moved away by
    /// hand are dropped first, so the click can't summon a window from elsewhere.
    private func selectStackMember(_ windowID: CGWindowID, in zoneKey: String) {
        if reconcileZoneMembers(zoneKey: zoneKey) {
            layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
        }
        guard zoneWindows[zoneKey]?.contains(windowID) == true,
              let window = engine.windowElement(for: windowID),
              engine.presence(of: window) == .visible else { return }
        bringForward(windowID, window: window, zoneKey: zoneKey)
    }

    /// A drag on a marker: adopt its order. Members it didn't know about keep their place at the end.
    private func reorderStack(_ zoneKey: String, to order: [CGWindowID]) {
        guard let current = zoneWindows[zoneKey] else { return }
        let kept = order.filter(current.contains)
        zoneWindows[zoneKey] = kept + current.filter { !kept.contains($0) }
        updateMarker(zoneKey: zoneKey)
    }

    /// Follow each stack's front when something other than Islands changed it (⌘-Tab, ⌘-`,
    /// a Dock click) by reading which member is on top, and keep each marker just above its
    /// front — raising a stack window can bring other windows of its app over the marker.
    /// One window-list copy for all stacks.
    private func refreshStackFronts() {
        let stacks = zoneWindows.filter { $0.value.count > 1 }
        guard !stacks.isEmpty else { return }
        let order = engine.onScreenWindowOrder()
        let now = Date()
        for (zoneKey, ids) in stacks {
            defer { markers.restack(zoneKey: zoneKey) }
            if let settles = frontSettlesAt[zoneKey], settles > now { continue }
            guard let top = order.first(where: ids.contains), top != zoneFront[zoneKey] else { continue }
            zoneFront[zoneKey] = top
            markers.setFront(zoneKey: zoneKey, frontID: top)
        }
    }

    /// Periodic refresh, only while a stack exists: members closed or minimized behind Islands'
    /// back that no notification reported (re-laid out, which evicts them), fronts changed outside
    /// Islands, and titles that changed (a terminal's working directory, a document name).
    private func refreshStackMarkers() {
        let stacks = zoneWindows.filter { $0.value.count > 1 }
        guard !stacks.isEmpty else {
            observer.watch([:])
            return
        }
        refreshStackFronts()
        for (zoneKey, ids) in stacks {
            let lost = ids.contains { id in
                engine.windowElement(for: id).map { engine.presence(of: $0) != .visible } ?? false
            }
            if lost {
                layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
            } else {
                updateMarker(zoneKey: zoneKey)
            }
        }
        watchStackMembers()
    }

    private func finishMove(window: AXUIElement, windowID: CGWindowID, oldZone: String?, targetScreen: NSScreen?) {
        if let targetScreen {
            let targetFrame = screens.visibleFrame(of: targetScreen)
            // A transient nudge onto the destination screen carrying the window's current size;
            // layoutStack immediately resets it to the real slot, so skip the on-screen clamp.
            engine.setFrame(window, frame: CGRect(
                origin: CGPoint(x: targetFrame.origin.x + 10, y: targetFrame.origin.y + 10),
                size: engine.getSize(window) ?? CGSize(width: 800, height: 600)
            ), visibleFrame: nil)
        }

        let screenID: String
        if let targetScreen {
            screenID = screens.screenID(for: targetScreen)
        } else if let currentFrame = engine.getFrame(window) {
            screenID = screens.screenID(for: currentFrame)
        } else if let position = engine.getPosition(window) {
            screenID = screens.screenID(for: position)
        } else {
            screenID = "unknown"
        }

        let state = winState[windowID]!
        let newZone = getZoneKey(state: state, screenID: screenID)

        // Zone membership can be stale: only the focused window is synchronized on each
        // action, so a member the user moved or resized manually would be yanked back to
        // its old slot — possibly on another screen — when the layouts below re-apply
        // frames. Reconcile (bookkeeping only) before membership changes; the single
        // layout per zone afterwards places the survivors.
        reconcileZoneMembers(zoneKey: oldZone, excluding: windowID)
        if newZone != oldZone {
            reconcileZoneMembers(zoneKey: newZone, excluding: windowID)
        }

        removeFromZone(windowID: windowID, zoneKey: oldZone)
        addToZone(windowID: windowID, zoneKey: newZone)
        winState[windowID]?.currentZone = newZone

        if let oldZone, oldZone != newZone {
            layoutStack(zoneKey: oldZone, shouldFocusFront: false)
        }
        // Also records each member's settled frame (including this window's): apps with
        // hard minimums or quantized sizing land off-slot, and that frame is what lets the
        // next press tell "the app refused our frame" from "the user moved the window"
        // (see synchronizeZoneMembership and reconcileZoneMembers).
        layoutStack(zoneKey: newZone)
    }

    // MARK: - Action Prologue

    /// Everything an action needs about the focused window, resolved once per press.
    private struct ActionContext {
        let window: AXUIElement
        let windowID: CGWindowID
        let state: WindowState
        let onGrid: Bool
        var oldZone: String? { state.currentZone }
    }

    /// Shared prologue for every window action: find the focused window, reconcile its
    /// zone membership, and resolve the state the action starts from. Funneling every
    /// action through here is what guarantees `resolveState` always runs against a
    /// membership `synchronizeZoneMembership` just reconciled (or knows it couldn't).
    private func beginAction(arrow: ArrowDirection? = nil) -> ActionContext? {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return nil }
        let zoneVerified = synchronizeZoneMembership(for: windowID, window: window)
        let resolved = resolveState(
            for: windowID,
            window: window,
            zoneVerified: zoneVerified,
            arrow: arrow
        )
        return ActionContext(window: window, windowID: windowID, state: resolved.state, onGrid: resolved.onGrid)
    }

    private func commit(_ ctx: ActionContext, state: WindowState, targetScreen: NSScreen? = nil) {
        winState[ctx.windowID] = state
        finishMove(window: ctx.window, windowID: ctx.windowID, oldZone: ctx.oldZone, targetScreen: targetScreen)
    }

    // MARK: - Edge-snap Movement

    func moveLeft() {
        guard let ctx = beginAction(arrow: .left) else { return }
        var state = ctx.state

        // Off-grid window whose nearest slot lies the way the arrow points: first press
        // snaps onto it (rejoining any stack living there); cycling continues from the
        // next press.
        guard ctx.onGrid else { return commit(ctx, state: state) }

        if state.hCentered {
            state.hCentered = false
            state.hIdx = horizontalLayout.centerToLeading[state.hCenterIdx] ?? horizontalLayout.fullEdgeIndex
            return commit(ctx, state: state)
        }

        if state.hIdx == 1 {
            if monitorOverflowEnabled,
               let position = engine.getPosition(ctx.window),
               let targetScreen = screens.screenToWest(of: position) {
                state.hIdx = horizontalLayout.fullEdgeIndex + 1
                commit(ctx, state: state, targetScreen: targetScreen)
            } else {
                state.hIdx = horizontalLayout.fullEdgeIndex - 1
                commit(ctx, state: state)
            }
        } else {
            state.hIdx -= 1
            commit(ctx, state: state)
        }
    }

    func moveRight() {
        guard let ctx = beginAction(arrow: .right) else { return }
        var state = ctx.state

        // Off-grid window whose nearest slot lies the way the arrow points: first press
        // snaps onto it (rejoining any stack living there); cycling continues from the
        // next press.
        guard ctx.onGrid else { return commit(ctx, state: state) }

        if state.hCentered {
            state.hCentered = false
            state.hIdx = horizontalLayout.centerToTrailing[state.hCenterIdx] ?? horizontalLayout.fullEdgeIndex
            return commit(ctx, state: state)
        }

        if state.hIdx == horizontalLayout.maxEdgeIndex {
            if monitorOverflowEnabled,
               let position = engine.getPosition(ctx.window),
               let targetScreen = screens.screenToEast(of: position) {
                state.hIdx = horizontalLayout.fullEdgeIndex - 1
                commit(ctx, state: state, targetScreen: targetScreen)
            } else {
                state.hIdx = horizontalLayout.fullEdgeIndex + 1
                commit(ctx, state: state)
            }
        } else {
            state.hIdx += 1
            commit(ctx, state: state)
        }
    }

    func moveUp() {
        guard let ctx = beginAction(arrow: .up) else { return }
        var state = ctx.state

        // Off-grid window whose nearest slot lies the way the arrow points: first press
        // snaps onto it (rejoining any stack living there); cycling continues from the
        // next press.
        guard ctx.onGrid else { return commit(ctx, state: state) }

        if state.vCentered {
            state.vCentered = false
            state.vIdx = verticalLayout.centerToLeading[state.vCenterIdx] ?? verticalLayout.fullEdgeIndex
            return commit(ctx, state: state)
        }

        if state.vIdx == 1 {
            if monitorOverflowEnabled,
               let position = engine.getPosition(ctx.window),
               let targetScreen = screens.screenToNorth(of: position) {
                state.vIdx = verticalLayout.fullEdgeIndex + 1
                commit(ctx, state: state, targetScreen: targetScreen)
            } else {
                state.vIdx = verticalLayout.fullEdgeIndex - 1
                commit(ctx, state: state)
            }
        } else {
            state.vIdx -= 1
            commit(ctx, state: state)
        }
    }

    func moveDown() {
        guard let ctx = beginAction(arrow: .down) else { return }
        var state = ctx.state

        // Off-grid window whose nearest slot lies the way the arrow points: first press
        // snaps onto it (rejoining any stack living there); cycling continues from the
        // next press.
        guard ctx.onGrid else { return commit(ctx, state: state) }

        if state.vCentered {
            state.vCentered = false
            state.vIdx = verticalLayout.centerToTrailing[state.vCenterIdx] ?? verticalLayout.fullEdgeIndex
            return commit(ctx, state: state)
        }

        if state.vIdx == verticalLayout.maxEdgeIndex {
            if monitorOverflowEnabled,
               let position = engine.getPosition(ctx.window),
               let targetScreen = screens.screenToSouth(of: position) {
                state.vIdx = verticalLayout.fullEdgeIndex - 1
                commit(ctx, state: state, targetScreen: targetScreen)
            } else {
                state.vIdx = verticalLayout.fullEdgeIndex + 1
                commit(ctx, state: state)
            }
        } else {
            state.vIdx += 1
            commit(ctx, state: state)
        }
    }

    // MARK: - Centered Mode

    func centerH(direction: CenterDirection) {
        guard let ctx = beginAction() else { return }
        var state = ctx.state

        // Off-grid window nearest a centered slot: first press snaps onto it — the
        // centering is the visible change, and it keeps the window's rough size.
        // Off-grid near an edge slot instead falls through: entering centered mode
        // from the inferred slot IS the visible first change there.
        if !ctx.onGrid && state.hCentered {
            return commit(ctx, state: state)
        }

        if !state.hCentered {
            state.hCentered = true
            state.hCenterIdx = horizontalLayout.edgeToCenter[state.hIdx] ?? 1
        } else {
            let count = horizontalLayout.centerPositions.count
            state.hCenterIdx = LayoutGeometry.cycledIndex(state.hCenterIdx, count: count, forward: direction == .shrink)
        }

        commit(ctx, state: state)
    }

    func centerV(direction: CenterDirection) {
        guard let ctx = beginAction() else { return }
        var state = ctx.state

        // Off-grid window nearest a centered slot: first press snaps onto it — the
        // centering is the visible change, and it keeps the window's rough size.
        // Off-grid near an edge slot instead falls through: entering centered mode
        // from the inferred slot IS the visible first change there.
        if !ctx.onGrid && state.vCentered {
            return commit(ctx, state: state)
        }

        if !state.vCentered {
            state.vCentered = true
            state.vCenterIdx = verticalLayout.edgeToCenter[state.vIdx] ?? 1
        } else {
            let count = verticalLayout.centerPositions.count
            state.vCenterIdx = LayoutGeometry.cycledIndex(state.vCenterIdx, count: count, forward: direction == .shrink)
        }

        commit(ctx, state: state)
    }

    // MARK: - Reset

    func resetWindow() {
        guard let ctx = beginAction() else { return }
        var state = ctx.state

        state.hIdx = horizontalLayout.fullEdgeIndex
        state.vIdx = verticalLayout.fullEdgeIndex
        state.hCentered = false
        state.vCentered = false
        state.hCenterIdx = 1
        state.vCenterIdx = 1

        commit(ctx, state: state)
    }

    // MARK: - Stack Cycling

    /// Tab: bring the next member of the focused window's stack forward. Only focus changes —
    /// the members already share one frame, so no window moves and nothing is re-laid out.
    func cycleZone(direction: CycleDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }

        synchronizeZoneMembership(for: windowID, window: window)

        guard let state = winState[windowID],
              let zoneKey = state.currentZone else { return }

        // Evictions can drop the stack to one window (losing its band) or change who is left.
        if reconcileZoneMembers(zoneKey: zoneKey, excluding: windowID) {
            layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
        }

        guard let windows = zoneWindows[zoneKey], windows.count > 1 else { return }

        // Step from the focused window — the visible one, whatever brought it forward — skipping
        // members that can't take focus (minimized since the last layout, or just closed:
        // focusing a minimized window would un-minimize it).
        var index = windows.firstIndex(of: windowID) ?? 0
        for _ in 1..<windows.count {
            index = StackMarkerLayout.step(index, count: windows.count, forward: direction == .forward)
            guard let next = engine.windowElement(for: windows[index]),
                  engine.presence(of: next) == .visible else { continue }
            bringForward(windows[index], window: next, zoneKey: zoneKey)
            return
        }
    }

    // MARK: - Cleanup

    private func cleanupStaleWindows() {
        // Runs on every exit: the engine's AX element cache only needs to hold windows we
        // track, so anything else (closed windows, windows only seen by a scan) goes here.
        defer { engine.pruneWindowElements(keeping: Set(winState.keys)) }
        guard !winState.isEmpty else { return }

        // One window-list copy for the whole sweep, not one per tracked window. An empty
        // list means the query failed (a live session always has the Dock/menu bar windows),
        // not that everything closed — don't wipe all state on it.
        let liveWindows = engine.liveWindowIDs()
        guard !liveWindows.isEmpty else { return }

        var deadWindows: [CGWindowID] = []
        var zonesToRefresh: Set<String> = []

        for (windowID, state) in winState where !liveWindows.contains(windowID) {
            deadWindows.append(windowID)
            if let zoneKey = state.currentZone {
                zonesToRefresh.insert(zoneKey)
            }
        }

        guard !deadWindows.isEmpty else { return }

        // The layout below re-applies frames, so first evict members the user has
        // moved by hand — before pruning changes the stacks' membership, while each
        // expected stack inset still reflects the stack as last laid out. The dead
        // members themselves fail their frame reads and are skipped, then pruned.
        for zoneKey in zonesToRefresh {
            reconcileZoneMembers(zoneKey: zoneKey)
        }

        for windowID in deadWindows {
            removeFromZone(windowID: windowID, zoneKey: winState[windowID]?.currentZone)
            winState[windowID] = nil
        }

        for zoneKey in zonesToRefresh where zoneWindows[zoneKey] != nil {
            layoutStack(zoneKey: zoneKey, shouldFocusFront: false)
        }
    }
}
