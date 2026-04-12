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
    let offset: CGFloat  // x or y fraction
    let size: CGFloat    // w or h fraction
}

struct WindowState {
    var hIdx: Int = 6          // 1-11, index into hPos
    var vIdx: Int = 6          // 1-11, index into vPos
    var hCentered: Bool = false
    var vCentered: Bool = false
    var hCenterIdx: Int = 1    // 1-6, index into hCenterPos
    var vCenterIdx: Int = 1    // 1-6, index into vCenterPos
    var currentZone: String?   // zone key this window is registered in
}

// MARK: - Window Manager

final class WindowManager {
    private let engine: WindowEngine
    private let screens: ScreenManager

    // Position tables
    private let hPos: [PositionEntry] = [
        PositionEntry(offset: 0,     size: 1.0/4),  // 1:  left quarter
        PositionEntry(offset: 0,     size: 1.0/3),  // 2:  left third
        PositionEntry(offset: 0,     size: 1.0/2),  // 3:  left half
        PositionEntry(offset: 0,     size: 2.0/3),  // 4:  left two thirds
        PositionEntry(offset: 0,     size: 3.0/4),  // 5:  left three quarters
        PositionEntry(offset: 0,     size: 1),       // 6:  full width
        PositionEntry(offset: 1.0/4, size: 3.0/4),  // 7:  right three quarters
        PositionEntry(offset: 1.0/3, size: 2.0/3),  // 8:  right two thirds
        PositionEntry(offset: 1.0/2, size: 1.0/2),  // 9:  right half
        PositionEntry(offset: 2.0/3, size: 1.0/3),  // 10: right third
        PositionEntry(offset: 3.0/4, size: 1.0/4),  // 11: right quarter
    ]

    private let vPos: [PositionEntry] = [
        PositionEntry(offset: 0,     size: 1.0/4),  // 1:  top quarter
        PositionEntry(offset: 0,     size: 1.0/3),  // 2:  top third
        PositionEntry(offset: 0,     size: 1.0/2),  // 3:  top half
        PositionEntry(offset: 0,     size: 2.0/3),  // 4:  top two thirds
        PositionEntry(offset: 0,     size: 3.0/4),  // 5:  top three quarters
        PositionEntry(offset: 0,     size: 1),       // 6:  full height
        PositionEntry(offset: 1.0/4, size: 3.0/4),  // 7:  bottom three quarters
        PositionEntry(offset: 1.0/3, size: 2.0/3),  // 8:  bottom two thirds
        PositionEntry(offset: 1.0/2, size: 1.0/2),  // 9:  bottom half
        PositionEntry(offset: 2.0/3, size: 1.0/3),  // 10: bottom third
        PositionEntry(offset: 3.0/4, size: 1.0/4),  // 11: bottom quarter
    ]

    private let hCenterPos: [PositionEntry] = [
        PositionEntry(offset: 0,     size: 1),       // 1: full width
        PositionEntry(offset: 1.0/8, size: 3.0/4),  // 2: centered 3/4
        PositionEntry(offset: 1.0/6, size: 2.0/3),  // 3: centered 2/3
        PositionEntry(offset: 1.0/4, size: 1.0/2),  // 4: centered 1/2
        PositionEntry(offset: 1.0/3, size: 1.0/3),  // 5: centered 1/3
        PositionEntry(offset: 3.0/8, size: 1.0/4),  // 6: centered 1/4
    ]

    private let vCenterPos: [PositionEntry] = [
        PositionEntry(offset: 0,     size: 1),       // 1: full height
        PositionEntry(offset: 1.0/8, size: 3.0/4),  // 2: centered 3/4
        PositionEntry(offset: 1.0/6, size: 2.0/3),  // 3: centered 2/3
        PositionEntry(offset: 1.0/4, size: 1.0/2),  // 4: centered 1/2
        PositionEntry(offset: 1.0/3, size: 1.0/3),  // 5: centered 1/3
        PositionEntry(offset: 3.0/8, size: 1.0/4),  // 6: centered 1/4
    ]

    // Mapping tables
    private let edgeToCenterH: [Int: Int] = [1:6, 2:5, 3:4, 4:3, 5:2, 6:1, 7:2, 8:3, 9:4, 10:5, 11:6]
    private let edgeToCenterV: [Int: Int] = [1:6, 2:5, 3:4, 4:3, 5:2, 6:1, 7:2, 8:3, 9:4, 10:5, 11:6]

    private let centerToEdgeLeft:  [Int: Int] = [1:6, 2:5, 3:4, 4:3, 5:2, 6:1]
    private let centerToEdgeRight: [Int: Int] = [1:6, 2:7, 3:8, 4:9, 5:10, 6:11]
    private let centerToEdgeUp:    [Int: Int] = [1:6, 2:5, 3:4, 4:3, 5:2, 6:1]
    private let centerToEdgeDown:  [Int: Int] = [1:6, 2:7, 3:8, 4:9, 5:10, 6:11]

    // Per-window state
    private var winState: [CGWindowID: WindowState] = [:]

    // Zone tracking (accordion stacking)
    private let PEEK_PX: CGFloat = 8
    private var zoneWindows: [String: [CGWindowID]] = [:]  // zone key -> ordered window IDs (index 0 = front)

    // Cleanup timer
    private var cleanupTimer: Timer?

    init(engine: WindowEngine, screens: ScreenManager) {
        self.engine = engine
        self.screens = screens

        // Periodic cleanup of stale window entries
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.cleanupStaleWindows()
        }
    }

    // MARK: - State Management

    private func getState(for windowID: CGWindowID) -> WindowState {
        if winState[windowID] == nil {
            winState[windowID] = WindowState()
        }
        return winState[windowID]!
    }

    // MARK: - Zone Tracking

    private func getZoneKey(state: WindowState, screenID: String) -> String {
        let hPart: String
        if state.hCentered {
            hPart = "ch\(state.hCenterIdx)"
        } else {
            hPart = "h\(state.hIdx)"
        }
        let vPart: String
        if state.vCentered {
            vPart = "cv\(state.vCenterIdx)"
        } else {
            vPart = "v\(state.vIdx)"
        }
        return "\(screenID)_\(hPart)_\(vPart)"
    }

    private func removeFromZone(windowID: CGWindowID, zoneKey: String?) {
        guard let zoneKey = zoneKey, zoneWindows[zoneKey] != nil else { return }
        zoneWindows[zoneKey]?.removeAll { $0 == windowID }
        if zoneWindows[zoneKey]?.isEmpty == true {
            zoneWindows[zoneKey] = nil
        }
    }

    private func addToZone(windowID: CGWindowID, zoneKey: String) {
        if zoneWindows[zoneKey] == nil {
            zoneWindows[zoneKey] = []
        }
        // Add to front of the stack
        zoneWindows[zoneKey]!.insert(windowID, at: 0)
    }

    // MARK: - Frame Application

    /// Apply frame to a window based on its state.
    /// peekInset: pixels to shave off the top for accordion stacking peek.
    private func applyFrame(window: AXUIElement, windowID: CGWindowID, state: WindowState, targetScreen: NSScreen?, peekInset: CGFloat = 0) {
        let screenFrame: CGRect
        if let target = targetScreen {
            screenFrame = screens.visibleFrame(of: target)
        } else if let pos = engine.getPosition(window),
                  let frame = screens.screenFrame(for: pos) {
            screenFrame = frame
        } else {
            return
        }

        let hx: CGFloat, hw: CGFloat
        if state.hCentered {
            let c = hCenterPos[state.hCenterIdx - 1]  // 1-based to 0-based
            hx = c.offset; hw = c.size
        } else {
            let h = hPos[state.hIdx - 1]  // 1-based to 0-based
            hx = h.offset; hw = h.size
        }

        let vy: CGFloat, vh: CGFloat
        if state.vCentered {
            let c = vCenterPos[state.vCenterIdx - 1]
            vy = c.offset; vh = c.size
        } else {
            let v = vPos[state.vIdx - 1]
            vy = v.offset; vh = v.size
        }

        let frame = CGRect(
            x: screenFrame.origin.x + screenFrame.width * hx,
            y: screenFrame.origin.y + screenFrame.height * vy + peekInset,
            width: screenFrame.width * hw,
            height: screenFrame.height * vh - peekInset
        )

        engine.setFrame(window, frame: frame)
    }

    /// Reposition all windows in a zone with peek offsets (accordion stacking).
    private func applyPeekOffsets(zoneKey: String) {
        guard let windowIDs = zoneWindows[zoneKey] else { return }
        let count = windowIDs.count

        // Resolve all window AXUIElements
        var resolved: [(index: Int, window: AXUIElement, id: CGWindowID)] = []
        for (i, wid) in windowIDs.enumerated() {
            if winState[wid] != nil, let axWindow = engine.windowElement(for: wid) {
                resolved.append((index: i, window: axWindow, id: wid))
            }
        }

        // 1. Set all frames: back windows are taller, front is shortest
        for entry in resolved {
            let layer = entry.index
            let inset = CGFloat(count - 1 - layer) * PEEK_PX
            applyFrame(window: entry.window, windowID: entry.id, state: winState[entry.id]!, targetScreen: nil, peekInset: inset)
        }

        // 2. Raise background windows back-to-front for correct z-ordering
        for entry in resolved.reversed() {
            if entry.index > 0 {
                engine.raise(entry.window)
            }
        }

        // 3. Focus only the front window
        if let front = resolved.first(where: { $0.index == 0 }) {
            engine.focus(front.window)
        }
    }

    /// Handle zone transition after state change.
    private func finishMove(window: AXUIElement, windowID: CGWindowID, oldZone: String?, targetScreen: NSScreen?) {
        // For monitor overflow, move window to target screen first
        if let target = targetScreen {
            let targetFrame = screens.visibleFrame(of: target)
            engine.setFrame(window, frame: CGRect(
                origin: CGPoint(x: targetFrame.origin.x + 10, y: targetFrame.origin.y + 10),
                size: engine.getSize(window) ?? CGSize(width: 800, height: 600)
            ))
        }

        let screenID: String
        if let target = targetScreen {
            screenID = screens.screenID(for: target)
        } else if let pos = engine.getPosition(window) {
            screenID = screens.screenID(for: pos)
        } else {
            screenID = "unknown"
        }

        let state = winState[windowID]!
        let newZone = getZoneKey(state: state, screenID: screenID)

        // Update zone registry
        removeFromZone(windowID: windowID, zoneKey: oldZone)
        addToZone(windowID: windowID, zoneKey: newZone)
        winState[windowID]!.currentZone = newZone

        // Reapply peek offsets for affected zones
        if let old = oldZone, old != newZone {
            applyPeekOffsets(zoneKey: old)
        }
        applyPeekOffsets(zoneKey: newZone)
    }

    // MARK: - Edge-snap Movement

    func moveLeft() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if state.hCentered {
            state.hCentered = false
            state.hIdx = centerToEdgeLeft[state.hCenterIdx]!
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.hIdx == 1 {
            // At left extreme — overflow to west monitor or wrap
            if let pos = engine.getPosition(window),
               let target = screens.screenToWest(of: pos) {
                state.hIdx = 7
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: target)
            } else {
                state.hIdx = 5
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
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if state.hCentered {
            state.hCentered = false
            state.hIdx = centerToEdgeRight[state.hCenterIdx]!
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.hIdx == 11 {
            // At right extreme — overflow to east monitor or wrap
            if let pos = engine.getPosition(window),
               let target = screens.screenToEast(of: pos) {
                state.hIdx = 5
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: target)
            } else {
                state.hIdx = 7
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
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if state.vCentered {
            state.vCentered = false
            state.vIdx = centerToEdgeUp[state.vCenterIdx]!
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.vIdx == 1 {
            // At top extreme — overflow to north monitor or wrap
            if let pos = engine.getPosition(window),
               let target = screens.screenToNorth(of: pos) {
                state.vIdx = 7
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: target)
            } else {
                state.vIdx = 5  // wrap
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
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if state.vCentered {
            state.vCentered = false
            state.vIdx = centerToEdgeDown[state.vCenterIdx]!
            winState[windowID] = state
            finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
            return
        }

        if state.vIdx == 11 {
            // At bottom extreme — overflow to south monitor or wrap
            if let pos = engine.getPosition(window),
               let target = screens.screenToSouth(of: pos) {
                state.vIdx = 5
                winState[windowID] = state
                finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: target)
            } else {
                state.vIdx = 7  // wrap
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
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if !state.hCentered {
            state.hCentered = true
            state.hCenterIdx = edgeToCenterH[state.hIdx]!
        } else {
            switch direction {
            case .shrink:
                state.hCenterIdx = state.hCenterIdx == 6 ? 1 : state.hCenterIdx + 1
            case .grow:
                state.hCenterIdx = state.hCenterIdx == 1 ? 6 : state.hCenterIdx - 1
            }
        }

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    func centerV(direction: CenterDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        if !state.vCentered {
            state.vCentered = true
            state.vCenterIdx = edgeToCenterV[state.vIdx]!
        } else {
            switch direction {
            case .shrink:
                state.vCenterIdx = state.vCenterIdx == 6 ? 1 : state.vCenterIdx + 1
            case .grow:
                state.vCenterIdx = state.vCenterIdx == 1 ? 6 : state.vCenterIdx - 1
            }
        }

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    // MARK: - Reset

    func resetWindow() {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        var state = getState(for: windowID)
        let oldZone = state.currentZone

        state.hIdx = 6
        state.vIdx = 6
        state.hCentered = false
        state.vCentered = false

        winState[windowID] = state
        finishMove(window: window, windowID: windowID, oldZone: oldZone, targetScreen: nil)
    }

    // MARK: - Accordion Cycling

    func cycleZone(direction: CycleDirection) {
        guard let window = engine.getFocusedWindow(),
              let windowID = engine.getWindowID(window) else { return }
        guard let state = winState[windowID],
              let zoneKey = state.currentZone,
              var windows = zoneWindows[zoneKey],
              windows.count > 1 else { return }

        switch direction {
        case .forward:
            // Move front to back
            let front = windows.removeFirst()
            windows.append(front)
        case .backward:
            // Move back to front
            let back = windows.removeLast()
            windows.insert(back, at: 0)
        }

        zoneWindows[zoneKey] = windows

        // Focus the new front window and reapply offsets
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
            applyPeekOffsets(zoneKey: zoneKey)
        }
    }
}
