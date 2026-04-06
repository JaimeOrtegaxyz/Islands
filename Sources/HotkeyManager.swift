import Carbon
import Foundation

final class HotkeyManager {
    private let windowManager: WindowManager
    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    // Carbon key codes
    private static let kVK_LeftArrow:  UInt32 = 0x7B  // 123
    private static let kVK_RightArrow: UInt32 = 0x7C  // 124
    private static let kVK_DownArrow:  UInt32 = 0x7D  // 125
    private static let kVK_UpArrow:    UInt32 = 0x7E  // 126
    private static let kVK_Return:     UInt32 = 0x24  // 36
    private static let kVK_Tab:        UInt32 = 0x30  // 48

    // Carbon modifier flags
    private static let controlBit:     UInt32 = UInt32(controlKey)   // 1 << 12
    private static let optionBit:      UInt32 = UInt32(optionKey)    // 1 << 11
    private static let cmdBit:         UInt32 = UInt32(cmdKey)       // 1 << 8
    private static let shiftBit:       UInt32 = UInt32(shiftKey)     // 1 << 9

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    func registerAll() {
        installHandler()

        let ctrlOpt = Self.controlBit | Self.optionBit
        let ctrlOptCmd = ctrlOpt | Self.cmdBit
        let ctrlOptShift = ctrlOpt | Self.shiftBit

        // Edge-snap: Ctrl+Option + arrows
        register(modifiers: ctrlOpt, keyCode: Self.kVK_LeftArrow)  { [weak self] in self?.windowManager.moveLeft() }
        register(modifiers: ctrlOpt, keyCode: Self.kVK_RightArrow) { [weak self] in self?.windowManager.moveRight() }
        register(modifiers: ctrlOpt, keyCode: Self.kVK_UpArrow)    { [weak self] in self?.windowManager.moveUp() }
        register(modifiers: ctrlOpt, keyCode: Self.kVK_DownArrow)  { [weak self] in self?.windowManager.moveDown() }

        // Reset: Ctrl+Option + Return
        register(modifiers: ctrlOpt, keyCode: Self.kVK_Return) { [weak self] in self?.windowManager.resetWindow() }

        // Zone cycling: Ctrl+Option + Tab / Ctrl+Option+Shift + Tab
        register(modifiers: ctrlOpt, keyCode: Self.kVK_Tab)      { [weak self] in self?.windowManager.cycleZone(direction: .forward) }
        register(modifiers: ctrlOptShift, keyCode: Self.kVK_Tab)  { [weak self] in self?.windowManager.cycleZone(direction: .backward) }

        // Centered mode: Ctrl+Option+Cmd + arrows
        register(modifiers: ctrlOptCmd, keyCode: Self.kVK_LeftArrow)  { [weak self] in self?.windowManager.centerH(direction: .shrink) }
        register(modifiers: ctrlOptCmd, keyCode: Self.kVK_RightArrow) { [weak self] in self?.windowManager.centerH(direction: .grow) }
        register(modifiers: ctrlOptCmd, keyCode: Self.kVK_UpArrow)    { [weak self] in self?.windowManager.centerV(direction: .shrink) }
        register(modifiers: ctrlOptCmd, keyCode: Self.kVK_DownArrow)  { [weak self] in self?.windowManager.centerV(direction: .grow) }
    }

    func unregisterAll() {
        for ref in hotkeyRefs {
            if let ref = ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeyRefs.removeAll()
        handlers.removeAll()

        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    // MARK: - Private

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
