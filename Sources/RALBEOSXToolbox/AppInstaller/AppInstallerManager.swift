import AppKit

struct BrewSearchResult: Identifiable, Hashable {
    let id: String
    let name: String
    let isCask: Bool
}

struct MASSearchResult: Identifiable, Hashable {
    let id: String
    let name: String
}

enum InstallActionStatus: Equatable {
    case idle
    case working(String)
    case succeeded(String)
    case failed(String)
}

/// Installs new apps from the three practical sources on macOS: Homebrew
/// (formulae + casks), the Mac App Store (via the third-party `mas` CLI -
/// there is no public App Store install API), and a direct dmg/zip/pkg
/// download URL (shares its download/extract/verify pipeline with
/// AppUpdaterManager via PackageInstallHelpers.swift).
@MainActor
final class AppInstallerManager: NSObject, ObservableObject {
    static let shared = AppInstallerManager()

    @Published var brewQuery = ""
    @Published var brewResults: [BrewSearchResult] = []
    @Published var isSearchingBrew = false
    @Published var brewSearchError: String?
    @Published var brewInstallStatus: [String: InstallActionStatus] = [:]

    @Published var masQuery = ""
    @Published var masResults: [MASSearchResult] = []
    @Published var isSearchingMAS = false
    @Published var masSearchError: String?
    @Published var masInstallStatus: [String: InstallActionStatus] = [:]
    @Published var isMASInstalled = false
    @Published var isInstallingMASTool = false
    @Published var masToolInstallError: String?

    @Published var directURLString = ""
    @Published var directInstallStatus: InstallActionStatus = .idle

    var isHomebrewInstalled: Bool { Self.resolveBrewPath() != nil }

    private override init() {
        super.init()
        isMASInstalled = Self.resolveMASPath() != nil
    }

    nonisolated private static func resolveBrewPath() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    nonisolated private static func resolveMASPath() -> String? {
        for path in ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: Homebrew search / install

    func searchBrew() {
        let query = brewQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { brewResults = []; return }
        guard let brewPath = Self.resolveBrewPath() else {
            brewSearchError = "Homebrew not found (checked /opt/homebrew and /usr/local)."
            return
        }
        brewSearchError = nil
        isSearchingBrew = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let formulaOutput = caffeineShell(brewPath, ["search", "--formula", query])
            let caskOutput = caffeineShell(brewPath, ["search", "--cask", query])
            let formulae = Self.parseSearchLines(formulaOutput).map { BrewSearchResult(id: "formula:\($0)", name: $0, isCask: false) }
            let casks = Self.parseSearchLines(caskOutput).map { BrewSearchResult(id: "cask:\($0)", name: $0, isCask: true) }
            let combined = Array((casks + formulae).prefix(40))
            Task { @MainActor in
                self?.brewResults = combined
                self?.isSearchingBrew = false
            }
        }
    }

    nonisolated private static func parseSearchLines(_ output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
    }

    func installBrewResult(_ result: BrewSearchResult) {
        guard let brewPath = Self.resolveBrewPath() else { return }
        brewInstallStatus[result.id] = .working("Installing…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = ["install"]
            if result.isCask { args.append("--cask") }
            args.append(result.name)
            let output = caffeineShell(brewPath, args)
            let failed = output.lowercased().contains("error:")
            Task { @MainActor in
                self?.brewInstallStatus[result.id] = failed ? .failed(String(output.suffix(500))) : .succeeded("Installed \(result.name).")
            }
        }
    }

    // MARK: Mac App Store search / install (via `mas` CLI)

    /// `mas` is a separate Homebrew-installable CLI, not bundled with macOS -
    /// installs it the same way as any other formula, then re-checks for it
    /// on disk so the UI can switch straight to the search form.
    func installMASTool() {
        guard let brewPath = Self.resolveBrewPath() else { return }
        isInstallingMASTool = true
        masToolInstallError = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell(brewPath, ["install", "mas"])
            let installed = Self.resolveMASPath() != nil
            Task { @MainActor in
                self?.isInstallingMASTool = false
                self?.isMASInstalled = installed
                if installed {
                    self?.refreshMASAccount()
                } else {
                    self?.masToolInstallError = String(output.suffix(500))
                }
            }
        }
    }

    /// `mas` 2.x+ removed the `account` subcommand (the private App Store
    /// API it relied on for this went away), so sign-in status can no
    /// longer be checked ahead of time - just re-checks `mas` is on disk.
    func refreshMASAccount() {
        isMASInstalled = Self.resolveMASPath() != nil
    }

    func searchMAS() {
        let query = masQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { masResults = []; return }
        guard let masPath = Self.resolveMASPath() else {
            masSearchError = "The 'mas' command-line tool isn't installed. Install it with Homebrew: brew install mas"
            return
        }
        masSearchError = nil
        isSearchingMAS = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell(masPath, ["search", query])
            let results = Self.parseMASSearch(output)
            Task { @MainActor in
                self?.masResults = results
                self?.isSearchingMAS = false
            }
        }
    }

    nonisolated private static func parseMASSearch(_ output: String) -> [MASSearchResult] {
        var results: [MASSearchResult] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = line.firstIndex(of: " ") else { continue }
            let idPart = String(line[line.startIndex..<firstSpace])
            guard Int(idPart) != nil else { continue }
            let namePart = String(line[line.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)
            results.append(MASSearchResult(id: idPart, name: namePart))
        }
        return Array(results.prefix(30))
    }

    func installMASResult(_ result: MASSearchResult) {
        guard let masPath = Self.resolveMASPath() else { return }
        masInstallStatus[result.id] = .working("Installing (requires being signed in to the App Store app)…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell(masPath, ["install", result.id])
            let lower = output.lowercased()
            let failed = lower.contains("error") || lower.contains("not signed in")
            Task { @MainActor in
                self?.masInstallStatus[result.id] = failed ? .failed(String(output.suffix(500))) : .succeeded("Installed \(result.name).")
            }
        }
    }

    // MARK: Direct download URL install (dmg / zip / pkg)

    func installFromDirectURL() {
        let trimmed = directURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, scheme == "https" || scheme == "http" else {
            directInstallStatus = .failed("Enter a valid http(s) download URL ending in .dmg, .zip, or .pkg.")
            return
        }
        directInstallStatus = .working("Downloading…")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let downloadedPath = try downloadPackageFile(url: url)
                let ext = (downloadedPath as NSString).pathExtension.lowercased()

                if ext == "pkg" {
                    Task { @MainActor in
                        // .pkg installers can run arbitrary postinstall
                        // scripts - hand off to Installer.app rather than
                        // scripting that ourselves.
                        NSWorkspace.shared.open(URL(fileURLWithPath: downloadedPath))
                        self.directInstallStatus = .succeeded("Opened in Installer - finish there.")
                    }
                    return
                }

                let extractedAppPath: String
                if ext == "dmg" {
                    extractedAppPath = try extractAppFromDMG(downloadedPath)
                } else if ext == "zip" {
                    extractedAppPath = try extractAppFromZip(downloadedPath)
                } else {
                    throw PackageInstallError.unsupportedFormat(ext.isEmpty ? "unknown" : ext)
                }

                guard verifyAppCodesign(extractedAppPath) else {
                    throw PackageInstallError.signatureVerificationFailed
                }

                Task { @MainActor in
                    self.confirmAndInstall(appPath: extractedAppPath)
                }
            } catch {
                Task { @MainActor in
                    self.directInstallStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func confirmAndInstall(appPath: String) {
        let appName = (appPath as NSString).lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Install \(appName)?"
        alert.informativeText = "This copies \(appName) into /Applications, replacing any existing copy with the same name."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            directInstallStatus = .idle
            return
        }
        directInstallStatus = .working("Installing…")
        let destination = "/Applications/\(appName)"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            if fm.isWritableFile(atPath: "/Applications") {
                do {
                    if fm.fileExists(atPath: destination) {
                        try fm.removeItem(atPath: destination)
                    }
                    try fm.copyItem(atPath: appPath, toPath: destination)
                    Task { @MainActor in self.directInstallStatus = .succeeded("Installed to \(destination).") }
                } catch {
                    Task { @MainActor in self.directInstallStatus = .failed(error.localizedDescription) }
                }
            } else {
                // No write access to /Applications - falls back to the
                // native macOS admin password/Touch ID prompt, same pattern
                // as AppUpdaterManager's elevated-install path.
                let script = "do shell script \"rm -rf \(destination.shellQuotedForInstall) && cp -R \(appPath.shellQuotedForInstall) \(destination.shellQuotedForInstall)\" with administrator privileges"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                (try? process.run())
                process.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                Task { @MainActor in
                    self.directInstallStatus = process.terminationStatus == 0
                        ? .succeeded("Installed to \(destination).")
                        : .failed(output.isEmpty ? "Cancelled or administrator authorization was not granted." : output)
                }
            }
        }
    }
}
