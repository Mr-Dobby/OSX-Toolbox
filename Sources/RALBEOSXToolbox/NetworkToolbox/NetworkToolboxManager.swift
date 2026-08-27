import Foundation

/// Small collection of everyday network utilities, all shelling out to
/// standard macOS command-line tools.
@MainActor
final class NetworkToolboxManager: ObservableObject {
    static let shared = NetworkToolboxManager()

    @Published var host = ""
    @Published var port = "443"
    @Published var output = ""
    @Published var isBusy = false
    @Published var localIPs: [String] = []
    @Published var publicIP = ""
    @Published var wifiSSID = ""

    private init() { refreshLocalInfo() }

    func refreshLocalInfo() {
        localIPs = ipv4Addresses()
        wifiSSID = currentSSID() ?? "Not connected"
    }

    func ping() { runAsync("/sbin/ping", ["-c", "4", host]) }
    func dnsLookup() { runAsync("/usr/bin/host", [host]) }
    func portCheck() { runAsync("/usr/bin/nc", ["-z", "-G", "3", host, port]) }
    func flushDNS() {
        runAsync("/usr/bin/dscacheutil", ["-flushcache"]) { [weak self] in
            _ = caffeineShell("/usr/bin/killall", ["-HUP", "mDNSResponder"])
            self?.output += "\nDNS cache flushed."
        }
    }
    func toggleWifi(on: Bool) { runAsync("/usr/sbin/networksetup", ["-setairportpower", "en0", on ? "on" : "off"]) }

    func fetchPublicIP() {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = caffeineShell("/usr/bin/curl", ["-s", "-m", "5", "https://api.ipify.org"]).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                self?.publicIP = result.isEmpty ? "Unavailable (offline or blocked)" : result
                self?.isBusy = false
            }
        }
    }

    private func runAsync(_ path: String, _ args: [String], then: (() -> Void)? = nil) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = caffeineShell(path, args)
            Task { @MainActor in
                self?.output = result.isEmpty ? "(no output)" : result
                self?.isBusy = false
                then?()
            }
        }
    }
}
