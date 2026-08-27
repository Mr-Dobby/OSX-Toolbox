import SwiftUI

@main
struct RALBEOSXToolboxApp: App {
    @NSApplicationDelegateAdaptor(ToolboxAppDelegate.self) private var appDelegate

    @StateObject private var autoClicker = AutoClickerViewModel()
    @StateObject private var caffeine = CaffeineInjectionManager.shared
    @StateObject private var appCleaner = AppCleanerManager.shared
    @StateObject private var appUpdater = AppUpdaterManager.shared
    @StateObject private var appInstaller = AppInstallerManager.shared
    @StateObject private var navigation = NavigationModel.shared
    @StateObject private var permissionsCenter = PermissionsCenterManager.shared
    @StateObject private var diskAnalyzer = DiskAnalyzerManager.shared
    @StateObject private var startup = StartupManager.shared
    @StateObject private var permissionsInspector = PermissionsInspectorManager.shared
    @StateObject private var networkToolbox = NetworkToolboxManager.shared
    @StateObject private var quickUtilities = QuickUtilitiesManager.shared
    @StateObject private var processMonitor = ProcessMonitorManager.shared
    @StateObject private var clipboard = ClipboardHistoryManager.shared
    @StateObject private var windowManager = WindowManagerService.shared
    @StateObject private var fileFinder = QuickFileFinderManager.shared
    @StateObject private var screenshotToolbox = ScreenshotToolboxManager.shared
    @StateObject private var fileConversion = FileConversionManager.shared
    @StateObject private var webDashboard = WebDashboardManager.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            MainDashboardView(
                autoClicker: autoClicker,
                caffeine: caffeine,
                appCleaner: appCleaner,
                appUpdater: appUpdater,
                appInstaller: appInstaller,
                navigation: navigation,
                permissionsCenter: permissionsCenter,
                diskAnalyzer: diskAnalyzer,
                startup: startup,
                permissionsInspector: permissionsInspector,
                networkToolbox: networkToolbox,
                quickUtilities: quickUtilities,
                processMonitor: processMonitor,
                clipboard: clipboard,
                windowManager: windowManager,
                fileFinder: fileFinder,
                screenshotToolbox: screenshotToolbox,
                fileConversion: fileConversion,
                webDashboard: webDashboard
            )
        }

        MenuBarExtra {
            ToolboxMenuBarView(autoClicker: autoClicker, caffeine: caffeine, appCleaner: appCleaner, appUpdater: appUpdater, appInstaller: appInstaller, navigation: navigation, quickUtilities: quickUtilities, webDashboard: webDashboard)
        } label: {
            // Reflects Caffeine Injection's manual/trigger on-off state live,
            // instead of a static icon that never changed with the toggles.
            Label {
                Text("RALBE OSX Toolbox")
            } icon: {
                HStack(spacing: 3) {
                    Image(systemName: "shippingbox.fill")
                    Text(caffeine.menuBarIcon)
                }
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
