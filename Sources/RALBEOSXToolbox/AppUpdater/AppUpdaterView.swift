import SwiftUI

struct AppUpdaterView: View {
    @ObservedObject var manager: AppUpdaterManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("App Updater").font(.title2).bold()
                Spacer()
                Button("Scan Installed Apps") { manager.scanInstalledApps() }
                Button("Check All for Updates") { manager.checkAllForUpdates() }
                    .disabled(manager.apps.isEmpty || manager.isCheckingAll)
                Button("Scan Homebrew Packages") { manager.scanHomebrewPackages() }
                    .disabled(!manager.isHomebrewInstalled)
                Button("Check App Store Updates") { manager.scanMASOutdated() }
                    .disabled(!manager.isMASToolInstalled)
                Button("Update Everything") { manager.updateEverything() }
                    .buttonStyle(.borderedProminent)
                    .disabled(manager.isUpdatingEverything)
            }
            Text("Checks apps that publish a Sparkle update feed (common for indie Mac apps), plus anything installed via Homebrew/Cask or the Mac App Store (via the `mas` CLI - install it from the App Installer tab if missing). Downloaded Sparkle updates are code-signature verified before anything is replaced, and installing to a system-owned location will prompt for your admin password.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if manager.isScanning || manager.isCheckingAll || manager.isCheckingBrew || manager.isCheckingMAS || manager.isUpdatingEverything {
                ProgressView()
            }

            List {
                Section("Bundled Apps") {
                    ForEach(manager.apps) { app in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.name)
                                Text("Installed: \(app.currentVersion)\(app.isMacAppStore ? " · Mac App Store" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let status = manager.installStatus[app.id] {
                                    Text(status).font(.caption2).foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            statusView(for: app)
                        }
                    }
                }

                Section("Homebrew / Cask") {
                    if let error = manager.brewError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(manager.brewPackages) { package in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(package.displayName)
                                Text("Installed: \(package.installedVersion)\(package.isCask ? " · Cask" : " · Formula")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let status = manager.brewUpdateStatus[package.id] {
                                    Text(status).font(.caption2).foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            if package.isOutdated {
                                Button("Update to \(package.latestVersion)") { manager.upgradeBrewPackage(package) }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Text("Up to date").foregroundStyle(.green)
                            }
                        }
                    }
                }

                Section("Mac App Store") {
                    if let error = manager.masError {
                        Text(error).font(.caption).foregroundStyle(.orange)
                    } else if manager.masOutdatedApps.isEmpty {
                        Text("No pending Mac App Store updates found (or not checked yet).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(manager.masOutdatedApps) { app in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(app.name)
                                Text("Installed: \(app.installedVersion)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let status = manager.masUpdateStatus[app.id] {
                                    Text(status).font(.caption2).foregroundStyle(.blue)
                                }
                            }
                            Spacer()
                            Button("Update to \(app.latestVersion)") { manager.upgradeMASApp(app) }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if manager.apps.isEmpty { manager.scanInstalledApps() }
            if manager.brewPackages.isEmpty, manager.isHomebrewInstalled { manager.scanHomebrewPackages() }
            if manager.masOutdatedApps.isEmpty, manager.isMASToolInstalled { manager.scanMASOutdated() }
        }
    }

    @ViewBuilder
    private func statusView(for app: InstalledAppInfo) -> some View {
        switch manager.results[app.id] {
        case .updateAvailable(let version, _, _, _):
            Button("Update to \(version)") { manager.installUpdate(for: app) }
                .buttonStyle(.borderedProminent)
        case .upToDate:
            Text("Up to date").foregroundStyle(.green)
        case .checkFailed(let message):
            VStack(alignment: .trailing) {
                Text("Check failed").font(.caption).foregroundStyle(.orange)
                Button("Retry") { manager.checkForUpdate(app) }
            }
            .help(message)
        case .noFeed, nil:
            if app.isMacAppStore {
                Text("Via App Store").font(.caption).foregroundStyle(.secondary)
            } else if app.feedURL == nil {
                Text("No update feed").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Check") { manager.checkForUpdate(app) }
            }
        }
    }
}

