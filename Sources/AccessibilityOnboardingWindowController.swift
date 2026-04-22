import AppKit

final class AccessibilityOnboardingWindowController: NSWindowController {
    private let accessibilityManager: AccessibilityManager

    init(accessibilityManager: AccessibilityManager) {
        self.accessibilityManager = accessibilityManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Enable Accessibility Access"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildInterface()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndActivate() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func buildInterface() {
        guard let contentView = window?.contentView else { return }

        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 16
        container.translatesAutoresizingMaskIntoConstraints = false

        let symbol = NSImageView()
        symbol.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "Accessibility required")
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)

        let titleLabel = NSTextField(labelWithString: "Islands needs Accessibility access before hotkeys can work.")
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        titleLabel.maximumNumberOfLines = 0

        let bodyLabel = NSTextField(wrappingLabelWithString: "Grant access in System Settings, then come back to Islands. Islands will offer a relaunch as soon as access is enabled so setup finishes cleanly.")
        bodyLabel.textColor = .secondaryLabelColor

        let stepsLabel = NSTextField(wrappingLabelWithString: "1. Click “Open Accessibility Settings”.\n2. Turn on Islands in the Accessibility list.\n3. Return to Islands. Access is rechecked automatically.")
        stepsLabel.font = .systemFont(ofSize: 13)

        let openButton = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openAccessibilitySettings))
        openButton.bezelStyle = .rounded

        let closeButton = NSButton(title: "Not Now", target: self, action: #selector(closeWindow))
        closeButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [openButton, closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        container.addArrangedSubview(symbol)
        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(bodyLabel)
        container.addArrangedSubview(stepsLabel)
        container.addArrangedSubview(buttonRow)

        contentView.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            container.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            container.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
        ])
    }

    @objc private func openAccessibilitySettings() {
        accessibilityManager.openSystemSettings()
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
