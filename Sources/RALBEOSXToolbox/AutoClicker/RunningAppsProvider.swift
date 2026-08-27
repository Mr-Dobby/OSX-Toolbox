import AppKit

/// Lightweight, Hashable snapshot of a running application usable as a SwiftUI Picker tag.
struct RunningAppInfo: Identifiable, Hashable {
    let id: pid_t
    let name: String
    let bundleIdentifier: String?
}

/// Fetches the list of currently running, user-facing (Dock-visible) applications.
enum RunningAppsProvider {
    static func fetch() -> [RunningAppInfo] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningAppInfo? in
                guard let name = app.localizedName else { return nil }
                return RunningAppInfo(id: app.processIdentifier, name: name, bundleIdentifier: app.bundleIdentifier)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
