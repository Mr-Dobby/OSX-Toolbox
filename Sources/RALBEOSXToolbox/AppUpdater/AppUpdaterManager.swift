import AppKit

struct InstalledAppInfo: Identifiable, Equatable {
    let id: String // bundle path, stable per-install
    let name: String
    let bundleIdentifier: String
    let currentVersion: String
    let path: String
    let feedURL: URL?
    let isMacAppStore: Bool
}

enum UpdateCheckResult {
    case upToDate
    case updateAvailable(version: String, enclosureURL: URL, enclosureType: String, releaseNotes: String?)
    case noFeed
    case checkFailed(String)
}

enum UpdateError: LocalizedError {
    case downloadFailed
    case mountFailed
    case appNotFoundInPackage
    case signatureVerificationFailed
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "The update file could not be downloaded."
        case .mountFailed: return "The downloaded disk image could not be mounted."
        case .appNotFoundInPackage: return "No .app bundle was found in the downloaded update."
        case .signatureVerificationFailed: return "The downloaded update failed code signature verification and was NOT installed."
        case .unsupportedFormat(let ext): return "Unsupported update file format: .\(ext)"
        }
    }
}

/// One Homebrew-managed package (formula or cask) with its installed and
/// latest-available version, both reported directly by `brew info` - no
/// manual version comparison needed for these, unlike the Sparkle path.
struct HomebrewPackageInfo: Identifiable {
    let id: String
    /// The name/token `brew` itself expects on the command line - NOT
    /// necessarily the same as `displayName` (casks have a separate token).
    let identifier: String
    let displayName: String
    let isCask: Bool
    let installedVersion: String
    let latestVersion: String
    var isOutdated: Bool { installedVersion != latestVersion }
}

private struct BrewInfoResult: Decodable {
    let formulae: [BrewFormula]
    let casks: [BrewCask]
}

private struct BrewFormula: Decodable {
    let name: String
    let versions: Versions
    let installed: [InstalledVersion]
    struct Versions: Decodable { let stable: String? }
    struct InstalledVersion: Decodable { let version: String }
}

private struct BrewCask: Decodable {
    let token: String
    let name: [String]
    let version: String?
    let installed: String?
}

/// One outdated Mac App Store app, as reported by `mas outdated` (id/name/
/// installed/latest all come straight from that one command - no separate
/// per-app check needed, same as the Homebrew path).
struct MASOutdatedAppInfo: Identifiable {
    let id: String
    let name: String
    let installedVersion: String
    let latestVersion: String
}

/// Scans installed apps for a Sparkle update feed (`SUFeedURL` in
/// Info.plist - the same mechanism the app itself already uses to check for
/// updates), fetches/parses the appcast, and can download + install a
/// newer version. There is no universal "check any app for updates" API on
/// macOS: apps without a Sparkle feed (including most Mac App Store apps)
/// are reported as "no feed" rather than silently skipped, so the user
/// knows to check the App Store or developer site instead.
@MainActor
final class AppUpdaterManager: NSObject, ObservableObject {
    static let shared = AppUpdaterManager()

    @Published var apps: [InstalledAppInfo] = []
    @Published var results: [String: UpdateCheckResult] = [:]
    @Published var installStatus: [String: String] = [:]
    @Published var isScanning = false
    @Published var isCheckingAll = false
    @Published var isUpdatingEverything = false

    @Published var brewPackages: [HomebrewPackageInfo] = []
    @Published var isCheckingBrew = false
    @Published var brewError: String?
    @Published var brewUpdateStatus: [String: String] = [:]

    @Published var masOutdatedApps: [MASOutdatedAppInfo] = []
    @Published var isCheckingMAS = false
    @Published var masError: String?
    @Published var masUpdateStatus: [String: String] = [:]

    private override init() { super.init() }

    // MARK: Scan

    func scanInstalledApps(completion: (() -> Void)? = nil) {
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
            let fm = FileManager.default
            var found: [InstalledAppInfo] = []
            for root in roots {
                guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
                for entry in entries where entry.hasSuffix(".app") {
                    let appPath = "\(root)/\(entry)"
                    guard let bundle = Bundle(path: appPath), let bundleID = bundle.bundleIdentifier else { continue }
                    let info = bundle.infoDictionary
                    let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? entry.replacingOccurrences(of: ".app", with: "")
                    let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
                    let feedURL = (info?["SUFeedURL"] as? String).flatMap { URL(string: $0) }
                    let isMAS = fm.fileExists(atPath: appPath + "/Contents/_MASReceipt/receipt")
                    found.append(InstalledAppInfo(id: appPath, name: name, bundleIdentifier: bundleID, currentVersion: version, path: appPath, feedURL: feedURL, isMacAppStore: isMAS))
                }
            }
            let sorted = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            Task { @MainActor in
                self?.apps = sorted
                self?.isScanning = false
                completion?()
            }
        }
    }

    // MARK: Homebrew / Cask

    nonisolated private static func resolveBrewPath() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    var isHomebrewInstalled: Bool { Self.resolveBrewPath() != nil }

    /// A single `brew info --json=v2 --installed` call reports both formulae
    /// and casks with their installed AND latest-available versions in one
    /// shot, so - unlike the Sparkle path - no separate "check" step is
    /// needed after scanning.
    func scanHomebrewPackages(completion: (() -> Void)? = nil) {
        guard let brewPath = Self.resolveBrewPath() else {
            brewError = "Homebrew not found (checked /opt/homebrew and /usr/local)."
            brewPackages = []
            completion?()
            return
        }
        brewError = nil
        isCheckingBrew = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell(brewPath, ["info", "--json=v2", "--installed"])
            guard let data = output.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(BrewInfoResult.self, from: data) else {
                Task { @MainActor in
                    self?.brewError = "Could not read Homebrew's package list."
                    self?.isCheckingBrew = false
                    completion?()
                }
                return
            }

            var packages: [HomebrewPackageInfo] = []
            for formula in decoded.formulae {
                guard let latest = formula.versions.stable, let installed = formula.installed.last?.version else { continue }
                packages.append(HomebrewPackageInfo(id: "formula:\(formula.name)", identifier: formula.name, displayName: formula.name, isCask: false, installedVersion: installed, latestVersion: latest))
            }
            for cask in decoded.casks {
                guard let installed = cask.installed, let latest = cask.version else { continue }
                packages.append(HomebrewPackageInfo(id: "cask:\(cask.token)", identifier: cask.token, displayName: cask.name.first ?? cask.token, isCask: true, installedVersion: installed, latestVersion: latest))
            }
            let sorted = packages.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            Task { @MainActor in
                self?.brewPackages = sorted
                self?.isCheckingBrew = false
                completion?()
            }
        }
    }

    func upgradeBrewPackage(_ package: HomebrewPackageInfo) {
        guard let brewPath = Self.resolveBrewPath() else { return }
        brewUpdateStatus[package.id] = "Upgrading…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var args = ["upgrade"]
            if package.isCask { args.append("--cask") }
            args.append(package.identifier)
            let output = caffeineShell(brewPath, args).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self?.brewUpdateStatus[package.id] = output.isEmpty ? "Upgraded." : String(output.suffix(400))
                self?.scanHomebrewPackages()
            }
        }
    }

    // MARK: Mac App Store (via `mas` CLI)

    nonisolated private static func resolveMASPath() -> String? {
        for path in ["/opt/homebrew/bin/mas", "/usr/local/bin/mas"] {
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    var isMASToolInstalled: Bool { Self.resolveMASPath() != nil }

    /// `mas outdated` reports id/name/installed/latest for every outdated
    /// Mac App Store app in one call - same one-shot shape as the Homebrew
    /// path, no separate per-app check needed.
    func scanMASOutdated(completion: (() -> Void)? = nil) {
        guard let masPath = Self.resolveMASPath() else {
            masError = "The 'mas' command-line tool isn't installed (install it from the App Installer tab to enable Mac App Store update checks)."
            masOutdatedApps = []
            completion?()
            return
        }
        masError = nil
        isCheckingMAS = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell(masPath, ["outdated"])
            let parsed = Self.parseMASOutdated(output)
            Task { @MainActor in
                self?.masOutdatedApps = parsed
                self?.isCheckingMAS = false
                completion?()
            }
        }
    }

    nonisolated private static func parseMASOutdated(_ output: String) -> [MASOutdatedAppInfo] {
        var results: [MASOutdatedAppInfo] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = line.firstIndex(of: " ") else { continue }
            let idPart = String(line[line.startIndex..<firstSpace])
            guard Int(idPart) != nil else { continue }
            let rest = String(line[line.index(after: firstSpace)...]).trimmingCharacters(in: .whitespaces)
            guard let parenOpen = rest.firstIndex(of: "("), let parenClose = rest.lastIndex(of: ")") else { continue }
            let name = String(rest[rest.startIndex..<parenOpen]).trimmingCharacters(in: .whitespaces)
            let versions = rest[rest.index(after: parenOpen)..<parenClose]
                .components(separatedBy: "->")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard versions.count == 2 else { continue }
            results.append(MASOutdatedAppInfo(id: idPart, name: name, installedVersion: versions[0], latestVersion: versions[1]))
        }
        return results
    }

    func upgradeMASApp(_ app: MASOutdatedAppInfo) {
        guard let masPath = Self.resolveMASPath() else { return }
        masUpdateStatus[app.id] = "Upgrading…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell(masPath, ["upgrade", app.id]).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self?.masUpdateStatus[app.id] = output.isEmpty ? "Upgraded." : String(output.suffix(400))
                self?.scanMASOutdated()
            }
        }
    }

    // MARK: Check for updates

    func checkAllForUpdates(completion: (() -> Void)? = nil) {
        guard !apps.isEmpty else { completion?(); return }
        isCheckingAll = true
        let group = DispatchGroup()
        for app in apps {
            group.enter()
            checkForUpdate(app) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            self?.isCheckingAll = false
            completion?()
        }
    }

    /// Scans + checks both sources, then kicks off installation/upgrade for
    /// everything found outdated: Sparkle apps still show their normal
    /// signature-verified confirmation flow per app; Homebrew/Cask packages
    /// upgrade immediately (same as their individual "Update" buttons).
    func updateEverything() {
        isUpdatingEverything = true
        let group = DispatchGroup()

        group.enter()
        scanInstalledApps { [weak self] in
            guard let self else { group.leave(); return }
            self.checkAllForUpdates {
                for app in self.apps {
                    if case .updateAvailable = self.results[app.id] {
                        self.installUpdate(for: app)
                    }
                }
                group.leave()
            }
        }

        if isHomebrewInstalled {
            group.enter()
            scanHomebrewPackages { [weak self] in
                guard let self else { group.leave(); return }
                for package in self.brewPackages where package.isOutdated {
                    self.upgradeBrewPackage(package)
                }
                group.leave()
            }
        }

        if isMASToolInstalled {
            group.enter()
            scanMASOutdated { [weak self] in
                guard let self else { group.leave(); return }
                for app in self.masOutdatedApps {
                    self.upgradeMASApp(app)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.isUpdatingEverything = false
        }
    }

    func checkForUpdate(_ app: InstalledAppInfo, completion: (() -> Void)? = nil) {
        guard let feedURL = app.feedURL else {
            results[app.id] = .noFeed
            completion?()
            return
        }
        let task = URLSession.shared.dataTask(with: feedURL) { [weak self] data, _, error in
            Task { @MainActor in
                guard let self else { completion?(); return }
                guard let data, error == nil else {
                    self.results[app.id] = .checkFailed(error?.localizedDescription ?? "Network error")
                    completion?()
                    return
                }
                guard let item = AppcastParser().parseLatestItem(data: data) else {
                    self.results[app.id] = .checkFailed("Could not parse the update feed.")
                    completion?()
                    return
                }
                let latestVersion = item.shortVersionString ?? item.version ?? ""
                if !latestVersion.isEmpty, VersionComparator.isNewer(latestVersion, than: app.currentVersion), let enclosureURL = item.enclosureURL {
                    self.results[app.id] = .updateAvailable(version: latestVersion, enclosureURL: enclosureURL, enclosureType: item.enclosureType ?? "", releaseNotes: item.description)
                } else {
                    self.results[app.id] = .upToDate
                }
                completion?()
            }
        }
        task.resume()
    }

    // MARK: Install

    func installUpdate(for app: InstalledAppInfo) {
        guard case let .updateAvailable(version, enclosureURL, _, _) = results[app.id] else { return }
        installStatus[app.id] = "Downloading…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let downloadedPath = try self.download(url: enclosureURL)
                let ext = (downloadedPath as NSString).pathExtension.lowercased()

                if ext == "pkg" {
                    Task { @MainActor in
                        // .pkg installers can run arbitrary postinstall
                        // scripts - hand off to Installer.app rather than
                        // scripting that ourselves; it manages its own
                        // privilege-escalation UI.
                        NSWorkspace.shared.open(URL(fileURLWithPath: downloadedPath))
                        self.installStatus[app.id] = "Opened in Installer - finish there."
                    }
                    return
                }

                let extractedAppPath: String
                if ext == "dmg" {
                    extractedAppPath = try self.extractFromDMG(downloadedPath)
                } else if ext == "zip" {
                    extractedAppPath = try self.extractFromZip(downloadedPath)
                } else {
                    throw UpdateError.unsupportedFormat(ext)
                }

                guard self.verifySignature(extractedAppPath) else {
                    throw UpdateError.signatureVerificationFailed
                }

                Task { @MainActor in
                    self.confirmAndReplace(app: app, newAppPath: extractedAppPath, newVersion: version)
                }
            } catch {
                Task { @MainActor in
                    self.installStatus[app.id] = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }

    nonisolated private func download(url: URL) throws -> String {
        let destination = NSTemporaryDirectory() + UUID().uuidString + "-" + url.lastPathComponent
        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
            defer { semaphore.signal() }
            if let error { resultError = error; return }
            guard let tempURL else { resultError = UpdateError.downloadFailed; return }
            do {
                try FileManager.default.moveItem(at: tempURL, to: URL(fileURLWithPath: destination))
            } catch {
                resultError = error
            }
        }
        task.resume()
        semaphore.wait()
        if let resultError { throw resultError }
        return destination
    }

    nonisolated private func extractFromDMG(_ dmgPath: String) throws -> String {
        let output = caffeineShell("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", dmgPath])
        guard let mountLine = output.split(separator: "\n").last(where: { $0.contains("/Volumes/") }),
              let range = mountLine.range(of: "/Volumes/") else {
            throw UpdateError.mountFailed
        }
        let mountPoint = String(mountLine[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
        defer { _ = caffeineShell("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]) }

        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mountPoint),
              let appFile = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.appNotFoundInPackage
        }
        let stagingPath = NSTemporaryDirectory() + UUID().uuidString + "-" + appFile
        try FileManager.default.copyItem(atPath: "\(mountPoint)/\(appFile)", toPath: stagingPath)
        return stagingPath
    }

    nonisolated private func extractFromZip(_ zipPath: String) throws -> String {
        let destDir = NSTemporaryDirectory() + UUID().uuidString
        try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        _ = caffeineShell("/usr/bin/ditto", ["-xk", zipPath, destDir])
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: destDir),
              let appFile = contents.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdateError.appNotFoundInPackage
        }
        return "\(destDir)/\(appFile)"
    }

    nonisolated private func verifySignature(_ appPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", appPath]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func confirmAndReplace(app: InstalledAppInfo, newAppPath: String, newVersion: String) {
        let alert = NSAlert()
        alert.messageText = "Install \(app.name) \(newVersion)?"
        alert.informativeText = "The installed version (\(app.currentVersion)) will be moved to the Trash and replaced. \(app.name) will be quit first if it's currently running."
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            installStatus[app.id] = "Cancelled."
            return
        }
        installStatus[app.id] = "Installing…"
        performReplace(app: app, newAppPath: newAppPath)
    }

    private func performReplace(app: InstalledAppInfo, newAppPath: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            running.terminate()
        }

        let installDir = (app.path as NSString).deletingLastPathComponent
        let writable = FileManager.default.isWritableFile(atPath: installDir)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            if writable {
                let semaphore = DispatchSemaphore(value: 0)
                var trashError: Error?
                Task { @MainActor in
                    NSWorkspace.shared.recycle([URL(fileURLWithPath: app.path)]) { _, error in
                        trashError = error
                        semaphore.signal()
                    }
                }
                semaphore.wait()
                if let trashError {
                    self.finish(app: app, message: "Failed to remove old version: \(trashError.localizedDescription)")
                    return
                }
                do {
                    try FileManager.default.copyItem(atPath: newAppPath, toPath: app.path)
                    self.finish(app: app, message: "Installed \(app.name). Relaunch to use the new version.")
                } catch {
                    self.finish(app: app, message: "Failed to install: \(error.localizedDescription)")
                }
            } else {
                // Needs elevated privileges - this shows the native macOS
                // admin password/Touch ID prompt, never a custom dialog of
                // ours, and the user can cancel it.
                let script = "do shell script \"rm -rf \(app.path.shellQuoted) && cp -R \(newAppPath.shellQuoted) \(app.path.shellQuoted)\" with administrator privileges"
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                (try? process.run())
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    self.finish(app: app, message: "Installed \(app.name). Relaunch to use the new version.")
                } else {
                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    self.finish(app: app, message: "Failed or cancelled: \(output.isEmpty ? "administrator authorization was not granted." : output)")
                }
            }
        }
    }

    nonisolated private func finish(app: InstalledAppInfo, message: String) {
        Task { @MainActor in
            self.installStatus[app.id] = message
            self.scanInstalledApps()
        }
    }
}

private extension String {
    /// Wraps a path in single quotes for safe use inside a shell command,
    /// escaping any embedded single quotes.
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
