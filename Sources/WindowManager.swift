import AppKit
import ApplicationServices

// MARK: - Data Types

enum CycleDirection {
    case forward, backward
}

enum CenterDirection {
    case shrink, grow
}

struct PositionEntry {
    let offset: CGFloat
    let size: CGFloat
}

struct WindowState {
    var hIdx: Int
    var vIdx: Int
    var hCentered: Bool = false
    var vCentered: Bool = false
    var hCenterIdx: Int = 1
    var vCenterIdx: Int = 1
    var currentZone: String?
}

private struct AxisLayout {
    let edgePositions: [PositionEntry]
    let centerPositions: [PositionEntry]
    let edgeToCenter: [Int: Int]
    let centerToLeading: [Int: Int]
    let centerToTrailing: [Int: Int]
    let fullEdgeIndex: Int

    var maxEdgeIndex: Int {
        edgePositions.count
    }

    static func make(for profile: SnapProfile) -> AxisLayout {
        let fractions = profile.availableFractions
        let fullEdgeIndex = fractions.count + 1

        var edgePositions = fractions.map { PositionEntry(offset: 0, size: $0) }
        edgePositions.append(PositionEntry(offset: 0, size: 1))
        edgePositions.append(contentsOf: fractions.reversed().map { PositionEntry(offset: 1 - $0, size: $0) })

        var centerPositions = [PositionEntry(offset: 0, size: 1)]
        centerPositions.append(contentsOf: fractions.reversed().map { PositionEntry(offset: (1 - $0) / 2, size: $0) })

        let centerIndexBySize = Dictionary(uniqueKeysWithValues: fractions.reversed().enumerated().map { ($1, $0 + 2) })
        let leadingIndexBySize = Dictionary(uniqueKeysWithValues: fractions.enumerated().map { ($1, $0 + 1) })
        let trailingIndexBySize = Dictionary(uniqueKeysWithValues: fractions.reversed().enumerated().map { ($1, fullEdgeIndex + $0 + 1) })

        var edgeToCenter: [Int: Int] = [fullEdgeIndex: 1]
        var centerToLeading: [Int: Int] = [1: fullEdgeIndex]
        var centerToTrailing: [Int: Int] = [1: fullEdgeIndex]

        for fraction in fractions {
            guard let centerIndex = centerIndexBySize[fraction],
                  let leadingIndex = leadingIndexBySize[fraction],
                  let trailingIndex = trailingIndexBySize[fraction] else {
                continue
            }

            edgeToCenter[leadingIndex] = centerIndex
            edgeToCenter[trailingIndex] = centerIndex
            centerToLeading[centerIndex] = leadingIndex
            centerToTrailing[centerIndex] = trailingIndex
        }

        return AxisLayout(
            edgePositions: edgePositions,
            centerPositions: centerPositions,
            edgeToCenter: edgeToCenter,
            centerToLeading: centerToLeading,
            centerToTrailing: centerToTrailing,
            fullEdgeIndex: fullEdgeIndex
        )
    }
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
        let horizontalEntry = state.hCentered
            ? horizontalLayout.centerPositions[state.hCenterIdx - 1]
            : horizontalLayout.edgePositions[state.hIdx - 1]

        let verticalEntry = state.vCentered
            ? verticalLayout.centerPositions[state.vCenterIdx - 1]
            : verticalLayout.edgePositions[state.vIdx - 1]

        return CGRect(
            x: screenFrame.origin.x + screenFrame.width * horizontalEntry.offset,
            y: screenFrame.origin.y + screenFrame.height * verticalEntry.offset + peekInset,
            width: screenFrame.width * horizontalEntry.size,
            height: screenFrame.height * verticalEntry.size - peekInset
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

        engine.setFrame(window, frame: frame(for: state, screenFrame: screenFrame, peekInset: peekInset))
    }

    private func peekInsetForWindow(windowID: CGWindowID, zoneKey: String) -> CGFloat {
        guard let windows = zoneWindows[zoneKey],
              let index = windows.firstIndex(of: windowID) else {
            return 0
        }

        return CGFloat(windows.count - 1 - index) * peekPixels
    }

    private func framesApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 6) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) <= tolerance
            && abs(lhs.origin.y - rhs.origin.y) <= tolerance
            && abs(lhs.size.width - rhs.size.width) <= tolerance
            && abs(lhs.size.height - rhs.size.height) <= tolerance
    }

    private func synchronizeZoneMembership(for windowID: CGWindowID, window: AXUIElement) {
        guard var state = winState[windowID],
              let oldZone = state.currentZone,
              let actualFrame = engine.getFrame(window),
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

    // MARK: - Accordion Stacking

    private func applyPeekOffsets(zoneKey: String, shouldFocusFront: Bool = true) {
        guard let windowIDs = zoneWindows[zoneKey] else { return }

        var resolved: [(index: Int, window: AXUIElement, id: CGWindowID)] = []
        for (index, windowID) in windowIDs.enumerated() {
            if winState[windowID] != nil, let window = engine.windowElement(for: windowID) {
                resolved.append((index: index, window: window, id: windowID))
            }
        }

        let count = resolved.count
        guard count > 0 else {
            zoneWindows[zoneKey] = nil
            return
        }

        for entry in resolved {
            let inset = CGFloat(count - 1 - entry.index) * peekPixels
            applyFrame(window: entry.window, state: winState[entry.id]!, targetScreen: nil, peekInset: inset)
        }

        for entry in resolved.reversed() where entry.index > 0 {
            engine.raise(entry.window)
        }

        if shouldFocusFront, let front = resolved.first {
            engine.focus(front.window)
        }
    }

    private func finishMove(window: AXUIElement, windowID: CGWindowID, oldZone: String?, targetScreen: NSScreen?) {
        if let targetScreen {
            let targetFrame = screens.visibleFrame(of: targetScreen)
            engine.setFrame(window, frame: CGRect(
                origin: CGPoint(x: targetFrame.origin.x + 10, y: targetFrame.origin.y + 10),
                size: engine.getSize(window) ?? CGSize(width: 800, height: 600)
            ))
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

        var state = getState(for: windowID)
        let oldZone = state.currentZone

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

        var state = getState(for: windowID)
        let oldZone = state.currentZone

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

        var state = getState(for: windowID)
        let oldZone = state.currentZone

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

        var state = getState(for: windowID)
        let oldZone = state.currentZone

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

        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if !state.hCentered {
            state.hCentered = true
            state.hCenterIdx = horizontalLayout.edgeToCenter[state.hIdx] ?? 1
        } else {
            switch direction {
            case .shrink:
                state.hCenterIdx = state.hCenterIdx == horizontalLayout.centerPositions.count ? 1 : state.hCenterIdx + 1
            case .grow:
                state.hCenterIdx = state.hCenterIdx == 1 ? horizontalLayout.centerPositions.count : state.hCenterIdx - 1
            }
        }

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    func centerV(direction: CenterDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        synchronizeZoneMembership(for: windowID, window: window)

        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if !state.vCentered {
            state.vCentered = true
            state.vCenterIdx = verticalLayout.edgeToCenter[state.vIdx] ?? 1
        } else {
            switch direction {
            case .shrink:
                state.vCenterIdx = state.vCenterIdx == verticalLayout.centerPositions.count ? 1 : state.vCenterIdx + 1
            case .grow:
                state.vCenterIdx = state.vCenterIdx == 1 ? verticalLayout.centerPositions.count : state.vCenterIdx - 1
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

        if let windowIDs = zoneWindows[zoneKey] {
            for trackedWindowID in windowIDs where trackedWindowID != windowID {
                if let trackedWindow = engine.windowElement(for: trackedWindowID) {
                    synchronizeZoneMembership(for: trackedWindowID, window: trackedWindow)
                }
            }
        }

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

        if let frontWindow = engine.windowElement(for: windows[0]) {
            engine.focus(frontWindow)
        }
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
