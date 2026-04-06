import AppKit

final class StatusBar {
    private var statusItem: NSStatusItem

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.split.2x2", accessibilityDescription: "Islands")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "About Islands", action: #selector(aboutClicked), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Islands", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        // Set target for about item
        menu.items[0].target = self

        statusItem.menu = menu
    }

    @objc private func aboutClicked() {
        let alert = NSAlert()
        alert.messageText = "Islands"
        alert.informativeText = "A native macOS window manager.\nKeyboard-driven window tiling with accordion stacking."
        alert.alertStyle = .informational
        alert.runModal()
    }
}
