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

    private func getState(for windowID: CGWindowID) -> WindowState {
        if winState[windowID] == nil {
            winState[windowID] = makeInitialState()
        }
        return winState[windowID]!
    }

    /// The snap state whose slots most closely match a window's actual frame, so an
    /// off-grid window enters the cycle from wherever the user left it.
    private func inferredState(from actualFrame: CGRect, screenFrame: CGRect) -> WindowState {
        let h = LayoutGeometry.nearestSlot(
            offset: (actualFrame.minX - screenFrame.minX) / screenFrame.width,
            size: actualFrame.width / screenFrame.width,
            in: horizontalLayout
        )
        let v = LayoutGeometry.nearestSlot(
            offset: (actualFrame.minY - screenFrame.minY) / screenFrame.height,
            size: actualFrame.height / screenFrame.height,
            in: verticalLayout
        )
        return WindowState(
            hIdx: h.centered ? (horizontalLayout.centerToLeading[h.index] ?? horizontalLayout.fullEdgeIndex) : h.index,
            vIdx: v.centered ? (verticalLayout.centerToLeading[v.index] ?? verticalLayout.fullEdgeIndex) : v.index,
            hCentered: h.centered,
            vCentered: v.centered,
            hCenterIdx: h.centered ? h.index : 1,
            vCenterIdx: v.centered ? v.index : 1
        )
    }

    /// The state a window action starts from. A window whose tracked state matches its
    /// actual frame is on-grid and cycles normally. A window that is untracked — or was
    /// moved/resized by hand since it was last snapped — instead gets a state inferred
    /// from its geometry, and `onGrid: false` tells the caller the first press should
    /// snap to that nearest slot rather than step beyond it. `onGrid: true` with an
    /// inferred state means the user parked the window exactly on a slot, so a step
    /// from there is never a visible no-op.
    private func resolveState(for windowID: CGWindowID, window: AXUIElement) -> (state: WindowState, onGrid: Bool) {
        let tracked = winState[windowID]

        // Still in a zone: synchronizeZoneMembership just verified frame == slot.
        if let tracked, tracked.currentZone != nil {
            return (tracked, true)
        }

        guard let actualFrame = engine.getFrame(window),
              let screenFrame = screens.screenFrame(for: actualFrame) else {
            return (tracked ?? makeInitialState(), true)
        }

        if let tracked, framesApproximatelyEqual(actualFrame, frame(for: tracked, screenFrame: screenFrame)) {
            return (tracked, true)
        }

        let inferred = inferredState(from: actualFrame, screenFrame: screenFrame)
        let onGrid = framesApproximatelyEqual(actualFrame, frame(for: inferred, screenFrame: screenFrame))
        return (inferred, onGrid)
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

        let previousPeek = peekPixels
        peekPixels = settings.peekSize.points

        if layoutChanged {
            winState.removeAll()
            zoneWindows.removeAll()
            return
        }

        if previousPeek != peekPixels {
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

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func synchronizeZoneMembership(for windowID: CGWindowID, window: AXUIElement) {
        guard var state = winState[windowID],
              let oldZone = state.currentZone else {
            return
        }

        // A minimized member reports a stale frame; don't reconcile against it. Evict it
        // from the zone (consistent with applyPeekOffsets) and let the rest re-fan.
        if engine.isMinimized(window) {
            removeFromZone(windowID: windowID, zoneKey: oldZone)
            state.currentZone = nil
            winState[windowID] = state
            applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
            return
        }

        guard let actualFrame = engine.getFrame(window),
              let screenFrame = screens.screenFrame(for: actualFrame) else {
            return
        }

        let expectedFrame = frame(
            for: state,
            screenFrame: screenFrame,
            peekInset: peekInsetForWindow(windowID: windowID, zoneKey: oldZone)
        )
        let liveZone = getZoneKey(state: state, screenID: screens.screenID(for: actualFrame))

        guard framesApproximatelyEqual(actualFrame, expectedFrame) else {
            removeFromZone(windowID: windowID, zoneKey: oldZone)
            state.currentZone = nil
            winState[windowID] = state
            applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
            return
        }

        guard liveZone != oldZone else { return }

        removeFromZone(windowID: windowID, zoneKey: oldZone)
        addToZone(windowID: windowID, zoneKey: liveZone)
        state.currentZone = liveZone
        winState[windowID] = state
        applyPeekOffsets(zoneKey: oldZone, shouldFocusFront: false)
        applyPeekOffsets(zoneKey: liveZone, shouldFocusFront: false)
    }

    /// Run `synchronizeZoneMembership` over a zone's tracked members (minus the window
    /// being acted on), evicting any the user has moved or resized manually. Must run
    /// before the zone's membership changes, while each member's expected peek inset
    /// still reflects the stack as it was last laid out.
    private func reconcileZoneMembers(zoneKey: String?, excluding excludedID: CGWindowID) {
        guard let zoneKey, let members = zoneWindows[zoneKey] else { return }
        for memberID in members where memberID != excludedID {
            guard let memberWindow = engine.windowElement(for: memberID) else { continue }
            synchronizeZoneMembership(for: memberID, window: memberWindow)
        }
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
                removeFromZone(windowID: windowID, zoneKey: zoneKey)
                winState[windowID]?.currentZone = nil
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
        // shouldFocusFront calls. Maintenance re-fans (member left, peek size change,
        // cleanup) preserve the stack's relative order, so re-raising would only hoist
        // the stack above unrelated windows — and bury the front member, since the loop
        // raises back-to-front and skips index 0 on the assumption it gets focused.
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
        // its old slot — possibly on another screen — when this fan re-applies frames.
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
    }

    // MARK: - Edge-snap Movement

    func moveLeft() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        let resolved = resolveState(for: windowID, window: window)
        var state = resolved.state
        let oldZone = state.currentZone

        // Off-grid window: first press snaps onto the nearest slot; cycling continues from there.
        if !resolved.onGrid {
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.hCentered {
            state.hCentered = false
            state.hIdx = horizontalLayout.centerToLeading[state.hCenterIdx] ?? horizontalLayout.fullEdgeIndex
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.hIdx == 1 {
            if monitorOverflowEnabled,
               let position = engine.getPosition(window),
               let targetScreen = screens.screenToWest(of: position) {
                state.hIdx = horizontalLayout.fullEdgeIndex + 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: targetScreen)
            } else {
                state.hIdx = horizontalLayout.fullEdgeIndex - 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            }
        } else {
            state.hIdx -= 1
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
        }
    }

    func moveRight() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        let resolved = resolveState(for: windowID, window: window)
        var state = resolved.state
        let oldZone = state.currentZone

        // Off-grid window: first press snaps onto the nearest slot; cycling continues from there.
        if !resolved.onGrid {
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.hCentered {
            state.hCentered = false
            state.hIdx = horizontalLayout.centerToTrailing[state.hCenterIdx] ?? horizontalLayout.fullEdgeIndex
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.hIdx == horizontalLayout.maxEdgeIndex {
            if monitorOverflowEnabled,
               let position = engine.getPosition(window),
               let targetScreen = screens.screenToEast(of: position) {
                state.hIdx = horizontalLayout.fullEdgeIndex - 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: targetScreen)
            } else {
                state.hIdx = horizontalLayout.fullEdgeIndex + 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            }
        } else {
            state.hIdx += 1
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
        }
    }

    func moveUp() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        let resolved = resolveState(for: windowID, window: window)
        var state = resolved.state
        let oldZone = state.currentZone

        // Off-grid window: first press snaps onto the nearest slot; cycling continues from there.
        if !resolved.onGrid {
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.vCentered {
            state.vCentered = false
            state.vIdx = verticalLayout.centerToLeading[state.vCenterIdx] ?? verticalLayout.fullEdgeIndex
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.vIdx == 1 {
            if monitorOverflowEnabled,
               let position = engine.getPosition(window),
               let targetScreen = screens.screenToNorth(of: position) {
                state.vIdx = verticalLayout.fullEdgeIndex + 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: targetScreen)
            } else {
                state.vIdx = verticalLayout.fullEdgeIndex - 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            }
        } else {
            state.vIdx -= 1
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
        }
    }

    func moveDown() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        let resolved = resolveState(for: windowID, window: window)
        var state = resolved.state
        let oldZone = state.currentZone

        // Off-grid window: first press snaps onto the nearest slot; cycling continues from there.
        if !resolved.onGrid {
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.vCentered {
            state.vCentered = false
            state.vIdx = verticalLayout.centerToTrailing[state.vCenterIdx] ?? verticalLayout.fullEdgeIndex
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.vIdx == verticalLayout.maxEdgeIndex {
            if monitorOverflowEnabled,
               let position = engine.getPosition(window),
               let targetScreen = screens.screenToSouth(of: position) {
                state.vIdx = verticalLayout.fullEdgeIndex - 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: targetScreen)
            } else {
                state.vIdx = verticalLayout.fullEdgeIndex + 1
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            }
        } else {
            state.vIdx += 1
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
        }
    }

    // MARK: - Centered Mode

    func centerH(direction: CenterDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        // Center commands always step: starting from the inferred nearest slot keeps the
        // window's rough size, and the centering itself is the visible first change.
        var state = resolveState(for: windowID, window: window).state
        let oldZone = state.currentZone

        if !state.hCentered {
            state.hCentered = true
            state.hCenterIdx = horizontalLayout.edgeToCenter[state.hIdx] ?? 1
        } else {
            let count = horizontalLayout.centerPositions.count
            switch direction {
            case .shrink:
                state.hCenterIdx = LayoutGeometry.cycledIndex(state.hCenterIdx, count: count, forward: true)
            case .grow:
                state.hCenterIdx = LayoutGeometry.cycledIndex(state.hCenterIdx, count: count, forward: false)
            }
        }

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    func centerV(direction: CenterDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        // Center commands always step: starting from the inferred nearest slot keeps the
        // window's rough size, and the centering itself is the visible first change.
        var state = resolveState(for: windowID, window: window).state
        let oldZone = state.currentZone

        if !state.vCentered {
            state.vCentered = true
            state.vCenterIdx = verticalLayout.edgeToCenter[state.vIdx] ?? 1
        } else {
            let count = verticalLayout.centerPositions.count
            switch direction {
            case .shrink:
                state.vCenterIdx = LayoutGeometry.cycledIndex(state.vCenterIdx, count: count, forward: true)
            case .grow:
                state.vCenterIdx = LayoutGeometry.cycledIndex(state.vCenterIdx, count: count, forward: false)
            }
        }

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    // MARK: - Reset

    func resetWindow() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        var state = getState(for: windowID)
        let oldZone = state.currentZone

        state.hIdx = horizontalLayout.fullEdgeIndex
        state.vIdx = verticalLayout.fullEdgeIndex
        state.hCentered = false
        state.vCentered = false
        state.hCenterIdx = 1
        state.vCenterIdx = 1

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    // MARK: - Accordion Cycling

    func cycleZone(direction: CycleDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }

        synchronizeZoneMembership(for: windowID, window: window)

        guard let state = winState[windowID],
              let zoneKey = state.currentZone else { return }

        reconcileZoneMembers(zoneKey: zoneKey, excluding: windowID)

        guard var windows = zoneWindows[zoneKey], windows.count > 1 else { return }

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
        var zonesToRefresh: Set<String> = []

        for (windowID, state) in winState {
            if !engine.windowExists(windowID) {
                if let zoneKey = state.currentZone {
                    removeFromZone(windowID: windowID, zoneKey: zoneKey)
                    if zoneWindows[zoneKey] != nil {
                        zonesToRefresh.insert(zoneKey)
                    }
                }
                winState[windowID] = nil
            }
        }

        for zoneKey in zonesToRefresh {
            applyPeekOffsets(zoneKey: zoneKey, shouldFocusFront: false)
        }
    }
}
