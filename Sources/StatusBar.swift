import AppKit

final class StatusBar {
    private var statusItem: NSStatusItem
    private let onOpenSettings: () -> Void

    init(onOpenSettings: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Islands")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Islands", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Set target for settings item
        menu.items[0].target = self

        statusItem.menu = menu
    }

    @objc private func openSettings() {
        onOpenSettings()
    }
}
