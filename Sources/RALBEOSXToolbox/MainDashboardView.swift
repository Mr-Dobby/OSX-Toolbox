import SwiftUI

/// The main application window: a grouped sidebar listing every sub-app,
/// with the selected one's full configuration screen shown in the detail
/// pane. This is what opens when the user launches "RALBE OSX Toolbox"
/// itself (as opposed to the menu bar, which offers quick actions).
struct MainDashboardView: View {
    @ObservedObject var autoClicker: AutoClickerViewModel
    @ObservedObject var caffeine: CaffeineInjectionManager
    @ObservedObject var appCleaner: AppCleanerManager
    @ObservedObject var appUpdater: AppUpdaterManager
    @ObservedObject var appInstaller: AppInstallerManager
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var permissionsCenter: PermissionsCenterManager
    @ObservedObject var diskAnalyzer: DiskAnalyzerManager
    @ObservedObject var startup: StartupManager
    @ObservedObject var permissionsInspector: PermissionsInspectorManager
    @ObservedObject var networkToolbox: NetworkToolboxManager
    @ObservedObject var quickUtilities: QuickUtilitiesManager
    @ObservedObject var processMonitor: ProcessMonitorManager
    @ObservedObject var clipboard: ClipboardHistoryManager
    @ObservedObject var windowManager: WindowManagerService
    @ObservedObject var fileFinder: QuickFileFinderManager
    @ObservedObject var screenshotToolbox: ScreenshotToolboxManager
    @ObservedObject var fileConversion: FileConversionManager
    @ObservedObject var webDashboard: WebDashboardManager

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.selection) {
                ForEach(ToolboxSection.groupedOrder, id: \.group) { group in
                    Section(group.group) {
                        ForEach(group.sections) { section in
                            Label(section.rawValue, systemImage: section.systemImage)
                                .tag(section)
                        }
                    }
                }
            }
            .navigationTitle("RALBE OSX Toolbox")
            .frame(minWidth: 220)
        } detail: {
            detailView
                .navigationTitle(navigation.selection?.rawValue ?? "RALBE OSX Toolbox")
        }
        .frame(minWidth: 900, minHeight: 640)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigation.selection {
        case .permissionsCenter:
            PermissionsCenterView(manager: permissionsCenter)
        case .caffeineInjection:
            CaffeineInjectionSettingsView(caffeine: caffeine)
        case .autoclicker:
            ContentView(viewModel: autoClicker)
        case .appCleaner:
            AppCleanerView(appCleaner: appCleaner)
        case .appUpdater:
            AppUpdaterView(manager: appUpdater)
        case .appInstaller:
            AppInstallerView(manager: appInstaller)
        case .diskAnalyzer:
            DiskAnalyzerView(manager: diskAnalyzer)
        case .startupManager:
            StartupView(manager: startup)
        case .permissionsInspector:
            PermissionsInspectorView(manager: permissionsInspector)
        case .networkToolbox:
            NetworkToolboxView(manager: networkToolbox)
        case .quickUtilities:
            QuickUtilitiesView(manager: quickUtilities)
        case .processMonitor:
            ProcessMonitorView(manager: processMonitor)
        case .clipboardManager:
            ClipboardManagerView(manager: clipboard)
        case .windowManager:
            WindowManagerView(manager: windowManager)
        case .fileFinder:
            QuickFileFinderView(manager: fileFinder)
        case .screenshotToolbox:
            ScreenshotToolboxView(manager: screenshotToolbox)
        case .fileConversion:
            FileConversionView(manager: fileConversion)
        case .webDashboard:
            WebDashboardView(manager: webDashboard)
        case nil:
            VStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Choose a Tool")
                    .font(.title3)
                Text("Select a tool from the sidebar.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

