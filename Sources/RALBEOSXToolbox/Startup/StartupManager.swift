import AppKit

struct StartupItem: Identifiable {
    let id = UUID()
    let label: String
    let path: String
    let scope: String
    var enabled: Bool
}

/// Lists LaunchAgents/LaunchDaemons plist files plus GUI Login Items (via
/// System Events AppleScript - the only remaining way to enumerate arbitrary
/// third-party login items without their bundle IDs). Toggling
/// LaunchAgents/Daemons requires write access to their directory (system
/// ones need admin and will silently no-op without it); toggling a Login
/// Item removes/re-adds it via System Events.
@MainActor
final class StartupManager: ObservableObject {
    static let shared = StartupManager()

    @Published var items: [StartupItem] = []

    private let plistLocations: [(String, String)] = [
        (NSHomeDirectory() + "/Library/LaunchAgents", "User LaunchAgent"),
        ("/Library/LaunchAgents", "System LaunchAgent"),
        ("/Library/LaunchDaemons", "System LaunchDaemon"),
    ]

    private init() {}

    /// Gathers plist files and login items on a background queue -
    /// `fetchLoginItems()` blocks on `osascript`, and running that
    /// synchronously on the main thread (as `init()` used to) can reenter
    /// SwiftUI's attribute graph update via `Process.waitUntilExit()`'s
    /// internal run loop pump and crash with an AttributeGraph precondition
    /// failure. Always refresh off the main thread, then hop back to
    /// publish `items`.
    func refresh() {
        let locations = plistLocations
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [StartupItem] = []
            let fm = FileManager.default
            for (dir, scope) in locations {
                guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
                for file in files where file.hasSuffix(".plist") {
                    let full = "\(dir)/\(file)"
                    let disabled = fm.fileExists(atPath: full + ".disabled")
                    results.append(StartupItem(label: file.replacingOccurrences(of: ".plist", with: ""), path: full, scope: scope, enabled: !disabled))
                }
            }
            results.append(contentsOf: Self.fetchLoginItems())
            let sorted = results.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            Task { @MainActor in
                self?.items = sorted
            }
        }
    }

    nonisolated private static func fetchLoginItems() -> [StartupItem] {
        let namesOut = caffeineShell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get the name of every login item"])
        let pathsOut = caffeineShell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get the path of every login item"])
        let names = namesOut.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ", ").filter { !$0.isEmpty }
        let paths = pathsOut.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ", ")
        guard !names.isEmpty, names.count == paths.count else { return [] }
        return zip(names, paths).map { StartupItem(label: $0, path: $1, scope: "Login Item", enabled: true) }
    }

    func toggle(_ item: StartupItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let fm = FileManager.default
            if item.scope == "Login Item" {
                let script = "tell application \"System Events\" to delete login item \"\(item.label)\""
                _ = caffeineShell("/usr/bin/osascript", ["-e", script])
            } else {
                let dir = (item.path as NSString).deletingLastPathComponent
                let disabledPath = item.path + ".disabled"
                let writable = fm.isWritableFile(atPath: dir)
                if item.enabled {
                    if writable {
                        _ = caffeineShell("/bin/launchctl", ["unload", item.path])
                        try? fm.moveItem(atPath: item.path, toPath: disabledPath)
                    } else {
                        Self.runElevated("launchctl unload \(item.path.shellQuotedForInstall) 2>/dev/null; mv \(item.path.shellQuotedForInstall) \(disabledPath.shellQuotedForInstall)")
                    }
                } else {
                    if writable {
                        if fm.fileExists(atPath: disabledPath) {
                            try? fm.moveItem(atPath: disabledPath, toPath: item.path)
                        }
                        _ = caffeineShell("/bin/launchctl", ["load", item.path])
                    } else {
                        Self.runElevated("mv \(disabledPath.shellQuotedForInstall) \(item.path.shellQuotedForInstall) 2>/dev/null; launchctl load \(item.path.shellQuotedForInstall)")
                    }
                }
            }
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Deletes the item outright rather than just disabling it - a plist's
    /// ".disabled" sibling is cleaned up too so it can't reappear on a
    /// future re-enable attempt.
    func remove(_ item: StartupItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if item.scope == "Login Item" {
                let script = "tell application \"System Events\" to delete login item \"\(item.label)\""
                _ = caffeineShell("/usr/bin/osascript", ["-e", script])
            } else {
                let fm = FileManager.default
                let dir = (item.path as NSString).deletingLastPathComponent
                let disabledPath = item.path + ".disabled"
                if fm.isWritableFile(atPath: dir) {
                    _ = caffeineShell("/bin/launchctl", ["unload", item.path])
                    try? fm.removeItem(atPath: item.path)
                    try? fm.removeItem(atPath: disabledPath)
                } else {
                    Self.runElevated("launchctl unload \(item.path.shellQuotedForInstall) 2>/dev/null; rm -f \(item.path.shellQuotedForInstall) \(disabledPath.shellQuotedForInstall)")
                }
            }
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Lets the user pick any app to add as a GUI Login Item - the same
    /// mechanism (and the only scriptable one) System Settings > Login
    /// Items itself uses; adding a custom LaunchAgent plist for an arbitrary
    /// app would need its own launch command, which we don't know.
    func pickAppToAddAsLoginItem() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add to Login Items"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addLoginItem(path: url.path)
    }

    private func addLoginItem(path: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to make login item at end with properties {path:\"\(escapedPath)\", hidden:false}"
            _ = caffeineShell("/usr/bin/osascript", ["-e", script])
            Task { @MainActor in self?.refresh() }
        }
    }

    nonisolated private static func runElevated(_ shellCommand: String) {
        let script = "do shell script \"\(shellCommand.replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        (try? process.run())
        process.waitUntilExit()
    }

    func reveal(_ item: StartupItem) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
    }
}
