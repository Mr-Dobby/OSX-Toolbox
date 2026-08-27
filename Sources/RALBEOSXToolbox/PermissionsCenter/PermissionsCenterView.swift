import SwiftUI

struct PermissionsCenterView: View {
    @ObservedObject var manager: PermissionsCenterManager

    var body: some View {
        Form {
            Section {
                Button("Request All Permissions") { manager.requestAll() }
                    .buttonStyle(.borderedProminent)
                Button("Refresh Status") { manager.refresh() }
                Text("Used across Autoclicker, Caffeine Injection, App Cleaner, Permissions Inspector, Window Manager, and Startup & Login Manager.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Accessibility") {
                statusRow("Accessibility", granted: manager.accessibilityTrusted, detail: "Needed for Autoclicker's synthetic key/mouse events, Window Manager, and the Caffeine Injection hotkey.")
                HStack {
                    Button("Request") { manager.requestAccessibility() }
                    Button("Open Settings…") { manager.openAccessibilitySettings() }
                }
            }

            Section("Input Monitoring") {
                Text("No public API to check this status. Needed for Autoclicker's and Caffeine Injection's global keyboard shortcuts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings…") { manager.openInputMonitoringSettings() }
            }

            Section("Full Disk Access") {
                statusRow("Full Disk Access", granted: manager.fullDiskAccessGranted, detail: "Needed for App Cleaner and the Permissions Inspector.")
                HStack {
                    Button("Request") { manager.requestFullDiskAccess() }
                    Button("Open Settings…") { manager.openFullDiskAccessSettings() }
                }
            }

            Section("Location Services") {
                statusRow("Location Services", granted: manager.locationStatus == .authorizedAlways, detail: "Needed to detect the current WiFi network name for Caffeine Injection's WiFi trigger.")
                Text(PermissionsCenterManager.locationStatusDescription(manager.locationStatus))
                    .font(.caption)
                HStack {
                    Button("Request") { manager.requestLocation() }
                }
            }

            Section("Automation (System Events)") {
                Text("No public API to check this status. Needed by the Startup & Login Manager to list/remove Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Request") { manager.requestAutomation() }
                    Button("Open Settings…") { manager.openAutomationSettings() }
                }
            }

            Section("Not Applicable") {
                Text("Bluetooth device detection uses `system_profiler`, not the Bluetooth framework, so no TCC prompt applies. Screenshot capture and screen recording are performed by the system `screencapture` tool, which carries its own Screen Recording permission separate from this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { manager.refresh() }
    }

    private func statusRow(_ title: String, granted: Bool, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(granted ? .green : .red)
                Text(title)
                Spacer()
                Text(granted ? "Granted" : "Not Granted")
                    .foregroundStyle(granted ? .green : .red)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }
}
