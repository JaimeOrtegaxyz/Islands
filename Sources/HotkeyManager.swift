import Carbon
import Foundation

final class HotkeyManager {
    private let windowManager: WindowManager
    private let settingsStore: SettingsStore
    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private var isEnabled = false

    // Carbon key codes
    private static let kVK_LeftArrow:  UInt32 = 0x7B  // 123
    private static let kVK_RightArrow: UInt32 = 0x7C  // 124
    private static let kVK_DownArrow:  UInt32 = 0x7D  // 125
    private static let kVK_UpArrow:    UInt32 = 0x7E  // 126
    private static let kVK_Return:     UInt32 = 0x24  // 36
    private static let kVK_Tab:        UInt32 = 0x30  // 48

    init(windowManager: WindowManager, settingsStore: SettingsStore) {
        self.windowManager = windowManager
        self.settingsStore = settingsStore

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: settingsStore
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        unregisterAll()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if enabled {
            registerAll()
        } else {
            unregisterAll()
        }
    }

    func registerAll() {
        unregisterAll()
        installHandler()

        let settings = settingsStore.snapshot
        let base = settings.baseModifiers.carbonFlags
        let reverse = settings.reverseCycleModifiers.carbonFlags
        let centered = settings.centeredModeModifiers.carbonFlags

        // Edge-snap: base modifiers + arrows
        register(modifiers: base, keyCode: Self.kVK_LeftArrow)  { [weak self] in self?.windowManager.moveLeft() }
        register(modifiers: base, keyCode: Self.kVK_RightArrow) { [weak self] in self?.windowManager.moveRight() }
        register(modifiers: base, keyCode: Self.kVK_UpArrow)    { [weak self] in self?.windowManager.moveUp() }
        register(modifiers: base, keyCode: Self.kVK_DownArrow)  { [weak self] in self?.windowManager.moveDown() }

        // Reset: base modifiers + Return
        register(modifiers: base, keyCode: Self.kVK_Return) { [weak self] in self?.windowManager.resetWindow() }

        // Zone cycling: base modifiers + Tab / base modifiers + extra modifiers + Tab
        register(modifiers: base, keyCode: Self.kVK_Tab) { [weak self] in self?.windowManager.cycleZone(direction: .forward) }
        register(modifiers: reverse, keyCode: Self.kVK_Tab) { [weak self] in self?.windowManager.cycleZone(direction: .backward) }

        // Centered mode: base modifiers + extra modifiers + arrows
        register(modifiers: centered, keyCode: Self.kVK_LeftArrow)  { [weak self] in self?.windowManager.centerH(direction: .shrink) }
        register(modifiers: centered, keyCode: Self.kVK_RightArrow) { [weak self] in self?.windowManager.centerH(direction: .grow) }
        register(modifiers: centered, keyCode: Self.kVK_UpArrow)    { [weak self] in self?.windowManager.centerV(direction: .shrink) }
        register(modifiers: centered, keyCode: Self.kVK_DownArrow)  { [weak self] in self?.windowManager.centerV(direction: .grow) }
    }

    func unregisterAll() {
        for ref in hotkeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeyRefs.removeAll()
        handlers.removeAll()
        nextID = 1

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Private

    @objc private func settingsDidChange() {
        guard isEnabled else { return }
        registerAll()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // Store a raw pointer to self for the C callback
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus in
                guard let event = event, let userData = userData else { return OSStatus(eventNotHandledErr) }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )

                if let action = mgr.handlers[hotkeyID.id] {
                    DispatchQueue.main.async { action() }
                }

                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )
    }

    private func register(modifiers: UInt32, keyCode: UInt32, action: @escaping () -> Void) {
        let id = nextID
        nextID += 1
        handlers[id] = action

        let hotkeyID = EventHotKeyID(signature: OSType(0x49534C44), id: id)  // 'ISLD'
        var hotkeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(keyCode, modifiers, hotkeyID, GetApplicationEventTarget(), 0, &hotkeyRef)
        if status == noErr {
            hotkeyRefs.append(hotkeyRef)
        } else {
            print("Failed to register hotkey \(id): \(status)")
        }
    }
}

private extension ModifierSet {
    var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) {
            flags |= UInt32(controlKey)
        }
        if contains(.option) {
            flags |= UInt32(optionKey)
        }
        if contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        return flags
    }
}
