import Foundation

/// Free functions shared by any module that downloads and installs a
/// dmg/zip-packaged .app from a URL (currently AppInstallerManager's direct
/// URL source; AppUpdaterManager has its own private equivalents predating
/// this file and is left untouched). All are safe to call directly from a
/// background queue - none touch actor-isolated state.
enum PackageInstallError: LocalizedError {
    case downloadFailed
    case mountFailed
    case appNotFoundInPackage
    case signatureVerificationFailed
    case unsupportedFormat(String)

    var errorDescription: String? {
        switch self {
        case .downloadFailed: return "The file could not be downloaded."
        case .mountFailed: return "The downloaded disk image could not be mounted."
        case .appNotFoundInPackage: return "No .app bundle was found in the downloaded file."
        case .signatureVerificationFailed: return "The downloaded app failed code signature verification and was NOT installed."
        case .unsupportedFormat(let ext): return "Unsupported file format: .\(ext)"
        }
    }
}

func downloadPackageFile(url: URL) throws -> String {
    let destination = NSTemporaryDirectory() + UUID().uuidString + "-" + url.lastPathComponent
    let semaphore = DispatchSemaphore(value: 0)
    var resultError: Error?
    let task = URLSession.shared.downloadTask(with: url) { tempURL, _, error in
        defer { semaphore.signal() }
        if let error { resultError = error; return }
        guard let tempURL else { resultError = PackageInstallError.downloadFailed; return }
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

func extractAppFromDMG(_ dmgPath: String) throws -> String {
    let output = caffeineShell("/usr/bin/hdiutil", ["attach", "-nobrowse", "-noautoopen", dmgPath])
    guard let mountLine = output.split(separator: "\n").last(where: { $0.contains("/Volumes/") }),
          let range = mountLine.range(of: "/Volumes/") else {
        throw PackageInstallError.mountFailed
    }
    let mountPoint = String(mountLine[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
    defer { _ = caffeineShell("/usr/bin/hdiutil", ["detach", mountPoint, "-quiet"]) }

    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: mountPoint),
          let appFile = contents.first(where: { $0.hasSuffix(".app") }) else {
        throw PackageInstallError.appNotFoundInPackage
    }
    let stagingPath = NSTemporaryDirectory() + UUID().uuidString + "-" + appFile
    try FileManager.default.copyItem(atPath: "\(mountPoint)/\(appFile)", toPath: stagingPath)
    return stagingPath
}

func extractAppFromZip(_ zipPath: String) throws -> String {
    let destDir = NSTemporaryDirectory() + UUID().uuidString
    try FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)
    _ = caffeineShell("/usr/bin/ditto", ["-xk", zipPath, destDir])
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: destDir),
          let appFile = contents.first(where: { $0.hasSuffix(".app") }) else {
        throw PackageInstallError.appNotFoundInPackage
    }
    return "\(destDir)/\(appFile)"
}

func verifyAppCodesign(_ appPath: String) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    process.arguments = ["--verify", "--deep", "--strict", appPath]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return false }
    process.waitUntilExit()
    return process.terminationStatus == 0
}

extension String {
    /// Wraps a path in single quotes for safe use inside a shell command,
    /// escaping any embedded single quotes.
    var shellQuotedForInstall: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
