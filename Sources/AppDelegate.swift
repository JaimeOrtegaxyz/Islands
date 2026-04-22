import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBar!
    private var settingsStore: SettingsStore!
    private var accessibilityManager: AccessibilityManager!
    private var launchAtLoginController: LaunchAtLoginController!
    private var screenManager: ScreenManager!
    private var windowEngine: WindowEngine!
    private var windowManager: WindowManager!
    private var hotkeyManager: HotkeyManager!
    private var settingsWindowController: SettingsWindowController!
    private var accessibilityOnboardingWindowController: AccessibilityOnboardingWindowController!
    private var accessibilityPollTimer: Timer?
    private var lastAccessibilityTrustedState = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore = SettingsStore()
        accessibilityManager = .shared
        launchAtLoginController = LaunchAtLoginController()
        screenManager = ScreenManager()
        windowEngine = WindowEngine()
        windowManager = WindowManager(engine: windowEngine, screens: screenManager, settingsStore: settingsStore)
        hotkeyManager = HotkeyManager(windowManager: windowManager, settingsStore: settingsStore)
        settingsWindowController = SettingsWindowController(
            settingsStore: settingsStore,
            accessibilityManager: accessibilityManager,
            launchAtLoginController: launchAtLoginController
        )
        accessibilityOnboardingWindowController = AccessibilityOnboardingWindowController(accessibilityManager: accessibilityManager)
        statusBar = StatusBar { [weak self] in
            self?.showSettings()
        }

        lastAccessibilityTrustedState = accessibilityManager.isTrusted()
        evaluateAccessibility(showPromptIfNeeded: true)
        print("Islands is running.")
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        evaluateAccessibility(showPromptIfNeeded: false)
    }

    private func showSettings() {
        settingsWindowController.showWindowAndActivate()
    }

    private func evaluateAccessibility(showPromptIfNeeded: Bool) {
        let trusted = accessibilityManager.isTrusted()
        let wasTrusted = lastAccessibilityTrustedState
        lastAccessibilityTrustedState = trusted

        settingsWindowController.refreshSystemState()

        if trusted {
            stopAccessibilityPolling()

            if !wasTrusted {
                handleFreshAccessibilityGrant()
                return
            }

            hotkeyManager.setEnabled(true)
            accessibilityOnboardingWindowController.close()
        } else {
            hotkeyManager.setEnabled(false)
            startAccessibilityPolling()

            if showPromptIfNeeded {
                accessibilityOnboardingWindowController.showWindowAndActivate()
            }
        }
    }

    private func startAccessibilityPolling() {
        guard accessibilityPollTimer == nil else { return }

        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.evaluateAccessibility(showPromptIfNeeded: false)
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityPollTimer?.invalidate()
        accessibilityPollTimer = nil
    }

    private func handleFreshAccessibilityGrant() {
        hotkeyManager.setEnabled(false)
        accessibilityOnboardingWindowController.close()

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Accessibility access is enabled"
        alert.informativeText = "Islands can relaunch now to finish setup cleanly. This avoids the case where permission looks enabled but hotkeys still need a fresh process to work."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Relaunch Islands")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApplication()
        } else {
            hotkeyManager.setEnabled(true)
        }
    }

    private func relaunchApplication() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, error in
            if let error {
                self?.hotkeyManager.setEnabled(true)
                self?.presentRelaunchFailureAlert(message: error.localizedDescription)
                return
            }

            NSApp.terminate(nil)
        }
    }

    private func presentRelaunchFailureAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t relaunch Islands"
        alert.informativeText = "Accessibility is enabled, but the automatic relaunch failed: \(message)"
        alert.alertStyle = .warning
        alert.runModal()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopAccessibilityPolling()
        hotkeyManager.unregisterAll()
    }
}
