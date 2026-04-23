import AppKit

final class StatusBar {
    private var statusItem: NSStatusItem
    private let onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusBar.loadStatusBarImage()
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Islands", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.items[0].target = self

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    private static func loadStatusBarImage() -> NSImage {
        let targetHeight: CGFloat = 18

        if let url = Bundle.main.url(forResource: "StatusBarIcon", withExtension: "svg"),
           let image = NSImage(contentsOf: url) {
            let aspect = image.size.width / max(image.size.height, 1)
            image.size = NSSize(width: targetHeight * aspect, height: targetHeight)
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Islands") ?? NSImage()
        fallback.isTemplate = true
        return fallback
    }
}
