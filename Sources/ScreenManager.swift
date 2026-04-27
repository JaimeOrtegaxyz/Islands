import AppKit

final class ScreenManager {
    private var screens: [NSScreen] = []

    init() {
        refresh()
        // Re-cache when display configuration changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        screens = NSScreen.screens
    }

    /// Get the visible frame (excluding menu bar/dock) of the screen containing a point
    func screenFrame(for point: CGPoint) -> CGRect? {
        guard let screen = screen(for: point) else { return nil }
        return visibleFrame(of: screen)
    }

    /// Get the visible frame of the screen containing most of a window frame.
    func screenFrame(for windowFrame: CGRect) -> CGRect? {
        guard let screen = screen(for: windowFrame) else { return nil }
        return visibleFrame(of: screen)
    }

    /// Get a stable screen identifier
    func screenID(for point: CGPoint) -> String {
        guard let screen = screen(for: point) else { return "unknown" }
        return stableID(for: screen)
    }

    /// Get a stable screen identifier for the screen containing most of a window frame.
    func screenID(for windowFrame: CGRect) -> String {
        guard let screen = screen(for: windowFrame) else { return "unknown" }
        return stableID(for: screen)
    }

    func screenID(for screen: NSScreen) -> String {
        return stableID(for: screen)
    }

    /// Find the screen to the east of the screen containing a point
    func screenToEast(of point: CGPoint) -> NSScreen? {
        guard let current = screen(for: point) else { return nil }
        let currentFrame = current.frame
        // Find the screen whose left edge is closest to (and to the right of) the current screen's right edge
        var best: NSScreen?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for s in screens {
            if s == current { continue }
            let sf = s.frame
            if sf.minX >= currentFrame.maxX - 1 {
                let dist = sf.minX - currentFrame.maxX
                if dist < bestDist {
                    bestDist = dist
                    best = s
                }
            }
        }
        return best
    }

    /// Find the screen above (north of) the screen containing a point
    func screenToNorth(of point: CGPoint) -> NSScreen? {
        guard let current = screen(for: point) else { return nil }
        let currentFrame = current.frame
        // In NSScreen coords (bottom-left origin), "above" means higher Y values
        var best: NSScreen?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for s in screens {
            if s == current { continue }
            let sf = s.frame
            if sf.minY >= currentFrame.maxY - 1 {
                let dist = sf.minY - currentFrame.maxY
                if dist < bestDist {
                    bestDist = dist
                    best = s
                }
            }
        }
        return best
    }

    /// Find the screen below (south of) the screen containing a point
    func screenToSouth(of point: CGPoint) -> NSScreen? {
        guard let current = screen(for: point) else { return nil }
        let currentFrame = current.frame
        // In NSScreen coords (bottom-left origin), "below" means lower Y values
        var best: NSScreen?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for s in screens {
            if s == current { continue }
            let sf = s.frame
            if sf.maxY <= currentFrame.minY + 1 {
                let dist = currentFrame.minY - sf.maxY
                if dist < bestDist {
                    bestDist = dist
                    best = s
                }
            }
        }
        return best
    }

    /// Find the screen to the west of the screen containing a point
    func screenToWest(of point: CGPoint) -> NSScreen? {
        guard let current = screen(for: point) else { return nil }
        let currentFrame = current.frame
        var best: NSScreen?
        var bestDist = CGFloat.greatestFiniteMagnitude
        for s in screens {
            if s == current { continue }
            let sf = s.frame
            if sf.maxX <= currentFrame.minX + 1 {
                let dist = currentFrame.minX - sf.maxX
                if dist < bestDist {
                    bestDist = dist
                    best = s
                }
            }
        }
        return best
    }

    /// Get the visible frame for a target screen (converting from NSScreen coordinates to top-left origin)
    func visibleFrame(of screen: NSScreen) -> CGRect {
        convertToTopLeftCoordinates(screen.visibleFrame)
    }

    // MARK: - Private

    private func screen(for point: CGPoint) -> NSScreen? {
        for s in screens {
            if frameInTopLeftCoordinates(for: s).contains(point) {
                return s
            }
        }
        // Fallback: find nearest screen
        return screens.first
    }

    private func screen(for windowFrame: CGRect) -> NSScreen? {
        var bestScreen: NSScreen?
        var bestArea: CGFloat = 0

        for screen in screens {
            let intersection = frameInTopLeftCoordinates(for: screen).intersection(windowFrame)
            guard !intersection.isNull, !intersection.isEmpty else { continue }

            let area = intersection.width * intersection.height
            if area > bestArea {
                bestArea = area
                bestScreen = screen
            }
        }

        if let bestScreen {
            return bestScreen
        }

        let midpoint = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        return screen(for: midpoint)
    }

    private func frameInTopLeftCoordinates(for screen: NSScreen) -> CGRect {
        convertToTopLeftCoordinates(screen.frame)
    }

    private func convertToTopLeftCoordinates(_ frame: CGRect) -> CGRect {
        // NSScreen uses bottom-left origin; window positions use top-left origin.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(
            x: frame.origin.x,
            y: mainHeight - frame.origin.y - frame.height,
            width: frame.width,
            height: frame.height
        )
    }

    private func stableID(for screen: NSScreen) -> String {
        let frame = screen.frame
        return "\(screen.localizedName)_\(Int(frame.origin.x))_\(Int(frame.origin.y))_\(Int(frame.width))x\(Int(frame.height))"
    }
}
