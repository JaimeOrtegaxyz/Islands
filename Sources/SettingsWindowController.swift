import AppKit

final class SettingsWindowController: NSWindowController {
    private let settingsStore: SettingsStore
    private let accessibilityManager: AccessibilityManager
    private let launchAtLoginController: LaunchAtLoginController

    private let baseModifierValueLabel = NSTextField(labelWithString: "")
    private let reverseCyclePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let centeredModePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let snapProfilePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let peekSizePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let keyboardPreviewLabel = NSTextField(wrappingLabelWithString: "")
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch Islands at login", target: nil, action: nil)

    init(
        settingsStore: SettingsStore,
        accessibilityManager: AccessibilityManager,
        launchAtLoginController: LaunchAtLoginController
    ) {
        self.settingsStore = settingsStore
        self.accessibilityManager = accessibilityManager
        self.launchAtLoginController = launchAtLoginController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Islands Settings"
        window.center()
        window.isReleasedWhenClosed = false

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
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        guard let window else { return }
        refreshUI()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func refreshSystemState() {
        let trusted = accessibilityManager.isTrusted()
        accessibilityStatusLabel.stringValue = trusted ? "Accessibility access is enabled." : "Accessibility access is still required."
        launchAtLoginCheckbox.state = launchAtLoginController.isEnabled() ? .on : .off
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        contentView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 18
        container.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            container.topAnchor.constraint(equalTo: documentView.topAnchor, constant: 24),
            container.bottomAnchor.constraint(equalTo: documentView.bottomAnchor, constant: -24),
            container.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor, constant: -48),
        ])

        container.addArrangedSubview(makeKeyboardSection())
        container.addArrangedSubview(makeLayoutSection())
        container.addArrangedSubview(makeSystemSection())
        container.addArrangedSubview(makeFooterSection())
    }

    private func makeKeyboardSection() -> NSView {
        let section = makeSection(title: "Keyboard")

        let recordButton = NSButton(title: "Record…", target: self, action: #selector(recordBaseModifiers))
        let baseRow = makeRow(label: "Base modifier combo", control: makeTrailingStack(views: [baseModifierValueLabel, recordButton]))

        reverseCyclePopup.target = self
        reverseCyclePopup.action = #selector(reverseCyclePopupChanged)
        let reverseRow = makeRow(label: "Backward stack extra modifiers", control: reverseCyclePopup)

        centeredModePopup.target = self
        centeredModePopup.action = #selector(centeredModePopupChanged)
        let centeredRow = makeRow(label: "Centered mode extra modifiers", control: centeredModePopup)

        keyboardPreviewLabel.textColor = .secondaryLabelColor

        let body = section.subviews[1] as! NSStackView
        body.addArrangedSubview(baseRow)
        body.addArrangedSubview(reverseRow)
        body.addArrangedSubview(centeredRow)
        body.addArrangedSubview(keyboardPreviewLabel)
        return section
    }

    private func makeLayoutSection() -> NSView {
        let section = makeSection(title: "Layout")

        snapProfilePopup.target = self
        snapProfilePopup.action = #selector(snapProfilePopupChanged)

        peekSizePopup.target = self
        peekSizePopup.action = #selector(peekSizePopupChanged)

        let snapRow = makeRow(label: "Snap sizes", control: snapProfilePopup)
        let peekRow = makeRow(label: "Accordion peek size", control: peekSizePopup)

        let noteLabel = NSTextField(wrappingLabelWithString: "Monitor overflow stays enabled by default.")
        noteLabel.textColor = .secondaryLabelColor

        let body = section.subviews[1] as! NSStackView
        body.addArrangedSubview(snapRow)
        body.addArrangedSubview(peekRow)
        body.addArrangedSubview(noteLabel)
        return section
    }

    private func makeSystemSection() -> NSView {
        let section = makeSection(title: "System")

        let accessibilityButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        let accessibilityRow = makeRow(label: "Accessibility", control: makeTrailingStack(views: [accessibilityStatusLabel, accessibilityButton]))

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)

        let restoreDefaultsButton = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        restoreDefaultsButton.bezelStyle = .rounded

        let body = section.subviews[1] as! NSStackView
        body.addArrangedSubview(accessibilityRow)
        body.addArrangedSubview(launchAtLoginCheckbox)
        body.addArrangedSubview(restoreDefaultsButton)
        return section
    }

    private func makeFooterSection() -> NSView {
        let footer = NSBox()
        footer.boxType = .custom
        footer.cornerRadius = 12
        footer.borderColor = .separatorColor
        footer.borderWidth = 1
        footer.contentViewMargins = NSSize(width: 16, height: 16)

        let logoSlot = NSBox()
        logoSlot.boxType = .custom
        logoSlot.cornerRadius = 10
        logoSlot.borderColor = .separatorColor
        logoSlot.borderWidth = 1
        logoSlot.fillColor = NSColor.windowBackgroundColor
        logoSlot.contentViewMargins = NSSize(width: 12, height: 12)
        logoSlot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            logoSlot.widthAnchor.constraint(equalToConstant: 64),
            logoSlot.heightAnchor.constraint(equalToConstant: 64),
        ])

        let logoImage = NSImageView()
        logoImage.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Islands")
        logoImage.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .medium)
        logoImage.translatesAutoresizingMaskIntoConstraints = false

        let logoContainer = NSView()
        logoContainer.translatesAutoresizingMaskIntoConstraints = false
        logoContainer.addSubview(logoImage)
        NSLayoutConstraint.activate([
            logoImage.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
            logoImage.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
        ])
        logoSlot.contentView = logoContainer

        let titleLabel = NSTextField(labelWithString: "Islands")
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)

        let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let descriptionLabel = NSTextField(wrappingLabelWithString: "Native macOS window tiling with accordion stacking.")
        descriptionLabel.textColor = .secondaryLabelColor

        let versionLabel = NSTextField(labelWithString: "Version \(versionString)")
        versionLabel.textColor = .secondaryLabelColor

        let textStack = NSStackView(views: [titleLabel, descriptionLabel, versionLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 6

        let layout = NSStackView(views: [logoSlot, textStack])
        layout.orientation = .horizontal
        layout.alignment = .centerY
        layout.spacing = 14

        footer.contentView = layout
        return footer
    }

    private func makeSection(title: String) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)

        let body = NSStackView()
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 12

        let section = NSStackView(views: [titleLabel, body])
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 10
        return section
    }

    private func makeRow(label: String, control: NSView) -> NSView {
        let labelField = NSTextField(labelWithString: label)
        labelField.font = .systemFont(ofSize: 13)

        let row = NSStackView(views: [labelField, NSView(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12

        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)

        return row
    }

    private func makeTrailingStack(views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func refreshUI() {
        let settings = settingsStore.snapshot
        baseModifierValueLabel.stringValue = settings.baseModifiers.symbolString
        populateExtraPopup(reverseCyclePopup, options: ModifierSet.extraModifierOptions(excluding: settings.baseModifiers), selected: settings.reverseCycleExtraModifiers)
        populateExtraPopup(centeredModePopup, options: ModifierSet.extraModifierOptions(excluding: settings.baseModifiers), selected: settings.centeredModeExtraModifiers)
        populateSnapProfilePopup(selected: settings.snapProfile)
        populatePeekSizePopup(selected: settings.peekSize)
        keyboardPreviewLabel.stringValue = """
        Move and resize: \(settings.baseModifiers.symbolString) + arrows / Return / Tab
        Backward stack: \(settings.reverseCycleModifiers.symbolString) + Tab
        Centered mode: \(settings.centeredModeModifiers.symbolString) + arrows
        """
        refreshSystemState()
    }

    private func populateExtraPopup(_ popup: NSPopUpButton, options: [ModifierSet], selected: ModifierSet) {
        popup.removeAllItems()
        for option in options {
            popup.addItem(withTitle: option.symbolString)
            popup.lastItem?.representedObject = option.rawValue
        }

        if let selectedItem = popup.itemArray.first(where: { ($0.representedObject as? Int) == selected.rawValue }) {
            popup.select(selectedItem)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func populateSnapProfilePopup(selected: SnapProfile) {
        snapProfilePopup.removeAllItems()
        for profile in SnapProfile.allCases {
            snapProfilePopup.addItem(withTitle: profile.displayName)
            snapProfilePopup.lastItem?.representedObject = profile.rawValue
            snapProfilePopup.lastItem?.tag = profile.rawValue
        }
        snapProfilePopup.selectItem(withTag: selected.rawValue)
    }

    private func populatePeekSizePopup(selected: PeekSizePreset) {
        peekSizePopup.removeAllItems()
        for preset in PeekSizePreset.allCases {
            peekSizePopup.addItem(withTitle: preset.displayName)
            peekSizePopup.lastItem?.representedObject = preset.rawValue
            peekSizePopup.lastItem?.tag = preset.rawValue
        }
        peekSizePopup.selectItem(withTag: selected.rawValue)
    }

    @objc private func settingsDidChange() {
        refreshUI()
    }

    @objc private func recordBaseModifiers() {
        let current = settingsStore.snapshot.baseModifiers
        let alert = NSAlert()
        alert.messageText = "Record Base Modifiers"
        alert.informativeText = "Press the modifiers you want to use, then click Save. Islands needs at least one modifier, and one modifier has to remain available for alternate modes."

        let capturedLabel = NSTextField(labelWithString: current.symbolString)
        capturedLabel.font = .monospacedSystemFont(ofSize: 18, weight: .medium)

        let accessory = NSStackView(views: [capturedLabel])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        alert.accessoryView = accessory

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        var capturedModifiers = current
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { event in
            let modifiers = ModifierSet(eventFlags: event.modifierFlags)
            if !modifiers.isEmpty {
                capturedModifiers = modifiers
                capturedLabel.stringValue = modifiers.symbolString
            }
            return nil
        }

        let response = alert.runModal()
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }

        guard response == .alertFirstButtonReturn else { return }
        guard capturedModifiers.isValidBaseShortcut else {
            presentErrorAlert(
                title: "That shortcut won’t work",
                message: "Use at least one modifier, and leave at least one extra modifier available for backward stack cycling and centered mode."
            )
            return
        }

        settingsStore.setBaseModifiers(capturedModifiers)
    }

    @objc private func reverseCyclePopupChanged() {
        guard let rawValue = reverseCyclePopup.selectedItem?.representedObject as? Int else { return }
        settingsStore.setReverseCycleExtraModifiers(ModifierSet(rawValue: rawValue))
    }

    @objc private func centeredModePopupChanged() {
        guard let rawValue = centeredModePopup.selectedItem?.representedObject as? Int else { return }
        settingsStore.setCenteredModeExtraModifiers(ModifierSet(rawValue: rawValue))
    }

    @objc private func snapProfilePopupChanged() {
        guard let rawValue = snapProfilePopup.selectedItem?.representedObject as? Int,
              let profile = SnapProfile(rawValue: rawValue) else { return }
        settingsStore.setSnapProfile(profile)
    }

    @objc private func peekSizePopupChanged() {
        guard let rawValue = peekSizePopup.selectedItem?.representedObject as? Int,
              let preset = PeekSizePreset(rawValue: rawValue) else { return }
        settingsStore.setPeekSize(preset)
    }

    @objc private func openAccessibilitySettings() {
        accessibilityManager.openSystemSettings()
    }

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = launchAtLoginCheckbox.state == .on
        do {
            try launchAtLoginController.setEnabled(shouldEnable)
        } catch {
            launchAtLoginCheckbox.state = launchAtLoginController.isEnabled() ? .on : .off
            presentErrorAlert(
                title: "Couldn’t update launch at login",
                message: error.localizedDescription
            )
        }
    }

    @objc private func restoreDefaults() {
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
