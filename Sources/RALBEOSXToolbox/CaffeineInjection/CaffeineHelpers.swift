import AppKit
import IOKit
import IOKit.ps
import CoreWLAN
import CoreAudio

// Free-function system probes used by the Caffeine Injection trigger engine.
// Ported from the original CaffeineInjectionInstaller.command script.

func caffeineShell(_ launchPath: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: launchPath)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = Pipe()
    do {
        try p.run()
    } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func ipv4Addresses() -> [String] {
    var addresses: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
    var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let current = ptr {
        let flags = Int32(current.pointee.ifa_flags)
        let addr = current.pointee.ifa_addr.pointee
        if (flags & (IFF_UP | IFF_RUNNING)) != 0, addr.sa_family == UInt8(AF_INET) {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            addresses.append(String(cString: hostname))
        }
        ptr = current.pointee.ifa_next
    }
    freeifaddrs(ifaddr)
    return addresses
}

func ipv6Addresses() -> [String] {
    var addresses: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
    var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
    while let current = ptr {
        let flags = Int32(current.pointee.ifa_flags)
        let addr = current.pointee.ifa_addr.pointee
        if (flags & (IFF_UP | IFF_RUNNING)) != 0, addr.sa_family == UInt8(AF_INET6) {
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(current.pointee.ifa_addr, socklen_t(current.pointee.ifa_addr.pointee.sa_len),
                        &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            let address = String(cString: hostname)
            // Skip link-local (fe80::...%iface) addresses - not useful for the dashboard.
            if !address.hasPrefix("fe80") {
                addresses.append(address)
            }
        }
        ptr = current.pointee.ifa_next
    }
    freeifaddrs(ifaddr)
    return addresses
}

func vpnInterfaceActive() -> Bool {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return false }
    var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
    var found = false
    while let current = ptr {
        let name = String(cString: current.pointee.ifa_name)
        let addr = current.pointee.ifa_addr.pointee
        if (name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")), addr.sa_family == UInt8(AF_INET) {
            found = true
            break
        }
        ptr = current.pointee.ifa_next
    }
    freeifaddrs(ifaddr)
    return found
}

func usbDeviceCount() -> Int {
    var iterator: io_iterator_t = 0
    let matching = IOServiceMatching("IOUSBDevice")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return 0 }
    var count = 0
    var service = IOIteratorNext(iterator)
    while service != 0 {
        count += 1
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    IOObjectRelease(iterator)
    return count
}

func bluetoothConnectedDeviceNames() -> [String] {
    let out = caffeineShell("/usr/sbin/system_profiler", ["SPBluetoothDataType"])
    var names: [String] = []
    var lastName: String?
    for rawLine in out.components(separatedBy: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasSuffix(":") && !line.contains("Connected") && !line.contains("Address") {
            lastName = String(line.dropLast())
        }
        if line.hasPrefix("Connected: Yes"), let n = lastName {
            names.append(n)
        }
    }
    return names
}

func batteryInfo() -> (percent: Int, isCharging: Bool, acConnected: Bool) {
    guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
        return (100, true, true)
    }
    for source in sources {
        if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
            let percent = desc[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? true
            let powerState = desc[kIOPSPowerSourceStateKey as String] as? String
            let ac = powerState == kIOPSACPowerValue
            return (percent, charging, ac)
        }
    }
    return (100, true, true)
}

func currentSSID() -> String? {
    return CWWiFiClient.shared().interface()?.ssid()
}

func defaultOutputIsExternal() -> Bool {
    var deviceID = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
    guard status == noErr else { return false }

    var transportType = UInt32(0)
    var tSize = UInt32(MemoryLayout<UInt32>.size)
    var tAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyTransportType,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(deviceID, &tAddress, 0, nil, &tSize, &transportType)
    return transportType == kAudioDeviceTransportTypeBluetooth
        || transportType == kAudioDeviceTransportTypeUSB
        || transportType == kAudioDeviceTransportTypeAirPlay
        || transportType == kAudioDeviceTransportTypeHDMI
}

final class CPUUsageMonitor {
    private var previousInfo: processor_info_array_t?
    private var previousCount: mach_msg_type_number_t = 0

    func currentUsagePercent() -> Double {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount)
        guard result == KERN_SUCCESS, let info = infoArray else { return 0 }

        defer {
            if let previousInfo = previousInfo {
                vm_deallocate(mach_task_self_, vm_address_t(bitPattern: previousInfo), vm_size_t(Int(previousCount) * MemoryLayout<Int32>.size))
            }
            previousInfo = info
            previousCount = infoCount
        }

        guard let previousInfo = previousInfo else { return 0 }

        var totalUsage: Double = 0
        for i in 0..<Int(cpuCount) {
            let base = Int(CPU_STATE_MAX) * i
            let user = Double(info[base + Int(CPU_STATE_USER)] - previousInfo[base + Int(CPU_STATE_USER)])
            let system = Double(info[base + Int(CPU_STATE_SYSTEM)] - previousInfo[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(info[base + Int(CPU_STATE_NICE)] - previousInfo[base + Int(CPU_STATE_NICE)])
            let idle = Double(info[base + Int(CPU_STATE_IDLE)] - previousInfo[base + Int(CPU_STATE_IDLE)])
            let total = user + system + nice + idle
            if total > 0 { totalUsage += (user + system + nice) / total }
        }
        return cpuCount > 0 ? (totalUsage / Double(cpuCount)) * 100.0 : 0
    }
}

func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for byte in string.utf8.prefix(4) { result = (result << 8) | FourCharCode(byte) }
    return result
}
