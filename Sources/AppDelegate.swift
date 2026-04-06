import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBar!
    private var screenManager: ScreenManager!
    private var windowEngine: WindowEngine!
    private var windowManager: WindowManager!
    private var hotkeyManager: HotkeyManager!

    func applicationDidFinishLaunching(_ notification: Notification) {
        screenManager = ScreenManager()
        windowEngine = WindowEngine()
        windowManager = WindowManager(engine: windowEngine, screens: screenManager)
        hotkeyManager = HotkeyManager(windowManager: windowManager)
        statusBar = StatusBar()

        hotkeyManager.registerAll()
        print("Islands is running.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.unregisterAll()
    }
}
