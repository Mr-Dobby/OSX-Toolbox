import SwiftUI

/// No universal "install any app" API exists on macOS, so this screen offers
/// the three practical sources side by side: Homebrew, the Mac App Store
/// (via the third-party `mas` CLI), and a direct download URL.
///
/// Search results render inside a height-capped `List` (not a `Form`/`VStack`
/// that grows with content) - letting result counts change without resizing
/// this whole pane, which otherwise made the NavigationSplitView reflow its
/// sidebar every time a search ran.
struct AppInstallerView: View {
    @ObservedObject var manager: AppInstallerManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Install new apps from Homebrew, the Mac App Store, or a direct download link. Each source works differently since macOS has no single universal install API.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                homebrewSection
                masSection
                directURLSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { manager.refreshMASAccount() }
    }

    // MARK: Homebrew

    private var homebrewSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if manager.isHomebrewInstalled {
                    HStack {
                        TextField("Search Homebrew, e.g. \"firefox\"", text: $manager.brewQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { manager.searchBrew() }
                        Button("Search") { manager.searchBrew() }
                            .disabled(manager.brewQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        if manager.isSearchingBrew {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let error = manager.brewSearchError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    if !manager.brewResults.isEmpty {
                        List(manager.brewResults) { result in
                            HStack {
                                Text(result.name)
                                Text(result.isCask ? "cask" : "formula")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                brewStatusView(for: result)
                            }
                        }
                        .listStyle(.plain)
                        .frame(height: min(CGFloat(manager.brewResults.count) * 32 + 8, 260))
                    }
                } else {
                    Text("Homebrew isn't installed (checked /opt/homebrew and /usr/local). Install it from brew.sh to enable this source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(4)
        } label: {
            Label("Homebrew (Formulae & Casks)", systemImage: "shippingbox")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func brewStatusView(for result: BrewSearchResult) -> some View {
        switch manager.brewInstallStatus[result.id] {
        case .working(let message):
            ProgressView().controlSize(.small)
            Text(message).font(.caption).foregroundStyle(.secondary)
        case .succeeded(let message):
            Text(message).font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
        case .idle, .none:
            Button("Install") { manager.installBrewResult(result) }
        }
    }

    // MARK: Mac App Store

    private var masSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if manager.isMASInstalled {
                    Text("The 'mas' CLI can no longer report App Store sign-in status - if a search or install below fails, make sure you're signed in from the App Store app itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        TextField("Search the App Store, e.g. \"xcode\"", text: $manager.masQuery)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { manager.searchMAS() }
                        Button("Search") { manager.searchMAS() }
                            .disabled(manager.masQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                        if manager.isSearchingMAS {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let error = manager.masSearchError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }

                    if !manager.masResults.isEmpty {
                        List(manager.masResults) { result in
                            HStack {
                                Text(result.name)
                                Spacer()
                                masStatusView(for: result)
                            }
                        }
                        .listStyle(.plain)
                        .frame(height: min(CGFloat(manager.masResults.count) * 32 + 8, 260))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("The 'mas' command-line tool isn't installed. There's no public Mac App Store install API, so this source relies on it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if manager.isHomebrewInstalled {
                            HStack {
                                Button {
                                    manager.installMASTool()
                                } label: {
                                    if manager.isInstallingMASTool {
                                        ProgressView().controlSize(.small)
                                        Text("Installing mas…")
                                    } else {
                                        Text("Install mas via Homebrew")
                                    }
                                }
                                .disabled(manager.isInstallingMASTool)
                            }
                            if let error = manager.masToolInstallError {
                                Text(error).font(.caption).foregroundStyle(.red).lineLimit(2)
                            }
                        } else {
                            Text("Homebrew is also required to install 'mas' automatically - install Homebrew first from brew.sh, or run \"brew install mas\" manually once you have it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(4)
        } label: {
            Label("Mac App Store (via mas)", systemImage: "bag")
                .font(.headline)
        }
    }

    @ViewBuilder
    private func masStatusView(for result: MASSearchResult) -> some View {
        switch manager.masInstallStatus[result.id] {
        case .working(let message):
            ProgressView().controlSize(.small)
            Text(message).font(.caption).foregroundStyle(.secondary)
        case .succeeded(let message):
            Text(message).font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(1)
        case .idle, .none:
            Button("Install") { manager.installMASResult(result) }
        }
    }

    // MARK: Direct download URL

    private var directURLSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Text("For apps distributed as a direct download. The file is downloaded, code-signature verified, and installed to /Applications - .pkg installers are handed off to Installer.app instead.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField("https://example.com/App.dmg", text: $manager.directURLString)
                        .textFieldStyle(.roundedBorder)
                    Button("Download & Install") { manager.installFromDirectURL() }
                        .disabled(manager.directURLString.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                directStatusView
            }
            .padding(4)
        } label: {
            Label("Direct Download URL (.dmg / .zip / .pkg)", systemImage: "arrow.down.circle")
                .font(.headline)
        }
    }

    @ViewBuilder
    private var directStatusView: some View {
        switch manager.directInstallStatus {
        case .idle:
            EmptyView()
        case .working(let message):
            HStack { ProgressView().controlSize(.small); Text(message) }
        case .succeeded(let message):
            Text(message).foregroundStyle(.green)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }
}

