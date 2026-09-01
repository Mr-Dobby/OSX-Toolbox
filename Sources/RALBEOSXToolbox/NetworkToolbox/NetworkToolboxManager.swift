import Foundation
import Network

private enum UDPProbeResult {
    case openOrFiltered
    case closedOrUnreachable
}

/// Serializes the connection callback and timeout callback so each probe
/// reports exactly once. Its lock protects the non-Sendable callback.
private final class TCPProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let completion: (Bool) -> Void

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }

    func finish(open: Bool, connection: NWConnection) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        connection.cancel()
        completion(open)
    }
}

/// Serializes UDP connection callbacks. UDP has no handshake, so a lack of
/// an immediate error can only be reported as "open or filtered."
private final class UDPProbeCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let completion: (UDPProbeResult) -> Void

    init(completion: @escaping (UDPProbeResult) -> Void) {
        self.completion = completion
    }

    func finish(_ result: UDPProbeResult, connection: NWConnection) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        connection.cancel()
        completion(result)
    }
}

/// Small collection of everyday network utilities plus native, opt-in TCP
/// service discovery for systems the user is authorized to assess.
@MainActor
final class NetworkToolboxManager: ObservableObject {
    static let shared = NetworkToolboxManager()

    @Published var host = ""
    @Published var port = "443"
    @Published var portRange = "1..443"
    @Published var udpPortRange = "1..443"
    @Published var output = ""
    @Published var isBusy = false
    @Published var localIPs: [String] = []
    @Published var publicIP = ""
    @Published var wifiSSID = ""

    private init() {
        refreshLocalInfo()
    }

    func refreshLocalInfo() {
        localIPs = ipv4Addresses()
        wifiSSID = currentSSID() ?? "Not connected"
    }

    func ping() { runAsync("/sbin/ping", ["-c", "10", host]) }
    func dnsLookup() { runAsync("/usr/bin/host", [host]) }
    func portCheck() { runAsync("/usr/bin/nc", ["-z", "-G", "3", host, port]) }
    func traceroute() { runAsync("/usr/sbin/traceroute", ["-m", "12", "-w", "2", host]) }

    /// Actively discovers reachable devices on the current IPv4 /24 subnet.
    /// This avoids relying on the ARP cache, which is commonly empty or stale.
    func discoverLocalNetworkDevices() {
        guard let subnetPrefix = Self.localSubnetPrefix(from: localIPs) else {
            output = "Could not determine an active private IPv4 LAN. Connect to Wi-Fi or Ethernet, then refresh Local Info."
            return
        }
        isBusy = true
        output = "Discovering reachable devices on \(subnetPrefix).0/24…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let group = DispatchGroup()
            let concurrencyLimit = DispatchSemaphore(value: 32)
            let resultLock = NSLock()
            var devices: [String] = []

            for hostNumber in 1...254 {
                let address = "\(subnetPrefix).\(hostNumber)"
                concurrencyLimit.wait()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let reply = caffeineShell("/sbin/ping", ["-c", "1", "-W", "1000", "-q", address])
                    if reply.contains("1 packets received") || reply.contains("1 packet received") {
                        resultLock.lock()
                        devices.append(address)
                        resultLock.unlock()
                    }
                    concurrencyLimit.signal()
                    group.leave()
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                resultLock.lock()
                let sortedDevices = devices.sorted(by: Self.isIPv4AddressBefore)
                resultLock.unlock()
                let report = sortedDevices.isEmpty
                    ? "No devices replied to ICMP echo requests on \(subnetPrefix).0/24. Devices may block ping or be asleep."
                    : "Reachable devices on \(subnetPrefix).0/24 (\(sortedDevices.count)):\n" + sortedDevices.map { "• \($0)" }.joined(separator: "\n")
                Task { @MainActor in
                    self?.output = report
                    self?.isBusy = false
                }
            }
        }
    }

    /// Checks a bounded set of common TCP service ports without depending on an external scanner. A successful TCP connection means the port is open.
    func scanCommonTCPPorts() {
        scanTCPPorts([
            21, 22, 23, 25, 53, 80, 110, 111, 135, 139, 143,
            389, 443, 445, 465, 587, 636, 993, 995,
            1433, 1521, 2049, 2375, 2376, 3000, 3306, 3389,
            5000, 5432, 5900, 5985, 5986, 6379, 6443,
            8000, 8080, 8443, 8888, 9090, 9200, 27017
        ], label: "common TCP ports")
    }

    /// Scans an inclusive port range written as `start..end``
    func scanCustomTCPPortRange() {
        guard let ports = Self.validatedPortRange(from: portRange) else {
            output = "Enter a valid TCP port range such as 1..443. Ranges may contain up to 1,024 ports."
            return
        }
        scanTCPPorts(ports, label: "TCP ports \(ports.first!)..\(ports.last!)")
    }

    func scanCommonUDPPorts() {
        scanUDPPorts([
            53, 67, 68, 69, 123, 137, 138, 161, 162,
            389, 500, 514, 520, 1194, 1434, 1701,
            1900, 4500, 5353, 5355, 5683
        ], label: "common UDP ports")
    }

    func scanCustomUDPPortRange() {
        guard let ports = Self.validatedPortRange(from: udpPortRange) else {
            output = "Enter a valid UDP port range such as 1..33. Ranges may contain up to 1,024 ports."
            return
        }
        scanUDPPorts(ports, label: "UDP ports \(ports.first!)..\(ports.last!)")
    }

    private func scanTCPPorts(_ ports: [UInt16], label: String) {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !ports.isEmpty else { return }

        isBusy = true
        output = "Scanning \(label) on \(target)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let group = DispatchGroup()
            let concurrencyLimit = DispatchSemaphore(value: 32)
            let resultLock = NSLock()
            var openPorts: [UInt16] = []

            for port in ports {
                concurrencyLimit.wait()
                group.enter()
                Self.probeTCPPort(host: target, port: port) { isOpen in
                    if isOpen {
                        resultLock.lock()
                        openPorts.append(port)
                        resultLock.unlock()
                    }
                    concurrencyLimit.signal()
                    group.leave()
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                let report: String
                resultLock.lock()
                let sortedPorts = openPorts.sorted()
                resultLock.unlock()
                if sortedPorts.isEmpty {
                    report = "No open ports found while scanning \(label) on \(target)."
                } else {
                    report = "Open TCP ports on \(target):\n" + sortedPorts.map { "• \($0) (\(Self.serviceName(for: $0)))" }.joined(separator: "\n")
                }
                Task { @MainActor in
                    self?.output = report
                    self?.isBusy = false
                }
            }
        }
    }

    private func scanUDPPorts(_ ports: [UInt16], label: String) {
        let target = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty, !ports.isEmpty else { return }

        isBusy = true
        output = "Scanning \(label) on \(target)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let group = DispatchGroup()
            let concurrencyLimit = DispatchSemaphore(value: 32)
            let resultLock = NSLock()
            var candidates: [UInt16] = []

            for port in ports {
                concurrencyLimit.wait()
                group.enter()
                Self.probeUDPPort(host: target, port: port) { result in
                    if result == .openOrFiltered {
                        resultLock.lock()
                        candidates.append(port)
                        resultLock.unlock()
                    }
                    concurrencyLimit.signal()
                    group.leave()
                }
            }

            group.notify(queue: .global(qos: .userInitiated)) {
                resultLock.lock()
                let sortedCandidates = candidates.sorted()
                resultLock.unlock()
                let report = sortedCandidates.isEmpty
                    ? "No UDP ports were identified as open or filtered while scanning \(label) on \(target)."
                    : "UDP ports open or filtered on \(target):\n" + sortedCandidates.map { "• \($0) (\(Self.serviceName(for: $0)))" }.joined(separator: "\n") + "\n\nUDP has no connection handshake: no response cannot distinguish an open service from a firewall dropping traffic."
                Task { @MainActor in
                    self?.output = report
                    self?.isBusy = false
                }
            }
        }
    }

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

    nonisolated private static func probeTCPPort(host: String, port: UInt16, completion: @escaping (Bool) -> Void) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            completion(false)
            return
        }
        let queue = DispatchQueue(label: "RALBEOSXToolbox.TCPProbe.\(port)")
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .tcp)
        let probeCompletion = TCPProbeCompletion(completion: completion)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                probeCompletion.finish(open: true, connection: connection)
            case .failed, .cancelled:
                probeCompletion.finish(open: false, connection: connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) {
            probeCompletion.finish(open: false, connection: connection)
        }
    }

    nonisolated private static func probeUDPPort(host: String, port: UInt16, completion: @escaping (UDPProbeResult) -> Void) {
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            completion(.closedOrUnreachable)
            return
        }
        let queue = DispatchQueue(label: "RALBEOSXToolbox.UDPProbe.\(port)")
        let connection = NWConnection(host: NWEndpoint.Host(host), port: endpointPort, using: .udp)
        let probeCompletion = UDPProbeCompletion(completion: completion)

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                connection.send(content: Data([0]), completion: .contentProcessed { error in
                    if error != nil {
                        probeCompletion.finish(.closedOrUnreachable, connection: connection)
                    }
                })
            case .failed, .cancelled:
                probeCompletion.finish(.closedOrUnreachable, connection: connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 2) {
            probeCompletion.finish(.openOrFiltered, connection: connection)
        }
    }

    nonisolated private static func validatedPortRange(from rangeText: String) -> [UInt16]? {
        let parts = rangeText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "..")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let start = UInt16(parts[0]),
              let end = UInt16(parts[1]),
              start <= end,
              Int(end) - Int(start) < 1_024 else { return nil }
        return Array(start...end)
    }

    nonisolated private static func localSubnetPrefix(from addresses: [String]) -> String? {
        for address in addresses where !address.hasPrefix("127.") {
            let parts = address.split(separator: ".")
            guard parts.count == 4,
                  let first = Int(parts[0]),
                  let second = Int(parts[1]),
                  let third = Int(parts[2]),
                  first == 10 || (first == 192 && second == 168) || (first == 172 && (16...31).contains(second)) else { continue }
            return "\(first).\(second).\(third)"
        }
        return nil
    }

    nonisolated private static func isIPv4AddressBefore(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".").compactMap { Int($0) }
        let right = rhs.split(separator: ".").compactMap { Int($0) }
        for index in 0..<min(left.count, right.count) where left[index] != right[index] {
            return left[index] < right[index]
        }
        return left.count < right.count
    }

    nonisolated private static func serviceName(for port: UInt16) -> String {
        switch port {
            case 21: return "FTP"
            case 22: return "SSH"
            case 23: return "Telnet"
            case 25: return "SMTP"
            case 53: return "DNS"
            case 67: return "DHCP Server"
            case 68: return "DHCP Client"
            case 69: return "TFTP"
            case 80: return "HTTP"
            case 110: return "POP3"
            case 111: return "RPCbind"
            case 123: return "NTP"
            case 135: return "MS RPC"
            case 137: return "NetBIOS Name Service"
            case 138: return "NetBIOS Datagram"
            case 139: return "NetBIOS Session"
            case 143: return "IMAP"
            case 389: return "LDAP"
            case 443: return "HTTPS"
            case 445: return "SMB"
            case 465: return "SMTPS"
            case 500: return "IKE / IPsec"
            case 514: return "Syslog"
            case 520: return "RIP"
            case 587: return "SMTP Submission"
            case 636: return "LDAPS"
            case 993: return "IMAPS"
            case 995: return "POP3S"
            case 1194: return "OpenVPN"
            case 1433: return "Microsoft SQL Server"
            case 1434: return "SQL Server Browser"
            case 1521: return "Oracle Database"
            case 1701: return "L2TP"
            case 1900: return "SSDP / UPnP"
            case 2049: return "NFS"
            case 2375: return "Docker API"
            case 2376: return "Docker API (TLS)"
            case 3000: return "HTTP / Development"
            case 3306: return "MySQL"
            case 3389: return "RDP"
            case 4500: return "IPsec NAT-T"
            case 5000: return "HTTP / Development"
            case 5353: return "mDNS"
            case 5355: return "LLMNR"
            case 5432: return "PostgreSQL"
            case 5683: return "CoAP"
            case 5900: return "VNC"
            case 5985: return "WinRM"
            case 5986: return "WinRM (HTTPS)"
            case 6379: return "Redis"
            case 6443: return "Kubernetes API"
            case 8000: return "HTTP / Development"
            case 8080: return "HTTP Alternate"
            case 8443: return "HTTPS Alternate"
            case 8888: return "HTTP / Development"
            case 9090: return "HTTP / Admin"
            case 9200: return "Elasticsearch"
            case 27017: return "MongoDB"
            default: return "Unknown service"
        }
    }
}
