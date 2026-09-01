import AppKit

/// Handles one-time app-launch setup: requesting permissions and starting
/// every sub-app's background timers/hotkeys/watchers.
@MainActor
final class ToolboxAppDelegate: NSObject, NSApplicationDelegate {
    private var hasShutDown = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        SystemPermissions.requestAllIfNeeded()
        CaffeineInjectionManager.shared.start()
        QuickUtilitiesManager.shared.start()
        ProcessMonitorManager.shared.start()
        ClipboardHistoryManager.shared.start()
        WindowManagerService.shared.start()
    }

    /// Command-Q and the menu-bar Quit item both route through this delegate
    /// method. Returning immediately prevents a persistent helper (such as
    /// `caffeinate`) from leaving the toolbox apparently alive after quitting.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        shutDownServices()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutDownServices()
    }

    private func shutDownServices() {
        guard !hasShutDown else { return }
        hasShutDown = true
        WebDashboardManager.shared.stop()
        CaffeineInjectionManager.shared.stop()
        ClipboardHistoryManager.shared.stop()
        ProcessMonitorManager.shared.stop()
        QuickUtilitiesManager.shared.stop()
        WindowManagerService.shared.stop()
    }
}
