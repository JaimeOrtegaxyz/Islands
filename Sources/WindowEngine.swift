import AppKit
import ApplicationServices

// Private API for getting CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

final class WindowEngine {

    /// Cap synchronous AX round-trips so one hung app can't freeze the main thread.
    private static let messagingTimeout: Float = 0.25

    /// Undocumented AX attribute that apps (Spotify, Electron/Chromium) set when an assistive
    /// client is detected; while true they apply geometry changes asynchronously/animated. See
    /// `setFrame`, which temporarily disables it to make moves land synchronously and precisely.
    private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface" as CFString

    /// Per-application AX elements (timeout-stamped), reused across calls and keyed by pid.
    private var appElementCache: [pid_t: AXUIElement] = [:]

    /// Get the currently focused window's AXUIElement
    func getFocusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, Self.messagingTimeout)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success, let window = focusedWindow,
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }

        return (window as! AXUIElement)
    }

    /// Get the CGWindowID for a window element
    func getWindowID(_ window: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        let result = _AXUIElementGetWindow(window, &windowID)
        guard result == .success else { return nil }
        return windowID
    }

    /// Get the position of a window
    func getPosition(_ window: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &value)
        guard result == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    /// Get the size of a window
    func getSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard result == .success, let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
        return size
    }

    /// Get the current frame (position + size) of a window
    func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = getPosition(window), let size = getSize(window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Whether a window is currently minimized to the Dock (kAXMinimized).
    ///
    /// Read-only (a Copy, not a Set), so it does NOT restore the window — unlike
    /// raise/focus/setFrame, which un-minimize a minimized window as a side effect.
    /// Fail-open: absent / non-boolean / error all read as `false`, so on any doubt
    /// we treat the window as visible and act on it normally.
    func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value)
        guard result == .success, let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    /// Set a window's frame.
    ///
    /// Most apps apply AX position/size directly, so they take a simple synchronous fast path —
    /// the only added cost over a bare set is one attribute read to detect that they're well-behaved.
    /// Apps that advertise `AXEnhancedUserInterface` (Spotify, Electron/Chromium) instead apply
    /// geometry asynchronously and animated, which desyncs this open-loop manager (stale read-backs,
    /// moves that "fight back"); only those pay for the workaround dance. Keeping that cost off the
    /// common path is deliberate — see the "keep the hot path lean" convention.
    ///
    /// `visibleFrame` (top-left AX coordinates, matching `frame`) is the target screen's visible area,
    /// used only for `repinIfOversized`; pass `nil` to skip that check.
    func setFrame(_ window: AXUIElement, frame: CGRect, visibleFrame: CGRect?) {
        let axApp = getOwnerPID(window).map { appElement(for: $0) }

        // Fast path: well-behaved apps obey AX directly — position then size, done.
        guard let axApp, isEnhancedUserInterfaceEnabled(axApp) else {
            setPosition(window, frame.origin)
            setSize(window, frame.size)
            repinIfOversized(window, frame: frame, visibleFrame: visibleFrame)
            return
        }

        // Slow path — enhanced-UI apps only. Disable the attribute so writes land synchronously and
        // precisely (yabai/Rectangle do the same), restoring it on every exit via defer.
        setEnhancedUserInterface(axApp, false)
        defer { setEnhancedUserInterface(axApp, true) }

        // size → position → size: shrinking first lets the destination position be accepted (macOS
        // clamps a move that would push an over-large window off-screen); the trailing size re-applies
        // the intent since moving — especially across displays — can re-clamp it.
        setSize(window, frame.size)
        setPosition(window, frame.origin)
        setSize(window, frame.size)

        // Still inside the enhanced-UI-disabled window, so the read-back is synchronous.
        repinIfOversized(window, frame: frame, visibleFrame: visibleFrame)
    }

    /// On-screen guarantee: an app that refuses to shrink below a hard minimum keeps the size it
    /// wants, so re-pin its origin to keep the right/bottom edge on screen instead of letting it
    /// march off the edge. Applies to both paths — the minimum is a property of the app's layout,
    /// not of how it applies geometry: Finder (a plain, well-behaved app) won't go under 796pt wide
    /// with a sidebar, which hung 76pt off-screen on a right-half snap of a 1440pt display.
    ///
    /// Costs one AX read (~0.07ms), and only for targets where the clamp could bite. A target flush
    /// against the visible frame's left/top edge can't move on that axis — `max(minX, …)` returns
    /// `minX` again — so maximize, left-half and top-row snaps skip the read entirely and stay
    /// exactly as cheap as before. Such a window still overflows its slot, but into the screen
    /// rather than off it, which is the best available outcome when the app won't be narrower.
    private func repinIfOversized(_ window: AXUIElement, frame: CGRect, visibleFrame: CGRect?) {
        guard let visibleFrame else { return }
        let canMoveX = frame.origin.x > visibleFrame.minX
        let canMoveY = frame.origin.y > visibleFrame.minY
        guard canMoveX || canMoveY, let actual = getSize(window) else { return }

        let tolerance: CGFloat = 2
        guard actual.width > frame.width + tolerance || actual.height > frame.height + tolerance else { return }

        var origin = frame.origin
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - actual.width))
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - actual.height))
        guard abs(origin.x - frame.origin.x) > 0.5 || abs(origin.y - frame.origin.y) > 0.5 else { return }
        setPosition(window, origin)
    }

    /// Set a window's position (top-left, AX coordinates). Best-effort.
    private func setPosition(_ window: AXUIElement, _ position: CGPoint) {
        var position = position
        if let value = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        }
    }

    /// Set a window's size. Best-effort.
    private func setSize(_ window: AXUIElement, _ size: CGSize) {
        var size = size
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
        }
    }

    /// Application AX element for a pid, created once and reused. Stamped with the messaging
    /// timeout like every other application element in this file. An element for a recycled or
    /// dead pid simply fails its (best-effort) AX calls, so the cache needs no invalidation.
    private func appElement(for pid: pid_t) -> AXUIElement {
        if let cached = appElementCache[pid] { return cached }
        let axApp = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(axApp, Self.messagingTimeout)
        appElementCache[pid] = axApp
        return axApp
    }

    /// Whether an application currently advertises `AXEnhancedUserInterface`. Absent / non-boolean /
    /// error all read as `false`, so the disable/restore dance only runs when it is explicitly true.
    private func isEnhancedUserInterfaceEnabled(_ axApp: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, Self.enhancedUserInterfaceAttribute, &value)
        guard result == .success, let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }

    private func setEnhancedUserInterface(_ axApp: AXUIElement, _ enabled: Bool) {
        AXUIElementSetAttributeValue(axApp, Self.enhancedUserInterfaceAttribute, enabled ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Raise a window (bring to front without focusing)
    func raise(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Focus a window: raise it and activate its owning application
    func focus(_ window: AXUIElement) {
        if let pid = getOwnerPID(window),
           let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate()
        }

        // Best effort: make the specific target window the app's active window,
        // not just any previously focused window from the same process.
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        raise(window)
    }

    /// Get the PID of the application that owns a window
    func getOwnerPID(_ window: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        let result = AXUIElementGetPid(window, &pid)
        guard result == .success else { return nil }
        return pid
    }

    /// Get an AXUIElement for a window by its CGWindowID, searching running apps
    func windowElement(for targetID: CGWindowID) -> AXUIElement? {
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, Self.messagingTimeout)

            var windowList: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowList)
            guard result == .success, let windows = windowList as? [AXUIElement] else { continue }

            for window in windows {
                if let wid = getWindowID(window), wid == targetID {
                    return window
                }
            }
        }
        return nil
    }

    /// Check if a CGWindowID still exists on screen
    func windowExists(_ windowID: CGWindowID) -> Bool {
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[CFString: Any]] ?? []
        for entry in list {
            if let wid = entry[kCGWindowNumber] as? CGWindowID, wid == windowID {
                return true
            }
        }
        return false
    }
}
