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

// MARK: - Window Manager

final class WindowManager {
    private let engine: WindowEngine
    private let screens: ScreenManager
    private let settingsStore: SettingsStore
    private let monitorOverflowEnabled = true

    private var horizontalLayout: AxisLayout
    private var verticalLayout: AxisLayout
    private var peekPixels: CGFloat

    // Per-window state
    private var winState: [CGWindowID: WindowState] = [:]

    // Zone tracking (accordion stacking)
    private var zoneWindows: [String: [CGWindowID]] = [:]

    // Cleanup timer
    private var cleanupTimer: Timer?
    private var settingsObserver: NSObjectProtocol?

    init(engine: WindowEngine, screens: ScreenManager, settingsStore: SettingsStore) {
        self.engine = engine
        self.screens = screens
        self.settingsStore = settingsStore

        let settings = settingsStore.snapshot
        horizontalLayout = AxisLayout.make(for: settings.snapProfile)
        verticalLayout = AxisLayout.make(for: settings.snapProfile)
        peekPixels = settings.peekSize.points

        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleWindows()
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
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
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

    /// A non-zoned window resting exactly on a slot where an accordion stack lives
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
    /// which case the first press rejoins it (`shouldRejoinStack`).
    ///
    /// `zoneVerified` is `synchronizeZoneMembership`'s return value: the zone
    /// fast-path is only sound when the sync actually read the frame this press.
    private func resolveState(
        for windowID: CGWindowID,
        window: AXUIElement,
        zoneVerified: Bool,
        edgeSnapAxis: ActionAxis? = nil
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

        if let tracked, framesApproximatelyEqual(actualFrame, frame(for: tracked, screenFrame: screenFrame)) {
            return (tracked, !shouldRejoinStack(tracked, windowID: windowID, actualFrame: actualFrame))
        }

        // The app refused or quantized our last snap (hard minimum size, line-height
        // rounding): the window can never physically match its slot, but the user
        // hasn't moved it — step from the tracked state instead of re-snapping to the
        // same slot forever.
        if let tracked, let settled = tracked.settledFrame,
           framesApproximatelyEqual(actualFrame, settled) {
            return (tracked, true)
        }

        var inferred = inferredState(from: actualFrame, screenFrame: screenFrame)
        inferred.currentZone = tracked?.currentZone
        if framesApproximatelyEqual(actualFrame, frame(for: inferred, screenFrame: screenFrame)) {
            return (inferred, !shouldRejoinStack(inferred, windowID: windowID, actualFrame: actualFrame))
        }

        // Off-grid: pick the snap target. Arrows keep their own axis on edge slots
        // (see `ActionAxis`); the cross axis still snaps to whatever is nearest.
        guard let edgeSnapAxis else { return (inferred, false) }
        var target = inferredState(
            from: actualFrame,
            screenFrame: screenFrame,
            hIncludeCentered: edgeSnapAxis != .horizontal,
            vIncludeCentered: edgeSnapAxis != .vertical
        )
        target.currentZone = tracked?.currentZone
        return (target, false)
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

        let newPeek = settings.peekSize.points

        if layoutChanged {
            peekPixels = newPeek
            winState.removeAll()
            zoneWindows.removeAll()
            return
        }

        if peekPixels != newPeek {
            // Members physically wear insets from the OLD peek size, so evict any the
            // user has moved while expected frames still match what was applied —
            // reconciling after the switch would mis-evict healthy members. Then
            // re-fan the survivors at the new size.
            for zoneKey in Array(zoneWindows.keys) {
                reconcileZoneMembers(zoneKey: zoneKey)
            }
            peekPixels = newPeek
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
        if zoneWindows[zoneKey]?.isEmpty == true {
            zoneWindows[zoneKey] = nil
        }
    }

    private func addToZone(windowID: CGWindowID, zoneKey: String) {
        if zoneWindows[zoneKey] == nil {
            zoneWindows[zoneKey] = []
        }
        zoneWindows[zoneKey]?.removeAll { $0 == windowID }
        zoneWindows[zoneKey]?.insert(windowID, at: 0)
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
        for zoneKey in zoneWindows.keys {
            applyPeekOffsets(zoneKey: zoneKey, shouldFocusFront: false)
        }
    }

    // MARK: - Frame Calculation

    private func frame(for state: WindowState, screenFrame: CGRect, peekInset: CGFloat = 0) -> CGRect {
        LayoutGeometry.frame(
            for: state,
            horizontal: horizontalLayout,
            vertical: verticalLayout,
            screenFrame: screenFrame,
            peekInset: peekInset
        )
    }

    private func applyFrame(window: AXUIElement, state: WindowState, targetScreen: NSScreen?, peekInset: CGFloat = 0) {
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

        engine.setFrame(window, frame: frame(for: state, screenFrame: screenFrame, peekInset: peekInset), visibleFrame: screenFrame)
    }

    private func peekInsetForWindow(windowID: CGWindowID, zoneKey: String) -> CGFloat {
        guard let windows = zoneWindows[zoneKey],
              let index = windows.firstIndex(of: windowID) else {
            return 0
        }

        return LayoutGeometry.peekInset(stackIndex: index, count: windows.count, peekPixels: peekPixels)
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        LayoutGeometry.framesApproximatelyEqual(lhs, rhs)
    }

    /// Whether a window physically sits where the manager last put it: on its expected
    /// slot frame, or — for apps that clamp/quantize our frames — on the frame it
    /// actually settled at after the last snap.
    private func isInPlace(actualFrame: CGRect, expectedFrame: CGRect, settledFrame: CGRect?) -> Bool {
        if framesApproximatelyEqual(actualFrame, expectedFrame) { return true }
        if let settledFrame { return framesApproximatelyEqual(actualFrame, settledFrame) }
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
        // from the zone (consistent with applyPeekOffsets) and let the rest re-fan.
        if engine.isMinimized(window) {
            evictFromZone(windowID: windowID, zoneKey: oldZone)
            applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
            return true
        }

        guard let actualFrame = engine.getFrame(window),
              let screenFrame = screens.screenFrame(for: actualFrame) else {
            return false
        }

        let expectedFrame = frame(
            for: state,
            screenFrame: screenFrame,
            peekInset: peekInsetForWindow(windowID: windowID, zoneKey: oldZone)
        )

        guard isInPlace(actualFrame: actualFrame, expectedFrame: expectedFrame, settledFrame: state.settledFrame) else {
            evictFromZone(windowID: windowID, zoneKey: oldZone)
            applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
            return true
        }

        let liveZone = getZoneKey(state: state, screenID: screens.screenID(for: actualFrame))
        guard liveZone != oldZone else { return true }

        removeFromZone(windowID: windowID, zoneKey: oldZone)
        addToZone(windowID: windowID, zoneKey: liveZone)
        state.currentZone = liveZone
        winState[windowID] = state
        applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
        applyPeekOffsets(zoneKey: liveZone, shouldFocusFront: false)
        return true
    }

    /// Evict from a stack any tracked member (minus the window being acted on) that
    /// the user has moved, resized, or minimized since the stack was last laid out.
    /// Pure bookkeeping — no frames are applied here, callers re-fan once afterwards —
    /// so one member's eviction can't disturb the checks, or the placement, of the
    /// members after it. All expected frames are computed before the first eviction,
    /// while each member's peek inset still reflects the stack as last laid out; for
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
            let expectedFrame = frame(
                for: state,
                screenFrame: screenFrame,
                peekInset: peekInsetForWindow(windowID: memberID, zoneKey: zoneKey)
            )
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

    // MARK: - Accordion Stacking

    private func applyPeekOffsets(zoneKey: String, shouldFocusFront: Bool = true) {
        guard let windowIDs = zoneWindows[zoneKey] else { return }

        // Resolve members, evicting any that are minimized: applying a frame, raising,
        // or focusing a Dock-minimized window un-minimizes it. Evicting (rather than
        // keeping it parked in the zone) keeps the layout deterministic — peek insets
        // are then re-indexed over the visible members only.
        //
        // Intended consequence, not a bug: a minimized window leaves its accordion. If the
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
            if engine.isMinimized(window) {
                evictFromZone(windowID: windowID, zoneKey: zoneKey)
                continue
            }
            visible.append((window: window, id: windowID))
        }

        // No member exists anymore (all closed) — tear the zone down.
        guard sawExisting else {
            zoneWindows[zoneKey] = nil
            return
        }

        // Members exist but all are minimized — nothing to lay out. Don't nil the zone
        // here; removeFromZone above already nils it if it emptied, and any still-tracked
        // window may be re-snapped later.
        guard !visible.isEmpty else { return }

        let count = visible.count
        for (visibleIndex, entry) in visible.enumerated() {
            let inset = LayoutGeometry.peekInset(stackIndex: visibleIndex, count: count, peekPixels: peekPixels)
            applyFrame(window: entry.window, state: winState[entry.id]!, targetScreen: nil, peekInset: inset)
        }

        // Raise only when the front changed (a member joined, or Tab cycled) — the
        // shouldFocusFront calls. Maintenance re-fans (member left/evicted, peek size
        // change, cleanup) keep the survivors' relative order, so re-raising would only
        // hoist the stack above unrelated windows — and bury the front member, since the
        // loop raises back-to-front and skips index 0 on the assumption it gets focused.
        // The one maintenance fan that DOES change a front — zone migration in
        // synchronizeZoneMembership — fronts the focused window, which is already
        // topmost, so it needs no raise either.
        guard shouldFocusFront else { return }

        for (visibleIndex, entry) in visible.enumerated().reversed() where visibleIndex > 0 {
            engine.raise(entry.window)
        }

        if let front = visible.first {
            engine.focus(front.window)
        }
    }

    private func finishMove(window: AXUIElement, windowID: CGWindowID, oldZone: String?, targetScreen: NSScreen?) {
        if let targetScreen {
            let targetFrame = screens.visibleFrame(of: targetScreen)
            // A transient nudge onto the destination screen carrying the window's current size;
            // applyPeekOffsets immediately resets it to the real slot, so skip the on-screen clamp.
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
        // its old slot — possibly on another screen — when the fans below re-apply
        // frames. Reconcile (bookkeeping only) before membership changes; the single
        // re-fan per zone afterwards lays out the survivors.
        reconcileZoneMembers(zoneKey: oldZone, excluding: windowID)
        if newZone != oldZone {
            reconcileZoneMembers(zoneKey: newZone, excluding: windowID)
        }

        removeFromZone(windowID: windowID, zoneKey: oldZone)
        addToZone(windowID: windowID, zoneKey: newZone)
        winState[windowID]?.currentZone = newZone

        if let oldZone, oldZone != newZone {
            applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
        }
        applyPeekOffsets(zoneKey: newZone)

        // Where the window actually landed: apps with hard minimums or quantized
        // sizing settle off-slot, and this is what lets the next press tell "the app
        // refused our frame" from "the user moved the window" (see resolveState and
        // synchronizeZoneMembership).
        winState[windowID]?.settledFrame = engine.getFrame(window)
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
    private func beginAction(edgeSnapAxis: ActionAxis? = nil) -> ActionContext? {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return nil }
        let zoneVerified = synchronizeZoneMembership(for: windowID, window: window)
        let resolved = resolveState(
            for: windowID,
            window: window,
            zoneVerified: zoneVerified,
            edgeSnapAxis: edgeSnapAxis
        )
        return ActionContext(window: window, windowID: windowID, state: resolved.state, onGrid: resolved.onGrid)
    }

    private func commit(_ ctx: ActionContext, state: WindowState, targetScreen: NSScreen? = nil) {
        winState[ctx.windowID] = state
        finishMove(window: ctx.window, windowID: ctx.windowID, oldZone: ctx.oldZone, targetScreen: targetScreen)
    }

    // MARK: - Edge-snap Movement

    func moveLeft() {
        guard let ctx = beginAction(edgeSnapAxis: .horizontal) else { return }
        var state = ctx.state

        // Off-grid window: first press snaps onto the nearest slot (rejoining any
        // stack living there); cycling continues from the next press.
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
        guard let ctx = beginAction(edgeSnapAxis: .horizontal) else { return }
        var state = ctx.state

        // Off-grid window: first press snaps onto the nearest slot (rejoining any
        // stack living there); cycling continues from the next press.
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
        guard let ctx = beginAction(edgeSnapAxis: .vertical) else { return }
        var state = ctx.state

        // Off-grid window: first press snaps onto the nearest slot (rejoining any
        // stack living there); cycling continues from the next press.
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
        guard let ctx = beginAction(edgeSnapAxis: .vertical) else { return }
        var state = ctx.state

        // Off-grid window: first press snaps onto the nearest slot (rejoining any
        // stack living there); cycling continues from the next press.
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

    // MARK: - Accordion Cycling

    func cycleZone(direction: CycleDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }

        synchronizeZoneMembership(for: windowID, window: window)

        guard let state = winState[windowID],
              let zoneKey = state.currentZone else { return }

        let evictedAny = reconcileZoneMembers(zoneKey: zoneKey, excluding: windowID)

        guard var windows = zoneWindows[zoneKey], windows.count > 1 else {
            // Evictions shrank the stack to just this window — re-fan to drop its inset.
            if evictedAny {
                applyPeekOffsets(zoneKey: zoneKey, shouldFocusFront: false)
            }
            return
        }

        switch direction {
        case .forward:
            let front = windows.removeFirst()
            windows.append(front)
        case .backward:
            let back = windows.removeLast()
            windows.insert(back, at: 0)
        }

        zoneWindows[zoneKey] = windows

        // applyPeekOffsets focuses the front (first visible) member. Don't focus
        // windows[0] directly here — after rotation it may be a minimized member,
        // and focusing a minimized window un-minimizes it.
        applyPeekOffsets(zoneKey: zoneKey)
    }

    // MARK: - Cleanup

    private func cleanupStaleWindows() {
        var deadWindows: [CGWindowID] = []
        var zonesToRefresh: Set<String> = []

        for (windowID, state) in winState where !engine.windowExists(windowID) {
            deadWindows.append(windowID)
            if let zoneKey = state.currentZone {
                zonesToRefresh.insert(zoneKey)
            }
        }

        guard !deadWindows.isEmpty else { return }

        // The re-fan below re-applies frames, so first evict members the user has
        // moved by hand — before pruning changes the stacks' membership, while each
        // expected peek inset still reflects the stack as last laid out. The dead
        // members themselves fail their frame reads and are skipped, then pruned.
        for zoneKey in zonesToRefresh {
            reconcileZoneMembers(zoneKey: zoneKey)
        }

        for windowID in deadWindows {
            removeFromZone(windowID: windowID, zoneKey: winState[windowID]?.currentZone)
            winState[windowID] = nil
            engine.forgetWindowElement(for: windowID)
        }

        for zoneKey in zonesToRefresh where zoneWindows[zoneKey] != nil {
            applyPeekOffsets(zoneKey: zoneKey, shouldFocusFront: false)
        }
    }
}
