import SwiftUI

struct NetworkToolboxView: View {
    @ObservedObject var manager: NetworkToolboxManager

    var body: some View {
        Form {
            Section("Local Info") {
                LabeledContent("WiFi Network", value: manager.wifiSSID)
                LabeledContent("Local IPs", value: manager.localIPs.joined(separator: ", "))
                HStack {
                    LabeledContent("Public IP", value: manager.publicIP)
                    Button("Fetch") { manager.fetchPublicIP() }
                }
                Button("Refresh Local Info") { manager.refreshLocalInfo() }
            }

            Section("Host Tools") {
                TextField("Host or IP", text: $manager.host)
                TextField("Port", text: $manager.port).frame(width: 100)
                HStack {
                    Button("Ping") { manager.ping() }.disabled(manager.host.isEmpty)
                    Button("DNS Lookup") { manager.dnsLookup() }.disabled(manager.host.isEmpty)
                    Button("Port Check") { manager.portCheck() }.disabled(manager.host.isEmpty)
                }
            }

            Section("System") {
                HStack {
                    Button("WiFi On") { manager.toggleWifi(on: true) }
                    Button("WiFi Off") { manager.toggleWifi(on: false) }
                    Button("Flush DNS Cache") { manager.flushDNS() }
                }
            }

            Section("Output") {
                if manager.isBusy { ProgressView() }
                ScrollView {
                    Text(manager.output)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
