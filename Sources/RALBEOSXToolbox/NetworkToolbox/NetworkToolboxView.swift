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
                    Button("Traceroute") { manager.traceroute() }.disabled(manager.host.isEmpty)
                }
            }

            Section("Network Discovery") {
                Button("Discover Devices on Local LAN") { manager.discoverLocalNetworkDevices() }
                    .disabled(manager.isBusy)
                Text("Actively checks the connected private IPv4 /24 network using a single ping per address. Devices that block ping or are asleep may not appear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Authorized Security Scans") {
                Button("Scan Common TCP Ports") { manager.scanCommonTCPPorts() }
                    .disabled(manager.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
                HStack {
                    TextField("Port range", text: $manager.portRange)
                        .frame(width: 180)
                    Button("Scan TCP Range") { manager.scanCustomTCPPortRange() }
                        .disabled(manager.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
                }
                HStack {
                    Button("Scan Common UDP Ports") { manager.scanCommonUDPPorts() }
                        .disabled(manager.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
                }
                HStack {
                    TextField("UDP port range", text: $manager.udpPortRange)
                        .frame(width: 180)
                    Button("Scan UDP Range") { manager.scanCustomUDPPortRange() }
                        .disabled(manager.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || manager.isBusy)
                }
                Text("Built into RALBE OSX Toolbox. TCP reports confirmed open ports. UDP reports open-or-filtered candidates because UDP has no connection handshake. Custom ranges are inclusive and support up to 1,024 ports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Only scan systems and networks you own or have explicit permission to assess.")
                    .font(.caption)
                    .foregroundStyle(.orange)
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
