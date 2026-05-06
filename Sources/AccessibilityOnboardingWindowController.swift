import AppKit

final class AccessibilityOnboardingWindowController: NSWindowController {
    private let accessibilityManager: AccessibilityManager

    init(accessibilityManager: AccessibilityManager) {
        self.accessibilityManager = accessibilityManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Islands"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .islandsBrand
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
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.islandsBrand.cgColor

        // Background image fills the entire content area, aspect-filled so it
        // covers without stretching. NSImageView doesn't expose aspect-fill
        // directly, so we use a CALayer with resizeAspectFill gravity.
        let background = AspectFillImageView()
        background.translatesAutoresizingMaskIntoConstraints = false
        if let url = Bundle.main.url(forResource: "settings-small", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            background.image = image
        }
        contentView.addSubview(background)

        // Small palm centered at the bottom — accent / brand mark.
        let logo = NSImageView()
        logo.contentTintColor = .white
        logo.alphaValue = 0.85
        logo.translatesAutoresizingMaskIntoConstraints = false
        let logoHeight: CGFloat = 22
        if let url = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            let aspect = image.size.width / max(image.size.height, 1)
            image.size = NSSize(width: logoHeight * aspect, height: logoHeight)
            image.isTemplate = true
            logo.image = image
        }
        contentView.addSubview(logo)

        let title = WhiteLabel()
        title.stringValue = "Islands"
        title.font = .quicksand(30, weight: .semibold)
        title.alignment = .center

        let body = WhiteLabel()
        body.stringValue = "needs Accessibility access\nto move and arrange your windows."
        body.font = .quicksand(13, weight: .regular)
        body.alignment = .center
        body.alphaValue = 0.85
        body.maximumNumberOfLines = 0

        let openButton = OutlineButton(title: "Open System Settings")
        openButton.onClick = { [weak self] in self?.accessibilityManager.openSystemSettings() }

        let notNowButton = TextLinkButton(title: "Not now")
        notNowButton.onClick = { [weak self] in self?.window?.close() }

        let stack = NSStackView(views: [title, body, openButton, notNowButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.setCustomSpacing(10, after: title)
        stack.setCustomSpacing(28, after: body)
        stack.setCustomSpacing(10, after: openButton)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            background.topAnchor.constraint(equalTo: contentView.topAnchor),
            background.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            background.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            logo.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            logo.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -36),
        ])
    }
}

extension NSColor {
    static let islandsBrand = NSColor(
        srgbRed: 0x79 / 255.0,
        green: 0xB5 / 255.0,
        blue: 0xB5 / 255.0,
        alpha: 1.0
    )
}

private final class AspectFillImageView: NSView {
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.contentsGravity = .resizeAspectFill
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.contents = image
    }
}

private final class TextLinkButton: NSView {
    var onClick: (() -> Void)?

    private let label = WhiteLabel()
    private var trackingArea: NSTrackingArea?

    init(title: String) {
        super.init(frame: .zero)
        label.stringValue = title
        label.font = .quicksand(12, weight: .medium)
        label.alphaValue = 0.65
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
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
        label.alphaValue = 1.0
    }

    override func mouseExited(with event: NSEvent) {
        label.alphaValue = 0.65
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
