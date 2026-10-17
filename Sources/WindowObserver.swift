import AppKit
import ApplicationServices

/// Accessibility notifications for the windows in stacks, so their markers follow changes made
/// outside Islands as they happen instead of on the next poll: a member closed, minimized, or
/// dragged away, or the focused window of its app changing (⌘-`, a click).
final class WindowObserver {
    enum Event {
        case closed(CGWindowID)
        case minimized(CGWindowID)
        case moved(CGWindowID)
        case focusChanged(pid_t)
    }

    var onEvent: ((Event) -> Void)?

    /// What one AX registration was for. AX hands back an integer key (the refcon), never a
    /// pointer, so a notification still in flight for a dropped registration finds nothing
    /// instead of freed memory — and a destroyed element can't be asked which window it was.
    private struct Registration {
        let windowID: CGWindowID?   // nil: the app-level focus registration
        let pid: pid_t
        let element: AXUIElement
    }

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
    ]

    /// The single live observer, for the C callback (AX gives it no context but the refcon).
    fileprivate static weak var current: WindowObserver?

    private var observers: [pid_t: AXObserver] = [:]
    private var registrations: [Int: Registration] = [:]
    private var windowKeys: [CGWindowID: Int] = [:]
    private var appKeys: [pid_t: Int] = [:]
    private var nextKey = 1

    init() {
        Self.current = self
    }

    /// Watch exactly `targets` (window → its element and owning app), registering new windows and
    /// dropping ones no longer listed. Cheap when nothing changed, so callers can sync freely.
    func watch(_ targets: [CGWindowID: (element: AXUIElement, pid: pid_t)]) {
        for (windowID, key) in windowKeys where targets[windowID] == nil {
            unregister(key)
            windowKeys[windowID] = nil
        }
        for (windowID, target) in targets where windowKeys[windowID] == nil {
            guard let key = register(Registration(windowID: windowID, pid: target.pid, element: target.element),
                                     notifications: Self.windowNotifications) else { continue }
            windowKeys[windowID] = key
        }

        let pids = Set(targets.values.map(\.pid))
        for (pid, key) in appKeys where !pids.contains(pid) {
            unregister(key)
            appKeys[pid] = nil
        }
        for pid in pids where appKeys[pid] == nil {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.25)
            guard let key = register(Registration(windowID: nil, pid: pid, element: app),
                                     notifications: [kAXFocusedWindowChangedNotification]) else { continue }
            appKeys[pid] = key
        }

        for pid in Array(observers.keys) where !pids.contains(pid) {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            }
        }
    }

    private func register(_ registration: Registration, notifications: [String]) -> Int? {
        guard let observer = observer(for: registration.pid) else { return nil }
        let key = nextKey
        nextKey += 1
        let refcon = UnsafeMutableRawPointer(bitPattern: key)
        var added = false
        for name in notifications {
            added = AXObserverAddNotification(observer, registration.element, name as CFString, refcon) == .success || added
        }
        guard added else { return nil }
        registrations[key] = registration
        return key
    }

    private func unregister(_ key: Int) {
        guard let registration = registrations.removeValue(forKey: key),
              let observer = observers[registration.pid] else { return }
        let names = registration.windowID == nil ? [kAXFocusedWindowChangedNotification] : Self.windowNotifications
        for name in names {
            AXObserverRemoveNotification(observer, registration.element, name as CFString)
        }
    }

    private func observer(for pid: pid_t) -> AXObserver? {
        if let observer = observers[pid] { return observer }
        var created: AXObserver?
        guard AXObserverCreate(pid, windowObserverCallback, &created) == .success, let created else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observers[pid] = created
        return created
    }

    fileprivate func handle(_ notification: String, key: Int) {
        guard let registration = registrations[key] else { return }
        switch (notification, registration.windowID) {
        case (kAXUIElementDestroyedNotification, let windowID?):
            onEvent?(.closed(windowID))
        case (kAXWindowMiniaturizedNotification, let windowID?):
            onEvent?(.minimized(windowID))
        case (kAXWindowMovedNotification, let windowID?), (kAXWindowResizedNotification, let windowID?):
            onEvent?(.moved(windowID))
        case (kAXFocusedWindowChangedNotification, nil):
            onEvent?(.focusChanged(registration.pid))
        default:
            break
        }
    }
}

private func windowObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    WindowObserver.current?.handle(notification as String, key: Int(bitPattern: refcon))
}
