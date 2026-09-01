import AppKit
import CoreLocation

enum CaffeineSessionMode: Equatable {
    case off
    case indefinite
    case timed(until: Date)
    case whileFile(URL)
    case whileApp(String)
}

/// Owns the "keep awake" state, all trigger evaluation, and the preferences
/// that used to live in the standalone CaffeineInjectionInstaller.command
/// script. Exposed as an ObservableObject so the unified SwiftUI menu bar can
/// bind directly to it (Toggle/Button), replacing the original NSMenu.
@MainActor
final class CaffeineInjectionManager: NSObject, ObservableObject {
    static let shared = CaffeineInjectionManager()

    private let d = UserDefaults.standard
    private let engine = AwakeEngine()
    private let cpuMonitor = CPUUsageMonitor()
    private let locationManager = CLLocationManager()

    @Published var sessionMode: CaffeineSessionMode = .off
    @Published var manualActive = false
    @Published var triggerActive = false

    @Published var allowDisplaySleep = false { didSet { d.set(allowDisplaySleep, forKey: "ci.allowDisplaySleep"); updateAwakeState() } }
    @Published var driveAlive = false { didSet { d.set(driveAlive, forKey: "ci.driveAlive"); updateAwakeState() } }
    @Published var allowScreenSaver = false { didSet { d.set(allowScreenSaver, forKey: "ci.allowScreenSaver") } }
    @Published var screenSaverIdleMinutes: Double = 10 { didSet { d.set(screenSaverIdleMinutes, forKey: "ci.screenSaverIdleMinutes") } }
    @Published var showRemainingTime = true { didSet { d.set(showRemainingTime, forKey: "ci.showRemainingTime") } }
    @Published var use24Hour = false { didSet { d.set(use24Hour, forKey: "ci.use24Hour") } }
    @Published var autoEndOnLowBattery = false { didSet { d.set(autoEndOnLowBattery, forKey: "ci.autoEndOnLowBattery") } }
    @Published var lowBatteryThreshold = 10 { didSet { d.set(lowBatteryThreshold, forKey: "ci.lowBatteryThreshold") } }
    @Published var activeIcon = "☕" { didSet { d.set(activeIcon, forKey: "ci.activeIcon") } }
    @Published var inactiveIcon = "🫗" { didSet { d.set(inactiveIcon, forKey: "ci.inactiveIcon") } }
    @Published var hotKeyString = "option+shift+c" { didSet { d.set(hotKeyString, forKey: "ci.hotKeyString"); installHotKey() } }

    @Published var triggerExternalDisplay = false { didSet { d.set(triggerExternalDisplay, forKey: "ci.t.display") } }
    @Published var triggerUSB = false { didSet { d.set(triggerUSB, forKey: "ci.t.usb"); if triggerUSB { usbBaselineCount = usbDeviceCount() } } }
    @Published var triggerBluetooth = false { didSet { d.set(triggerBluetooth, forKey: "ci.t.bt") } }
    @Published var triggerAppRunning = false { didSet { d.set(triggerAppRunning, forKey: "ci.t.app") } }
    @Published var triggerAppFrontmost = false { didSet { d.set(triggerAppFrontmost, forKey: "ci.t.appFront") } }
    @Published var triggerBattery = false { didSet { d.set(triggerBattery, forKey: "ci.t.battery") } }
    @Published var triggerAC = false { didSet { d.set(triggerAC, forKey: "ci.t.ac") } }
    @Published var triggerIP = false { didSet { d.set(triggerIP, forKey: "ci.t.ip") } }
    @Published var triggerWifi = false { didSet { d.set(triggerWifi, forKey: "ci.t.wifi") } }
    @Published var triggerVPN = false { didSet { d.set(triggerVPN, forKey: "ci.t.vpn") } }
    @Published var triggerAudio = false { didSet { d.set(triggerAudio, forKey: "ci.t.audio") } }
    @Published var triggerVolume = false { didSet { d.set(triggerVolume, forKey: "ci.t.volume") } }
    @Published var triggerCPU = false { didSet { d.set(triggerCPU, forKey: "ci.t.cpu") } }

    @Published var appBundleName = "" { didSet { d.set(appBundleName, forKey: "ci.cfg.appName") } }
    @Published var appFrontName = "" { didSet { d.set(appFrontName, forKey: "ci.cfg.appFrontName") } }
    @Published var batteryThresholdPercent = 50 { didSet { d.set(batteryThresholdPercent, forKey: "ci.cfg.batteryPct") } }
    @Published var targetIP = "" { didSet { d.set(targetIP, forKey: "ci.cfg.ip") } }
    @Published var targetSSID = "" { didSet { d.set(targetSSID, forKey: "ci.cfg.ssid") } }
    @Published var targetVolumeName = "" { didSet { d.set(targetVolumeName, forKey: "ci.cfg.volume") } }
    @Published var cpuThresholdPercent = 80 { didSet { d.set(cpuThresholdPercent, forKey: "ci.cfg.cpuPct") } }

    private var usbBaselineCount = 0
    private var heartbeat: Timer?
    private var tickTimer: Timer?
    private var hotKeyMonitor: Any?
    private var hotKeyLocalMonitor: Any?
    private var didStart = false

    private override init() {
        super.init()
        loadPrefs()
    }

    private func loadPrefs() {
        allowDisplaySleep = d.bool(forKey: "ci.allowDisplaySleep")
        driveAlive = d.bool(forKey: "ci.driveAlive")
        allowScreenSaver = d.bool(forKey: "ci.allowScreenSaver")
        screenSaverIdleMinutes = d.double(forKey: "ci.screenSaverIdleMinutes") == 0 ? 10 : d.double(forKey: "ci.screenSaverIdleMinutes")
        showRemainingTime = d.object(forKey: "ci.showRemainingTime") == nil ? true : d.bool(forKey: "ci.showRemainingTime")
        use24Hour = d.bool(forKey: "ci.use24Hour")
        autoEndOnLowBattery = d.bool(forKey: "ci.autoEndOnLowBattery")
        lowBatteryThreshold = d.object(forKey: "ci.lowBatteryThreshold") == nil ? 10 : d.integer(forKey: "ci.lowBatteryThreshold")
        activeIcon = d.string(forKey: "ci.activeIcon") ?? "☕"
        inactiveIcon = d.string(forKey: "ci.inactiveIcon") ?? "🫗"
        hotKeyString = d.string(forKey: "ci.hotKeyString") ?? "option+shift+c"

        triggerExternalDisplay = d.bool(forKey: "ci.t.display")
        triggerUSB = d.bool(forKey: "ci.t.usb")
        triggerBluetooth = d.bool(forKey: "ci.t.bt")
        triggerAppRunning = d.bool(forKey: "ci.t.app")
        triggerAppFrontmost = d.bool(forKey: "ci.t.appFront")
        triggerBattery = d.bool(forKey: "ci.t.battery")
        triggerAC = d.bool(forKey: "ci.t.ac")
        triggerIP = d.bool(forKey: "ci.t.ip")
        triggerWifi = d.bool(forKey: "ci.t.wifi")
        triggerVPN = d.bool(forKey: "ci.t.vpn")
        triggerAudio = d.bool(forKey: "ci.t.audio")
        triggerVolume = d.bool(forKey: "ci.t.volume")
        triggerCPU = d.bool(forKey: "ci.t.cpu")

        appBundleName = d.string(forKey: "ci.cfg.appName") ?? ""
        appFrontName = d.string(forKey: "ci.cfg.appFrontName") ?? ""
        batteryThresholdPercent = d.object(forKey: "ci.cfg.batteryPct") == nil ? 50 : d.integer(forKey: "ci.cfg.batteryPct")
        targetIP = d.string(forKey: "ci.cfg.ip") ?? ""
        targetSSID = d.string(forKey: "ci.cfg.ssid") ?? ""
        targetVolumeName = d.string(forKey: "ci.cfg.volume") ?? ""
        cpuThresholdPercent = d.object(forKey: "ci.cfg.cpuPct") == nil ? 80 : d.integer(forKey: "ci.cfg.cpuPct")
    }

    /// Starts the trigger-evaluation/tick timers and the AppleScript/hotkey
    /// handlers. Safe to call multiple times.
    func start() {
        guard !didStart else { return }
        didStart = true

        if #available(macOS 11.0, *) {
            locationManager.requestWhenInUseAuthorization()
        }

        heartbeat = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateTriggers() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(heartbeat!, forMode: .common)
        RunLoop.main.add(tickTimer!, forMode: .common)

        registerAppleEvents()
        installHotKey()
    }

    /// Releases every resource owned by Caffeine Injection before the app
    /// exits, including its child `/usr/bin/caffeinate` process.
    func stop() {
        heartbeat?.invalidate()
        heartbeat = nil
        tickTimer?.invalidate()
        tickTimer = nil
        if let monitor = hotKeyMonitor { NSEvent.removeMonitor(monitor) }
        hotKeyMonitor = nil
        if let monitor = hotKeyLocalMonitor { NSEvent.removeMonitor(monitor) }
        hotKeyLocalMonitor = nil
        engine.stop()
        didStart = false
    }

    // MARK: Status text

    func statusTitle() -> String {
        switch sessionMode {
        case .off:
            return triggerActive ? "Awake (trigger active)" : "Idle"
        case .indefinite:
            return "Awake indefinitely"
        case .timed(let until):
            return "Awake until \(formatTime(until))"
        case .whileFile:
            return "Awake while file downloads"
        case .whileApp(let name):
            return "Awake while \(name) is running"
        }
    }

    func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = use24Hour ? "HH:mm" : "h:mm a"
        return f.string(from: date)
    }

    var menuBarIcon: String {
        (manualActive || triggerActive) ? activeIcon : inactiveIcon
    }

    func triggerLabel(_ base: String, _ enabled: Bool, _ config: String) -> String {
        let mark = enabled ? "✓ " : ""
        return config.isEmpty ? "\(mark)\(base)…" : "\(mark)\(base) (\(config))…"
    }

    // MARK: Manual session controls

    func toggleIndefinite() {
        if manualActive { endManualSession() } else { startSession(.indefinite) }
    }

    func startSession(_ mode: CaffeineSessionMode) {
        sessionMode = mode
        manualActive = true
        updateAwakeState()
    }

    func endManualSession() {
        sessionMode = .off
        manualActive = false
        updateAwakeState()
    }

    func startTimed(minutes: Double) { startSession(.timed(until: Date().addingTimeInterval(minutes * 60))) }

    func promptCustomDuration() {
        guard let minutes = promptForText("Custom Duration", "Minutes to keep awake:", "60"), let m = Double(minutes) else { return }
        startSession(.timed(until: Date().addingTimeInterval(m * 60)))
    }

    func promptUntilTime() {
        guard let value = promptForText("Until a Specified Time", "Enter time (HH:mm, 24-hour):", "23:00") else { return }
        let parts = value.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = h
        comps.minute = m
        guard var target = Calendar.current.date(from: comps) else { return }
        if target < Date() { target = Calendar.current.date(byAdding: .day, value: 1, to: target)! }
        startSession(.timed(until: target))
    }

    func promptWhileFile() {
        let panel = NSOpenPanel()
        panel.prompt = "Watch"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            startSession(.whileFile(url))
        }
    }

    func promptWhileApp() {
        guard let name = promptForText("While an App Is Running", "App name (as shown in Activity Monitor):", "") else { return }
        startSession(.whileApp(name))
    }

    // MARK: Trigger configuration prompts

    func promptTriggerApp() {
        guard let name = promptForText("App Running Trigger", "App name:", appBundleName) else { return }
        appBundleName = name
        triggerAppRunning = !name.isEmpty
    }

    func promptTriggerAppFront() {
        guard let name = promptForText("App Running & Frontmost Trigger", "App name:", appFrontName) else { return }
        appFrontName = name
        triggerAppFrontmost = !name.isEmpty
    }

    func promptTriggerBattery() {
        guard let value = promptForText("Battery Trigger", "Keep awake while charging or battery above %:", "\(batteryThresholdPercent)"), let pct = Int(value) else { return }
        batteryThresholdPercent = pct
        triggerBattery = true
    }

    func promptTriggerIP() {
        guard let ip = promptForText("IP Address Trigger", "Keep awake while this IP is active:", targetIP) else { return }
        targetIP = ip
        triggerIP = !ip.isEmpty
    }

    func promptTriggerWifi() {
        guard let ssid = promptForText("WiFi Network Trigger", "Keep awake while connected to this SSID:", targetSSID) else { return }
        targetSSID = ssid
        triggerWifi = !ssid.isEmpty
    }

    func promptTriggerVolume() {
        guard let vol = promptForText("Volume Mounted Trigger", "Keep awake while this volume is mounted:", targetVolumeName) else { return }
        targetVolumeName = vol
        triggerVolume = !vol.isEmpty
    }

    func promptTriggerCPU() {
        guard let value = promptForText("CPU Utilization Trigger", "Keep awake while CPU usage is above %:", "\(cpuThresholdPercent)"), let pct = Int(value) else { return }
        cpuThresholdPercent = pct
        triggerCPU = true
    }

    func promptScreenSaver() {
        if allowScreenSaver {
            allowScreenSaver = false
        } else {
            guard let value = promptForText("Screen Saver", "Allow screen saver after minutes of inactivity:", "\(Int(screenSaverIdleMinutes))"), let m = Double(value) else { return }
            screenSaverIdleMinutes = m
            allowScreenSaver = true
        }
    }

    func promptLowBattery() {
        if autoEndOnLowBattery {
            autoEndOnLowBattery = false
        } else {
            guard let value = promptForText("Auto-End on Low Battery", "End session when battery drops below %:", "\(lowBatteryThreshold)"), let pct = Int(value) else { return }
            lowBatteryThreshold = pct
            autoEndOnLowBattery = true
        }
    }

    func setIcons(active: String, inactive: String) {
        activeIcon = active
        inactiveIcon = inactive
    }

    func promptCustomIcons() {
        guard let active = promptForText("Custom Icon", "Active icon (emoji/text):", activeIcon) else { return }
        guard let inactive = promptForText("Custom Icon", "Inactive icon (emoji/text):", inactiveIcon) else { return }
        setIcons(active: active, inactive: inactive)
    }

    func promptHotKey() {
        guard let combo = promptForText("Hot Key", "Format: option+shift+c (modifiers: cmd, option, shift, ctrl):", hotKeyString) else { return }
        hotKeyString = combo
    }

    // MARK: Prompt helper

    private func promptForText(_ title: String, _ message: String, _ defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    // MARK: Ticking / state evaluation

    private func tick() {
        checkScreenSaverIdle()

        if manualActive {
            switch sessionMode {
            case .timed(let until):
                if Date() >= until { endManualSession(); return }
            case .whileFile(let url):
                if !FileManager.default.fileExists(atPath: url.path) { endManualSession(); return }
            case .whileApp(let name):
                let running = NSWorkspace.shared.runningApplications.contains { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }
                if !running { endManualSession(); return }
            default: break
            }

            if autoEndOnLowBattery {
                let battery = batteryInfo()
                if !battery.isCharging && battery.percent <= lowBatteryThreshold {
                    endManualSession()
                    return
                }
            }
        }
    }

    private func checkScreenSaverIdle() {
        guard allowScreenSaver, manualActive || triggerActive else { return }
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .init(rawValue: ~0)!)
        if idleSeconds >= screenSaverIdleMinutes * 60 {
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: ["-a", "ScreenSaverEngine"])
        }
    }

    private func evaluateTriggers() {
        var active = false

        if triggerExternalDisplay, NSScreen.screens.count > 1 { active = true }
        if triggerUSB, usbDeviceCount() > usbBaselineCount { active = true }
        if triggerBluetooth, !bluetoothConnectedDeviceNames().isEmpty { active = true }
        if triggerAppRunning, !appBundleName.isEmpty {
            if NSWorkspace.shared.runningApplications.contains(where: { $0.localizedName?.caseInsensitiveCompare(appBundleName) == .orderedSame }) {
                active = true
            }
        }
        if triggerAppFrontmost, !appFrontName.isEmpty {
            if NSWorkspace.shared.frontmostApplication?.localizedName?.caseInsensitiveCompare(appFrontName) == .orderedSame {
                active = true
            }
        }
        if triggerBattery {
            let battery = batteryInfo()
            if battery.isCharging || battery.percent >= batteryThresholdPercent { active = true }
        }
        if triggerAC, batteryInfo().acConnected { active = true }
        if triggerIP, !targetIP.isEmpty, ipv4Addresses().contains(targetIP) { active = true }
        if triggerWifi, !targetSSID.isEmpty, let ssid = currentSSID(), ssid.caseInsensitiveCompare(targetSSID) == .orderedSame { active = true }
        if triggerVPN, vpnInterfaceActive() { active = true }
        if triggerAudio, defaultOutputIsExternal() { active = true }
        if triggerVolume, !targetVolumeName.isEmpty, FileManager.default.fileExists(atPath: "/Volumes/\(targetVolumeName)") { active = true }
        if triggerCPU, cpuMonitor.currentUsagePercent() >= Double(cpuThresholdPercent) { active = true }

        if active != triggerActive {
            triggerActive = active
            updateAwakeState()
        }
    }

    private func updateAwakeState() {
        engine.setEngaged(manualActive || triggerActive, allowDisplaySleep: allowDisplaySleep, driveAlive: driveAlive)
    }

    // MARK: Hot key

    private func installHotKey() {
        if let m = hotKeyMonitor { NSEvent.removeMonitor(m) }
        if let m = hotKeyLocalMonitor { NSEvent.removeMonitor(m) }

        let combo = hotKeyString.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyChar = combo.last, let code = Self.keyCodeMap[keyChar] else { return }
        var mods: NSEvent.ModifierFlags = []
        if combo.contains("cmd") || combo.contains("command") { mods.insert(.command) }
        if combo.contains("option") || combo.contains("alt") { mods.insert(.option) }
        if combo.contains("shift") { mods.insert(.shift) }
        if combo.contains("ctrl") || combo.contains("control") { mods.insert(.control) }

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == code, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == mods else { return }
            Task { @MainActor in self?.toggleIndefinite() }
        }
        hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { handler($0) }
        hotKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in handler(event); return event }
    }

    private static let keyCodeMap: [String: UInt16] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
        "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
        "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]

    // MARK: AppleScript (Apple Event) support - custom event class "cAFF" with IDs: strt / stop / driv

    private func registerAppleEvents() {
        let manager = NSAppleEventManager.shared()
        let eventClass: AEEventClass = fourCharCode("cAFF")
        manager.setEventHandler(self, andSelector: #selector(handleAppleEvent(_:withReplyEvent:)), forEventClass: eventClass, andEventID: fourCharCode("strt"))
        manager.setEventHandler(self, andSelector: #selector(handleAppleEvent(_:withReplyEvent:)), forEventClass: eventClass, andEventID: fourCharCode("stop"))
        manager.setEventHandler(self, andSelector: #selector(handleAppleEvent(_:withReplyEvent:)), forEventClass: eventClass, andEventID: fourCharCode("driv"))
    }

    @objc private func handleAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        switch event.eventID {
        case fourCharCode("strt"): startSession(.indefinite)
        case fourCharCode("stop"): endManualSession()
        case fourCharCode("driv"): driveAlive.toggle()
        default: break
        }
    }
}
