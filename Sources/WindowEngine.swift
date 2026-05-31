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

    /// Set the frame of a window.
    ///
    /// Apps that advertise `AXEnhancedUserInterface` (Spotify, and Electron/Chromium-based apps)
    /// apply position/size changes asynchronously and animated. That desyncs an open-loop window
    /// manager — immediate read-backs are stale and moves appear to "fight back". The fix used by
    /// yabai/Rectangle: temporarily disable that attribute on the owning application, set the
    /// geometry, then restore it. Disabling it also makes the writes synchronous, so the on-screen
    /// read-back below is reliable.
    ///
    /// Geometry is applied as size → position → size: shrinking first lets the destination position
    /// be accepted (macOS clamps a move that would push an over-large window off-screen), and the
    /// trailing size re-applies the intent since moving — especially across displays — can re-clamp it.
    ///
    /// `visibleFrame` (top-left AX coordinates, same space as `frame`) is the target screen's visible
    /// area. When provided, the window is re-pinned to stay fully on-screen after the set: an app with
    /// a hard minimum size (e.g. Spotify's 800×600) refuses to fit a smaller slot and would otherwise
    /// march off the screen edge into a sliver. Pass `nil` to skip the on-screen clamp.
    func setFrame(_ window: AXUIElement, frame: CGRect, visibleFrame: CGRect?) {
        let axApp = getOwnerPID(window).map { appElement(for: $0) }
        let wasEnhanced = axApp.map(isEnhancedUserInterfaceEnabled) ?? false
        if wasEnhanced, let axApp { setEnhancedUserInterface(axApp, false) }
        defer { if wasEnhanced, let axApp { setEnhancedUserInterface(axApp, true) } }

        var position = frame.origin
        var size = frame.size

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // On-screen guarantee for min-size apps: if the app clamped to a larger size than the slot,
        // re-pin the origin so the right/bottom edge stays within the screen instead of overflowing.
        // With enhanced UI disabled this read-back reflects the clamped size synchronously.
        guard let visibleFrame, let actual = getSize(window) else { return }
        let tolerance: CGFloat = 2
        guard actual.width > frame.width + tolerance || actual.height > frame.height + tolerance else { return }

        var clamped = position
        clamped.x = max(visibleFrame.minX, min(position.x, visibleFrame.maxX - actual.width))
        clamped.y = max(visibleFrame.minY, min(position.y, visibleFrame.maxY - actual.height))
        guard abs(clamped.x - position.x) > 0.5 || abs(clamped.y - position.y) > 0.5 else { return }
        if let posValue = AXValueCreate(.cgPoint, &clamped) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
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
