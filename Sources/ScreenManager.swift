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

    /// Get a stable screen identifier
    func screenID(for point: CGPoint) -> String {
        guard let screen = screen(for: point) else { return "unknown" }
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
        // NSScreen uses bottom-left origin; we need top-left origin for window positioning
        let mainScreen = NSScreen.screens[0]
        let mainHeight = mainScreen.frame.height
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.origin.x,
            y: mainHeight - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
    }

    // MARK: - Private

    private func screen(for point: CGPoint) -> NSScreen? {
        // Convert top-left point to bottom-left for NSScreen coordinate system
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let flippedPoint = CGPoint(x: point.x, y: mainHeight - point.y)
        for s in screens {
            if s.frame.contains(flippedPoint) {
                return s
            }
        }
        // Fallback: find nearest screen
        return screens.first
    }

    private func stableID(for screen: NSScreen) -> String {
        let frame = screen.frame
        return "\(screen.localizedName)_\(Int(frame.origin.x))_\(Int(frame.origin.y))_\(Int(frame.width))x\(Int(frame.height))"
    }
}
