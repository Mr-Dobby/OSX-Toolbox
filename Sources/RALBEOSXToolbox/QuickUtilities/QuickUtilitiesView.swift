import SwiftUI

struct QuickUtilitiesView: View {
    @ObservedObject var manager: QuickUtilitiesManager

    var body: some View {
        Form {
            Section("Battery") {
                LabeledContent("Charge", value: "\(manager.battery.percent)%")
                LabeledContent("Charging", value: manager.battery.isCharging ? "Yes" : "No")
                LabeledContent("AC Connected", value: manager.battery.acConnected ? "Yes" : "No")
            }

            Section("Displays") {
                ForEach(manager.displays, id: \.self) { Text($0) }
            }

            Section("Quick Actions") {
                Toggle("Microphone Muted", isOn: Binding(get: { manager.isMicMuted }, set: { _ in manager.toggleMicrophoneMute() }))
                Toggle("WiFi On", isOn: Binding(get: { manager.wifiOn }, set: { _ in manager.toggleWifi() }))
                Button("Eject All External Disks") { manager.ejectAllExternalDisks() }
                Button("Refresh") { manager.refresh() }
            }

            Section("Not Implemented") {
                Text("Focus Mode toggle and temperature/fan monitoring have no public macOS API and were intentionally left out rather than faked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
