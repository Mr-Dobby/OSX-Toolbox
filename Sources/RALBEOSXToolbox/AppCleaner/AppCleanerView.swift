import SwiftUI

/// In-window screen for the App Cleaner tool. The actual scan/removal UI is
/// a native AppKit window (NSTableView with checkboxes), so this view is
/// just the entry point + a status readout for Full Disk Access.
struct AppCleanerView: View {
    @ObservedObject var appCleaner: AppCleanerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Cleaner")
                .font(.title2)
                .bold()

            Text("Pick an installed app to scan for leftover caches, logs, preferences, and support files, then choose which ones to move to the Trash.")
                .foregroundStyle(.secondary)

            HStack {
                Image(systemName: appCleaner.hasFullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(appCleaner.hasFullDiskAccess ? .green : .orange)
                Text(appCleaner.hasFullDiskAccess ? "Full Disk Access granted" : "Full Disk Access not detected")
                Spacer()
                Button("Refresh") { appCleaner.refreshFullDiskAccess() }
                if !appCleaner.hasFullDiskAccess {
                    Button("Open Settings…") { SystemPermissions.promptFullDiskAccess() }
                }
            }
            .padding(10)
            .background((appCleaner.hasFullDiskAccess ? Color.green : Color.orange).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button("Choose an App to Clean…") {
                appCleaner.pickAndClean()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
