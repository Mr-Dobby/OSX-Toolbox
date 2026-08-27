import AppKit

/// Handles one-time app-launch setup: requesting permissions and starting
/// every sub-app's background timers/hotkeys/watchers.
final class ToolboxAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemPermissions.requestAllIfNeeded()
        CaffeineInjectionManager.shared.start()
        QuickUtilitiesManager.shared.start()
        ProcessMonitorManager.shared.start()
        ClipboardHistoryManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        WebDashboardManager.shared.stop()
    }
}
