import AppKit
import Sparkle

final class StatusBar {
    private var statusItem: NSStatusItem
    private let onOpenSettings: () -> Void
    private let updaterController: SPUStandardUpdaterController

    init(updaterController: SPUStandardUpdaterController, onOpenSettings: @escaping () -> Void) {
        self.updaterController = updaterController
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusBar.loadStatusBarImage()
        }

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = updaterController
        menu.addItem(updatesItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Islands", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

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
