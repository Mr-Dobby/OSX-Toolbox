import AppKit

/// Gathers a point-in-time snapshot of device stats and serializes it as
/// JSON for the local web dashboard to poll. Cheap/fast-changing values
/// (CPU%, memory, uptime, network) are computed fresh every call; slower or
/// near-static values (battery health, disk list, machine/OS identity) are
/// cached for a while so a poll every 2s doesn't repeatedly shell out to
/// `system_profiler`/`ps` or hammer the public-IP service.
enum DeviceStatsSnapshot {
    private static let cpuMonitor = CPUUsageMonitor()

    private static var cachedPublicIP = "Fetching…"
    private static var lastPublicIPFetch = Date.distantPast

    private static var cachedBatteryHealth: (cycleCount: Int, condition: String) = (0, "Unknown")
    private static var lastBatteryHealthFetch = Date.distantPast

    private static var cachedDisks: [[String: Any]] = []
    private static var lastDiskFetch = Date.distantPast

    private static var cachedMachineInfo: [String: Any]?

    static func currentJSON() -> String {
        let cpu = cpuMonitor.currentUsagePercent()
        let mem = memoryUsage()
        let swap = swapUsage()
        let battery = batteryInfo()
        let batteryHealth = cachedBatteryHealthInfo()
        let runningAppsCount = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.count

        var dict: [String: Any] = machineInfo()
        dict["cpuPercent"] = cpu
        dict["loadAverage"] = loadAverage()
        dict["thermalState"] = thermalStateDescription()
        dict["memoryUsedGB"] = mem.usedGB
        dict["memoryTotalGB"] = mem.totalGB
        dict["swapUsedGB"] = swap.usedGB
        dict["swapTotalGB"] = swap.totalGB
        dict["disks"] = cachedDiskVolumes()
        dict["batteryPercent"] = battery.percent
        dict["batteryCharging"] = battery.isCharging
        dict["acConnected"] = battery.acConnected
        dict["batteryCycleCount"] = batteryHealth.cycleCount
        dict["batteryCondition"] = batteryHealth.condition
        dict["uptimeSeconds"] = ProcessInfo.processInfo.systemUptime
        dict["localIPs"] = ipv4Addresses()
        dict["localIPv6s"] = ipv6Addresses()
        dict["publicIP"] = publicIPCached()
        dict["wifiSSID"] = currentSSID() ?? "Not connected"
        dict["runningAppsCount"] = runningAppsCount
        dict["topCPUProcesses"] = topProcesses(byMemory: false, limit: 5)
        dict["topMemProcesses"] = topProcesses(byMemory: true, limit: 5)
        dict["timestamp"] = ISO8601DateFormatter().string(from: Date())

        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Machine/OS identity essentially never changes for a running process,
    /// so this is fetched once and reused for the lifetime of the app.
    private static func machineInfo() -> [String: Any] {
        if let cached = cachedMachineInfo { return cached }
        let info: [String: Any] = [
            "hostName": ProcessInfo.processInfo.hostName,
            "modelIdentifier": sysctlString("hw.model"),
            "cpuBrand": sysctlString("machdep.cpu.brand_string"),
            "cpuCoreCount": ProcessInfo.processInfo.processorCount,
            "activeCoreCount": ProcessInfo.processInfo.activeProcessorCount,
            "osVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        cachedMachineInfo = info
        return info
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "Unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return loads
    }

    private static func thermalStateDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Nominal"
        case .fair: return "Fair"
        case .serious: return "Serious"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    private static func publicIPCached() -> String {
        if Date().timeIntervalSince(lastPublicIPFetch) > 60 {
            lastPublicIPFetch = Date()
            let result = caffeineShell("/usr/bin/curl", ["-s", "-m", "3", "https://api.ipify.org"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !result.isEmpty { cachedPublicIP = result }
        }
        return cachedPublicIP
    }

    private static func cachedBatteryHealthInfo() -> (cycleCount: Int, condition: String) {
        if Date().timeIntervalSince(lastBatteryHealthFetch) > 60 {
            lastBatteryHealthFetch = Date()
            cachedBatteryHealth = fetchBatteryHealth()
        }
        return cachedBatteryHealth
    }

    private static func fetchBatteryHealth() -> (cycleCount: Int, condition: String) {
        let output = caffeineShell("/usr/sbin/system_profiler", ["SPPowerDataType"])
        var cycleCount = 0
        var condition = "Unknown"
        for rawLine in output.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Cycle Count:") {
                cycleCount = Int(line.replacingOccurrences(of: "Cycle Count:", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            } else if line.hasPrefix("Condition:") {
                condition = line.replacingOccurrences(of: "Condition:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        return (cycleCount, condition)
    }

    private static func cachedDiskVolumes() -> [[String: Any]] {
        if Date().timeIntervalSince(lastDiskFetch) > 30 {
            lastDiskFetch = Date()
            cachedDisks = fetchDiskVolumes()
        }
        return cachedDisks
    }

    private static func fetchDiskVolumes() -> [[String: Any]] {
        let fm = FileManager.default
        var paths = ["/"]
        if let volumes = try? fm.contentsOfDirectory(atPath: "/Volumes") {
            paths += volumes.map { "/Volumes/\($0)" }
        }
        var seenNames = Set<String>()
        var results: [[String: Any]] = []
        for path in paths {
            guard let attrs = try? fm.attributesOfFileSystem(forPath: path),
                  let total = attrs[.systemSize] as? NSNumber,
                  let free = attrs[.systemFreeSize] as? NSNumber,
                  total.int64Value > 0 else { continue }
            let name = path == "/" ? "Macintosh HD" : (path as NSString).lastPathComponent
            guard seenNames.insert(name).inserted else { continue }
            let totalGB = total.doubleValue / 1_073_741_824
            let freeGB = free.doubleValue / 1_073_741_824
            results.append(["name": name, "usedGB": totalGB - freeGB, "totalGB": totalGB])
        }
        return results
    }

    private static func memoryUsage() -> (usedGB: Double, totalGB: Double) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, total / 1_073_741_824) }
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.inactive_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        return (used / 1_073_741_824, total / 1_073_741_824)
    }

    private struct XswUsage {
        let total: UInt64
        let avail: UInt64
        let used: UInt64
        let pagesize: UInt32
        let encrypted: Int32
    }

    private static func swapUsage() -> (usedGB: Double, totalGB: Double) {
        var usage = XswUsage(total: 0, avail: 0, used: 0, pagesize: 0, encrypted: 0)
        var size = MemoryLayout<XswUsage>.size
        let result = withUnsafeMutablePointer(to: &usage) {
            sysctlbyname("vm.swapusage", $0, &size, nil, 0)
        }
        guard result == 0 else { return (0, 0) }
        return (Double(usage.used) / 1_073_741_824, Double(usage.total) / 1_073_741_824)
    }

    private static func topProcesses(byMemory: Bool, limit: Int) -> [[String: Any]] {
        let sortFlag = byMemory ? "-m" : "-r"
        let output = caffeineShell("/bin/ps", ["-Ao", "pid,pcpu,pmem,comm", sortFlag])
        var results: [[String: Any]] = []
        for line in output.split(separator: "\n").dropFirst() {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count >= 4, let cpu = Double(parts[1]), let mem = Double(parts[2]) else { continue }
            let name = (String(parts[3]) as NSString).lastPathComponent
            results.append(["name": name, "cpu": cpu, "mem": mem])
            if results.count >= limit { break }
        }
        return results
    }
}
