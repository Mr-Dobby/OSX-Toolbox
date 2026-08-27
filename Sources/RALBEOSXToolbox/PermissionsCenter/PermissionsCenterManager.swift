import AppKit
import CoreLocation

/// One place to request/check every permission this app can use across its
/// sub-apps: Accessibility, Input Monitoring, Full Disk Access, Location
/// Services, and Automation (System Events). Distinct from the "Permissions
/// Inspector" tool, which inspects OTHER apps' grants - this tab is only
/// about RALBE OSX Toolbox's own access.
@MainActor
final class PermissionsCenterManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PermissionsCenterManager()

    @Published var accessibilityTrusted = false
    @Published var fullDiskAccessGranted = false
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
        refresh()
    }

    func refresh() {
        accessibilityTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
        fullDiskAccessGranted = SystemPermissions.hasFullDiskAccess()
        locationStatus = locationManager.authorizationStatus
    }

    func requestAll() {
        _ = AccessibilityPermission.isTrusted(promptIfNeeded: true)
        if !SystemPermissions.hasFullDiskAccess() { SystemPermissions.promptFullDiskAccess() }
        locationManager.requestWhenInUseAuthorization()
        SystemPermissions.triggerAutomationPrompt()
        refresh()
    }

    func requestAccessibility() {
        _ = AccessibilityPermission.isTrusted(promptIfNeeded: true)
        refresh()
    }

    func requestFullDiskAccess() { SystemPermissions.promptFullDiskAccess() }
    func requestLocation() { locationManager.requestWhenInUseAuthorization() }
    func requestAutomation() { SystemPermissions.triggerAutomationPrompt() }

    func openAccessibilitySettings() { AccessibilityPermission.openAccessibilitySettings() }
    func openInputMonitoringSettings() { AccessibilityPermission.openInputMonitoringSettings() }
    func openFullDiskAccessSettings() { SystemPermissions.openFullDiskAccessSettings() }
    func openAutomationSettings() { SystemPermissions.openAutomationSettings() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    static func locationStatusDescription(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "Granted"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not Requested"
        @unknown default: return "Unknown"
        }
    }
}
