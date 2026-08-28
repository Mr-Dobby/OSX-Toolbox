import SwiftUI

/// Identifies each sub-app shown in the main dashboard window's sidebar.
enum ToolboxSection: String, CaseIterable, Identifiable, Hashable {
    case permissionsCenter = "Request Permissions"
    case caffeineInjection = "Caffeine Injection"
    case autoclicker = "Autoclicker"
    case appCleaner = "App Cleaner"
    case appUpdater = "App Updater"
    case appInstaller = "App Installer"
    case diskAnalyzer = "Disk Analyzer"
    case startupManager = "Startup & Login"
    case permissionsInspector = "Permissions Inspector"
    case networkToolbox = "Network Toolbox"
    case quickUtilities = "Quick Utilities"
    case processMonitor = "Process Monitor"
    case clipboardManager = "Clipboard Manager"
    case windowManager = "Window Manager"
    case fileFinder = "Quick File Finder"
    case screenshotToolbox = "Screenshot Toolbox"
    case fileConversion = "File Conversion"
    case imageEditor = "Image Editor"
    case webDashboard = "Web Dashboard"

    var id: String { rawValue }

    var group: String {
        switch self {
        case .permissionsCenter: return "Setup"
        case .caffeineInjection, .autoclicker, .appCleaner, .appUpdater, .appInstaller: return "Core Tools"
        case .diskAnalyzer, .startupManager, .permissionsInspector, .networkToolbox, .quickUtilities, .processMonitor: return "System"
        case .clipboardManager, .windowManager, .fileFinder, .screenshotToolbox, .fileConversion, .imageEditor: return "Productivity"
        case .webDashboard: return "Dashboard"
        }
    }

    static var groupedOrder: [(group: String, sections: [ToolboxSection])] {
        let groups = ["Setup", "Core Tools", "System", "Productivity", "Dashboard"]
        return groups.map { group in (group, allCases.filter { $0.group == group }) }
    }

    var systemImage: String {
        switch self {
        case .permissionsCenter: return "checkmark.shield.fill"
        case .caffeineInjection: return "cup.and.saucer.fill"
        case .autoclicker: return "cursorarrow.click.2"
        case .appCleaner: return "trash.fill"
        case .appUpdater: return "arrow.triangle.2.circlepath.circle.fill"
        case .appInstaller: return "arrow.down.app.fill"
        case .diskAnalyzer: return "internaldrive.fill"
        case .startupManager: return "power"
        case .permissionsInspector: return "hand.raised.fill"
        case .networkToolbox: return "network"
        case .quickUtilities: return "switch.2"
        case .processMonitor: return "cpu.fill"
        case .clipboardManager: return "doc.on.clipboard.fill"
        case .windowManager: return "macwindow"
        case .fileFinder: return "magnifyingglass"
        case .screenshotToolbox: return "camera.viewfinder"
        case .fileConversion: return "arrow.triangle.2.circlepath.doc.on.clipboard"
        case .imageEditor: return "wand.and.stars"
        case .webDashboard: return "chart.xyaxis.line"
        }
    }
}

/// Shared across the menu bar and the main window so that clicking a sub-app
/// in the tray (e.g. "Show Autoclicker") opens the main window scrolled to
/// the right section instead of a separate window per tool.
@MainActor
final class NavigationModel: ObservableObject {
    static let shared = NavigationModel()

    @Published var selection: ToolboxSection? = .caffeineInjection

    private init() {}
}
