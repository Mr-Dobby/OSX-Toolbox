import AppKit

struct PermissionGrant: Identifiable {
    let id = UUID()
    let client: String
    let service: String
    let authValue: Int
}

/// Reads the system TCC database (requires Full Disk Access) via the
/// `sqlite3` CLI to show which apps were granted which privacy permissions.
/// The `auth_value` interpretation (0=Denied, 2=Allowed) is the commonly
/// documented layout but is best-effort and may not match every macOS
/// version exactly.
@MainActor
final class PermissionsInspectorManager: ObservableObject {
    static let shared = PermissionsInspectorManager()

    @Published var grants: [PermissionGrant] = []
    @Published var lastError: String?

    private let dbPath = "/Library/Application Support/com.apple.TCC/TCC.db"

    private init() {}

    func refresh() {
        guard SystemPermissions.hasFullDiskAccess() else {
            lastError = "Full Disk Access is required to read the system permissions database."
            grants = []
            return
        }
        let output = caffeineShell("/usr/bin/sqlite3", ["-separator", "|", dbPath, "SELECT client, service, auth_value FROM access ORDER BY client;"])
        guard !output.isEmpty else {
            lastError = "No data returned - the database may be locked or unreadable."
            grants = []
            return
        }
        lastError = nil
        grants = output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 3, let auth = Int(parts[2]) else { return nil }
            return PermissionGrant(client: parts[0], service: parts[1], authValue: auth)
        }
    }

    static func serviceDisplayName(_ raw: String) -> String {
        let map: [String: String] = [
            "kTCCServiceCamera": "Camera",
            "kTCCServiceMicrophone": "Microphone",
            "kTCCServiceAccessibility": "Accessibility",
            "kTCCServiceSystemPolicyAllFiles": "Full Disk Access",
            "kTCCServiceScreenCapture": "Screen Recording",
            "kTCCServiceContactsFull": "Contacts",
            "kTCCServicePhotos": "Photos",
            "kTCCServiceReminders": "Reminders",
            "kTCCServiceCalendar": "Calendar",
            "kTCCServiceBluetoothAlways": "Bluetooth",
            "kTCCServiceListenEvent": "Input Monitoring",
            "kTCCServiceMediaLibrary": "Media & Apple Music",
            "kTCCServiceLocation": "Location Services",
            "kTCCServiceUbiquity": "iCloud",
        ]
        return map[raw] ?? raw
    }

    static func authDescription(_ value: Int) -> String {
        switch value {
        case 2: return "Allowed"
        case 0: return "Denied"
        default: return "Prompt / Unknown"
        }
    }

    private static let settingsDeepLinks: [String: String] = [
        "kTCCServiceCamera": "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera",
        "kTCCServiceMicrophone": "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
        "kTCCServiceAccessibility": "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        "kTCCServiceSystemPolicyAllFiles": "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        "kTCCServiceScreenCapture": "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        "kTCCServiceContactsFull": "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts",
        "kTCCServicePhotos": "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos",
        "kTCCServiceListenEvent": "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        "kTCCServiceLocation": "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
    ]

    func openSettings(for service: String) {
        guard let str = Self.settingsDeepLinks[service], let url = URL(string: str) else { return }
        NSWorkspace.shared.open(url)
    }
}
