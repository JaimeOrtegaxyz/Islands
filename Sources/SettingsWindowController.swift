import AppKit

// MARK: - Controller

final class SettingsWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let accessibilityManager: AccessibilityManager
    private let launchAtLoginController: LaunchAtLoginController

    private let baseRecorder = ModifierRecorderView()
    private let reverseCyclePills = PillSelectorView()
    private let centeredModePills = PillSelectorView()
    private let snapProfilePills = PillSelectorView()
    private let peekSizePills = PillSelectorView()
    private let launchAtLoginCheckbox = StyledCheckbox(title: "Launch at login")
    private let accessibilityStatusLabel = WhiteLabel()
    private let accessibilityButton = OutlineButton(title: "Open Accessibility Settings")
    private let restoreDefaultsButton = OutlineButton(title: "Restore Defaults")
    private let previewLabel = WhiteLabel()

    init(
        settingsStore: SettingsStore,
        accessibilityManager: AccessibilityManager,
        launchAtLoginController: LaunchAtLoginController
    ) {
        self.settingsStore = settingsStore
        self.accessibilityManager = accessibilityManager
        self.launchAtLoginController = launchAtLoginController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Islands Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        buildInterface()
        refreshUI()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: settingsStore
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func showWindowAndActivate() {
        guard let window else { return }
        refreshUI()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func refreshSystemState() {
        let trusted = accessibilityManager.isTrusted()
        accessibilityStatusLabel.stringValue = trusted ? "Accessibility access enabled" : "Accessibility access required"
        accessibilityStatusLabel.alphaValue = trusted ? 0.7 : 1.0
        launchAtLoginCheckbox.isChecked = launchAtLoginController.isEnabled()
    }

    // MARK: Layout

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let background = BackgroundImageView()
        background.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(background)

        let tint = NSView()
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
        tint.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tint)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tint.topAnchor.constraint(equalTo: contentView.topAnchor),
            tint.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let shortcutsColumn = makeShortcutsColumn()
        let layoutColumn = makeLayoutColumn()

        let columns = NSStackView(views: [shortcutsColumn, layoutColumn])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 36
        columns.translatesAutoresizingMaskIntoConstraints = false

        let systemRow = makeSystemRow()
        let footer = makeFooter()

        contentView.addSubview(columns)
        contentView.addSubview(systemRow)
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            columns.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 72),
            columns.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            columns.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            systemRow.topAnchor.constraint(equalTo: columns.bottomAnchor, constant: 28),
            systemRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            systemRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            footer.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -34),
        ])

        baseRecorder.onCommit = { [weak self] modifiers in
            self?.settingsStore.setBaseModifiers(modifiers)
        }
        reverseCyclePills.onSelect = { [weak self] raw in
            self?.settingsStore.setReverseCycleExtraModifiers(ModifierSet(rawValue: raw))
        }
        centeredModePills.onSelect = { [weak self] raw in
            self?.settingsStore.setCenteredModeExtraModifiers(ModifierSet(rawValue: raw))
        }
        snapProfilePills.onSelect = { [weak self] raw in
            if let profile = SnapProfile(rawValue: raw) {
                self?.settingsStore.setSnapProfile(profile)
            }
        }
        peekSizePills.onSelect = { [weak self] raw in
            if let preset = PeekSizePreset(rawValue: raw) {
                self?.settingsStore.setPeekSize(preset)
            }
        }
        launchAtLoginCheckbox.onToggle = { [weak self] shouldEnable in
            self?.applyLaunchAtLogin(shouldEnable)
        }
        accessibilityButton.onClick = { [weak self] in
            self?.accessibilityManager.openSystemSettings()
        }
        restoreDefaultsButton.onClick = { [weak self] in
            self?.restoreDefaults()
        }
    }

    private func makeShortcutsColumn() -> NSView {
        previewLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        previewLabel.alphaValue = 0.75
        previewLabel.maximumNumberOfLines = 3

        let column = NSStackView(views: [
            sectionHeader("Shortcuts"),
            fieldGroup(label: "Base combo", control: baseRecorder),
            fieldGroup(label: "Backward stack adds", control: reverseCyclePills),
            fieldGroup(label: "Centered mode adds", control: centeredModePills),
            previewLabel,
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 18
        column.setCustomSpacing(14, after: column.arrangedSubviews[0])
        column.setCustomSpacing(20, after: column.arrangedSubviews[3])
        return column
    }

    private func makeLayoutColumn() -> NSView {
        let column = NSStackView(views: [
            sectionHeader("Layout"),
            fieldGroup(label: "Snap sizes", control: snapProfilePills),
            fieldGroup(label: "Peek size", control: peekSizePills),
        ])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 18
        column.setCustomSpacing(14, after: column.arrangedSubviews[0])
        return column
    }

    private func makeSystemRow() -> NSView {
        let accessibilityStack = NSStackView(views: [accessibilityStatusLabel, accessibilityButton])
        accessibilityStack.orientation = .horizontal
        accessibilityStack.alignment = .centerY
        accessibilityStack.spacing = 14
        accessibilityStatusLabel.font = .systemFont(ofSize: 12, weight: .regular)

        let leftStack = NSStackView(views: [launchAtLoginCheckbox, accessibilityStack])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 12

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let row = NSStackView(views: [leftStack, spacer, restoreDefaultsButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 20
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func makeFooter() -> NSView {
        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

        let title = WhiteLabel()
        title.stringValue = "Islands"
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.alignment = .center
        title.alphaValue = 0.95

        let tagline = WhiteLabel()
        tagline.stringValue = "Native window tiling for macOS"
        tagline.font = .systemFont(ofSize: 11, weight: .regular)
        tagline.alignment = .center
        tagline.alphaValue = 0.75

        let version = WhiteLabel()
        version.stringValue = "Version \(versionString)"
        version.font = .systemFont(ofSize: 10, weight: .regular)
        version.alignment = .center
        version.alphaValue = 0.6

        let stack = NSStackView(views: [title, tagline, version])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func sectionHeader(_ text: String) -> NSView {
        let label = WhiteLabel()
        label.stringValue = text.uppercased()
        label.font = .systemFont(ofSize: 10, weight: .semibold)

        let attributed = NSMutableAttributedString(string: text.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
            .kern: 2.4,
        ])
        label.attributedStringValue = attributed
        label.alphaValue = 0.85
        return label
    }

    private func fieldGroup(label text: String, control: NSView) -> NSView {
        let label = WhiteLabel()
        label.stringValue = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.alphaValue = 0.9

        let stack = NSStackView(views: [label, control])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        return stack
    }

    // MARK: State

    private func refreshUI() {
        let settings = settingsStore.snapshot
        baseRecorder.setModifiers(settings.baseModifiers)

        let extras = ModifierSet.extraModifierOptions(excluding: settings.baseModifiers)
        let extraItems = extras.map { PillSelectorView.Item(rawValue: $0.rawValue, title: "+\($0.symbolString)") }
        reverseCyclePills.configure(items: extraItems, selectedRawValue: settings.reverseCycleExtraModifiers.rawValue)
        centeredModePills.configure(items: extraItems, selectedRawValue: settings.centeredModeExtraModifiers.rawValue)

        snapProfilePills.configure(
            items: SnapProfile.allCases.map { PillSelectorView.Item(rawValue: $0.rawValue, title: $0.displayName) },
            selectedRawValue: settings.snapProfile.rawValue
        )
        peekSizePills.configure(
            items: PeekSizePreset.allCases.map { PillSelectorView.Item(rawValue: $0.rawValue, title: $0.displayName) },
            selectedRawValue: settings.peekSize.rawValue
        )

        previewLabel.stringValue = """
        Move/resize  \(settings.baseModifiers.symbolString) + arrows / Return / Tab
        Back stack   \(settings.reverseCycleModifiers.symbolString) + Tab
        Centered     \(settings.centeredModeModifiers.symbolString) + arrows
        """
        refreshSystemState()
    }

    @objc private func settingsDidChange() {
        refreshUI()
    }

    private func applyLaunchAtLogin(_ shouldEnable: Bool) {
        do {
            try launchAtLoginController.setEnabled(shouldEnable)
        } catch {
            launchAtLoginCheckbox.isChecked = launchAtLoginController.isEnabled()
            presentErrorAlert(
                title: "Couldn’t update launch at login",
                message: error.localizedDescription
            )
        }
    }

    private func restoreDefaults() {
        settingsStore.restoreDefaults()

        if launchAtLoginController.isEnabled() {
            do {
                try launchAtLoginController.setEnabled(false)
            } catch {
                presentErrorAlert(
                    title: "Defaults restored with one exception",
                    message: "Islands settings were reset, but launch at login could not be disabled: \(error.localizedDescription)"
                )
            }
        }

        refreshUI()
    }

    private func presentErrorAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window!)
    }
}

// MARK: - Background image

private final class BackgroundImageView: NSView {
    override var wantsDefaultClipping: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
        loadImage()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadImage() {
        let url = Bundle.main.url(forResource: "settings-bg", withExtension: "webp")
            ?? URL(fileURLWithPath: "settings-bg.webp")
        if let image = NSImage(contentsOf: url) {
            layer?.contents = image
        }
    }
}

// MARK: - White label

private final class WhiteLabel: NSTextField {
    init() {
        super.init(frame: .zero)
        isEditable = false
        isBezeled = false
        drawsBackground = false
        isSelectable = false
        textColor = .white
        backgroundColor = .clear
        cell?.wraps = true
        cell?.isScrollable = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var allowsVibrancy: Bool { false }
}

// MARK: - Outline button

private final class OutlineButton: NSView {
    var onClick: (() -> Void)?

    private let titleLabel = WhiteLabel()
    private var isHovered = false
    private var isPressed = false
    private var trackingArea: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        layer?.backgroundColor = NSColor.clear.cgColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            heightAnchor.constraint(equalToConstant: 30),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        updateAppearance()
        if wasPressed && bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    private func updateAppearance() {
        let fillAlpha: CGFloat = isPressed ? 0.22 : (isHovered ? 0.12 : 0.0)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(fillAlpha).cgColor
    }
}

// MARK: - Checkbox

private final class StyledCheckbox: NSView {
    var onToggle: ((Bool) -> Void)?
    var isChecked: Bool = false {
        didSet { updateAppearance() }
    }

    private let box = NSView()
    private let check = NSView()
    private let titleLabel = WhiteLabel()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(title: String) {
        super.init(frame: .zero)

        box.wantsLayer = true
        box.layer?.cornerRadius = 4
        box.layer?.borderWidth = 1.2
        box.layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        addSubview(box)

        check.wantsLayer = true
        check.layer?.cornerRadius = 2
        check.layer?.backgroundColor = NSColor.white.cgColor
        check.translatesAutoresizingMaskIntoConstraints = false
        check.alphaValue = 0
        box.addSubview(check)

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.alphaValue = 0.9
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: leadingAnchor),
            box.centerYAnchor.constraint(equalTo: centerYAnchor),
            box.widthAnchor.constraint(equalToConstant: 16),
            box.heightAnchor.constraint(equalToConstant: 16),
            check.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            check.widthAnchor.constraint(equalToConstant: 8),
            check.heightAnchor.constraint(equalToConstant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        isChecked.toggle()
        onToggle?(isChecked)
    }

    private func updateAppearance() {
        check.alphaValue = isChecked ? 1 : 0
        let borderAlpha: CGFloat = isHovered ? 1.0 : 0.85
        box.layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
    }
}

// MARK: - Modifier recorder

private final class ModifierRecorderView: NSView {
    var onCommit: ((ModifierSet) -> Void)?

    private let displayLabel = WhiteLabel()
    private let hintLabel = WhiteLabel()
    private let cancelButton = CancelGlyphView()
    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var committedModifiers: ModifierSet = []
    private var pendingModifiers: ModifierSet = []
    private var isRecording = false
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1.2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.85).cgColor
        layer?.backgroundColor = NSColor.clear.cgColor

        displayLabel.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        displayLabel.alignment = .left
        displayLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(displayLabel)

        hintLabel.stringValue = "Press modifier keys…"
        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.alphaValue = 0
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hintLabel)

        cancelButton.alphaValue = 0
        cancelButton.onClick = { [weak self] in self?.stopRecording(commit: false) }
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 44),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            displayLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            displayLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            displayLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -8),
            hintLabel.leadingAnchor.constraint(equalTo: displayLabel.trailingAnchor, constant: 10),
            hintLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            hintLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -8),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            cancelButton.widthAnchor.constraint(equalToConstant: 18),
            cancelButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        removeMonitors()
    }

    func setModifiers(_ modifiers: ModifierSet) {
        committedModifiers = modifiers
        if !isRecording {
            displayLabel.stringValue = modifiers.symbolString
        }
    }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            // Tapping while recording does nothing (use X to cancel).
            return
        }
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        pendingModifiers = []
        displayLabel.stringValue = ""
        updateAppearance()

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                self.stopRecording(commit: false)
                return nil
            }
            return event
        }
    }

    private func stopRecording(commit: Bool) {
        isRecording = false
        removeMonitors()
        if commit, pendingModifiers.isValidBaseShortcut {
            committedModifiers = pendingModifiers
            onCommit?(pendingModifiers)
        }
        pendingModifiers = []
        displayLabel.stringValue = committedModifiers.symbolString
        updateAppearance()
    }

    private func removeMonitors() {
        if let m = flagsMonitor { NSEvent.removeMonitor(m) }
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        flagsMonitor = nil
        keyMonitor = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard isRecording else { return }
        let current = ModifierSet(eventFlags: event.modifierFlags)

        if current.isEmpty {
            // All keys released — commit what we captured at peak.
            stopRecording(commit: pendingModifiers.isValidBaseShortcut)
            return
        }

        // Track the peak combo pressed so multi-key combos register reliably.
        pendingModifiers.formUnion(current)
        displayLabel.stringValue = pendingModifiers.symbolString
    }

    private func updateAppearance() {
        let accent = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.4, alpha: 1.0)
        if isRecording {
            layer?.borderColor = accent.cgColor
            layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
            hintLabel.animator().alphaValue = pendingModifiers.isEmpty ? 0.75 : 0
            cancelButton.animator().alphaValue = 1
            displayLabel.textColor = accent
        } else {
            let borderAlpha: CGFloat = isHovered ? 1.0 : 0.85
            layer?.borderColor = NSColor.white.withAlphaComponent(borderAlpha).cgColor
            layer?.backgroundColor = isHovered ? NSColor.white.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
            hintLabel.animator().alphaValue = 0
            cancelButton.animator().alphaValue = 0
            displayLabel.textColor = .white
        }
    }
}

// MARK: - Cancel glyph

private final class CancelGlyphView: NSView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath()
        let inset: CGFloat = 5
        path.move(to: NSPoint(x: inset, y: inset))
        path.line(to: NSPoint(x: bounds.width - inset, y: bounds.height - inset))
        path.move(to: NSPoint(x: inset, y: bounds.height - inset))
        path.line(to: NSPoint(x: bounds.width - inset, y: inset))
        path.lineWidth = 1.3
        path.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.9).setStroke()
        path.stroke()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - Pill selector

private final class PillSelectorView: NSView {
    struct Item {
        let rawValue: Int
        let title: String
    }

    var onSelect: ((Int) -> Void)?

    private var items: [Item] = []
    private var selectedRawValue: Int?
    private var pills: [PillButton] = []
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(items: [Item], selectedRawValue: Int) {
        self.items = items
        self.selectedRawValue = selectedRawValue

        for pill in pills {
            stack.removeArrangedSubview(pill)
            pill.removeFromSuperview()
        }
        pills = items.map { item in
            let pill = PillButton(title: item.title)
            pill.onClick = { [weak self] in
                self?.selectedRawValue = item.rawValue
                self?.updateSelection()
                self?.onSelect?(item.rawValue)
            }
            return pill
        }
        for pill in pills { stack.addArrangedSubview(pill) }
        updateSelection()
    }

    private func updateSelection() {
        for (pill, item) in zip(pills, items) {
            pill.isSelected = (item.rawValue == selectedRawValue)
        }
    }
}

private final class PillButton: NSView {
    var onClick: (() -> Void)?
    var isSelected: Bool = false {
        didSet { updateAppearance() }
    }

    private let titleLabel = WhiteLabel()
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.75).cgColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updateAppearance() {
        if isSelected {
            layer?.backgroundColor = NSColor.white.cgColor
            layer?.borderColor = NSColor.white.cgColor
            titleLabel.textColor = NSColor.black.withAlphaComponent(0.82)
        } else {
            let fill: CGFloat = isHovered ? 0.12 : 0
            layer?.backgroundColor = NSColor.white.withAlphaComponent(fill).cgColor
            layer?.borderColor = NSColor.white.withAlphaComponent(isHovered ? 1.0 : 0.75).cgColor
            titleLabel.textColor = .white
        }
    }
}
