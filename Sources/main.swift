import AppKit
import ApplicationServices

// Check Accessibility permission — prompt if not trusted
let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
if !AXIsProcessTrustedWithOptions(options) {
    print("Islands requires Accessibility permission. Please grant it in System Settings > Privacy & Security > Accessibility, then relaunch.")
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
