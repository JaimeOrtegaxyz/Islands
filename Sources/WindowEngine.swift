import AppKit
import ApplicationServices

// Private API for getting CGWindowID from AXUIElement
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

final class WindowEngine {

    /// Get the currently focused window's AXUIElement
    func getFocusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)

        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard result == .success else { return nil }

        return (focusedWindow as! AXUIElement)
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
        guard result == .success else { return nil }

        var point = CGPoint.zero
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    /// Get the size of a window
    func getSize(_ window: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &value)
        guard result == .success else { return nil }

        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }

    /// Get the current frame (position + size) of a window
    func getFrame(_ window: AXUIElement) -> CGRect? {
        guard let position = getPosition(window), let size = getSize(window) else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Set the frame of a window (position first, then size)
    func setFrame(_ window: AXUIElement, frame: CGRect) {
        var position = frame.origin
        var size = frame.size

        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
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
