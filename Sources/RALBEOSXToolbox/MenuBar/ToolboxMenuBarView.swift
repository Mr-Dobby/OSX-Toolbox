import SwiftUI

/// Root content of the single unified menu-bar (system tray) icon. Keeps the
/// four original sub-apps as their own submenus (Caffeine Injection,
/// Autoclicker, App Cleaner, App Updater); every other tool is reachable via
/// "More Tools".
struct ToolboxMenuBarView: View {
    @ObservedObject var autoClicker: AutoClickerViewModel
    @ObservedObject var caffeine: CaffeineInjectionManager
    @ObservedObject var appCleaner: AppCleanerManager
    @ObservedObject var appUpdater: AppUpdaterManager
    @ObservedObject var appInstaller: AppInstallerManager
    @ObservedObject var navigation: NavigationModel
    @ObservedObject var quickUtilities: QuickUtilitiesManager
    @ObservedObject var webDashboard: WebDashboardManager

    @Environment(\.openWindow) private var openWindow

    private func openDashboard(at section: ToolboxSection) {
        navigation.selection = section
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }

    var body: some View {
        Group {
            Text(caffeine.statusTitle())

            Divider()

            Menu("☕ Caffeine Injection") {
                Button("Open Caffeine Injection Settings…") { openDashboard(at: .caffeineInjection) }
                Divider()
                caffeineInjectionMenu
            }

            Menu("🖱️ Autoclicker") {
                Button("Open Autoclicker Window…") { openDashboard(at: .autoclicker) }
                Divider()
                autoClickerMenu
            }

            Menu("🧹 App Cleaner") {
                Button("Open App Cleaner…") { openDashboard(at: .appCleaner) }
                Divider()
                Button("Clean an App…") { appCleaner.pickAndClean() }
            }

            Menu("🔄 App Updater") {
                Button("Open App Updater…") { openDashboard(at: .appUpdater) }
                Divider()
                Button("Check All for Updates") { appUpdater.checkAllForUpdates() }
            }

            Menu("📥 App Installer") {
                Button("Open App Installer…") { openDashboard(at: .appInstaller) }
            }

            Divider()

            Button("🌐 Open Web Dashboard") { webDashboard.openInBrowser() }

            Menu("🧰 More Tools") {
                ForEach(ToolboxSection.groupedOrder.filter { $0.group != "Core Tools" }, id: \.group) { group in
                    Menu(group.group) {
                        ForEach(group.sections) { section in
                            Button("Open \(section.rawValue)…") { openDashboard(at: section) }
                        }
                    }
                }
            }

            Menu("⚡️ Quick Actions") {
                Toggle("Microphone Muted", isOn: Binding(get: { quickUtilities.isMicMuted }, set: { _ in quickUtilities.toggleMicrophoneMute() }))
                Toggle("WiFi On", isOn: Binding(get: { quickUtilities.wifiOn }, set: { _ in quickUtilities.toggleWifi() }))
                Button("Eject All External Disks") { quickUtilities.ejectAllExternalDisks() }
            }

            Divider()

            Button("Open RALBE OSX Toolbox…") { openDashboard(at: navigation.selection ?? .caffeineInjection) }

            Divider()

            Button("About RALBE OSX Toolbox…") { showAbout() }

            Divider()

            Button("Quit RALBE OSX Toolbox") { NSApp.terminate(nil) }
        }
    }

    // MARK: Caffeine Injection

    @ViewBuilder
    private var caffeineInjectionMenu: some View {
        Button(caffeine.manualActive ? "End Session" : "Keep Awake Indefinitely") { caffeine.toggleIndefinite() }

        Divider()

        Menu("Keep Awake For…") {
            Button("5 Minutes") { caffeine.startTimed(minutes: 5) }
            Button("15 Minutes") { caffeine.startTimed(minutes: 15) }
            Button("30 Minutes") { caffeine.startTimed(minutes: 30) }
            Button("1 Hour") { caffeine.startTimed(minutes: 60) }
            Button("2 Hours") { caffeine.startTimed(minutes: 120) }
            Button("Custom Duration…") { caffeine.promptCustomDuration() }
        }

        Button("Until a Specified Time…") { caffeine.promptUntilTime() }
        Button("While a File Is Downloading…") { caffeine.promptWhileFile() }
        Button("While an App Is Running…") { caffeine.promptWhileApp() }

        Divider()

        Toggle("Drive Alive (Keep Drive Awake)", isOn: $caffeine.driveAlive)

        Divider()

        Menu("Triggers") {
            Toggle("External Display Connected", isOn: $caffeine.triggerExternalDisplay)
            Toggle("USB Device Connected", isOn: $caffeine.triggerUSB)
            Toggle("Bluetooth Device Connected", isOn: $caffeine.triggerBluetooth)
            Button(caffeine.triggerLabel("App Running", caffeine.triggerAppRunning, caffeine.appBundleName)) { caffeine.promptTriggerApp() }
            Button(caffeine.triggerLabel("App Running & Frontmost", caffeine.triggerAppFrontmost, caffeine.appFrontName)) { caffeine.promptTriggerAppFront() }
            Button(caffeine.triggerLabel("Battery Charging / Above Threshold", caffeine.triggerBattery, "\(caffeine.batteryThresholdPercent)%")) { caffeine.promptTriggerBattery() }
            Toggle("AC Power Connected", isOn: $caffeine.triggerAC)
            Button(caffeine.triggerLabel("Specific IP Address", caffeine.triggerIP, caffeine.targetIP)) { caffeine.promptTriggerIP() }
            Button(caffeine.triggerLabel("Specific WiFi Network", caffeine.triggerWifi, caffeine.targetSSID)) { caffeine.promptTriggerWifi() }
            Toggle("VPN Connected", isOn: $caffeine.triggerVPN)
            Toggle("Headphones / Audio Output In Use", isOn: $caffeine.triggerAudio)
            Button(caffeine.triggerLabel("Specific Volume Mounted", caffeine.triggerVolume, caffeine.targetVolumeName)) { caffeine.promptTriggerVolume() }
            Button(caffeine.triggerLabel("CPU Utilization Threshold", caffeine.triggerCPU, "\(caffeine.cpuThresholdPercent)%")) { caffeine.promptTriggerCPU() }
        }

        Divider()

        Menu("Preferences") {
            Toggle("Allow Display Sleep While Awake", isOn: $caffeine.allowDisplaySleep)
            Button("Allow Screen Saver After Inactivity: \(caffeine.allowScreenSaver ? "\(Int(caffeine.screenSaverIdleMinutes))m" : "Off")…") { caffeine.promptScreenSaver() }
            Toggle("Show Session Time Remaining", isOn: $caffeine.showRemainingTime)
            Toggle("Use 24-Hour Time", isOn: $caffeine.use24Hour)
            Button("Auto-End on Low Battery: \(caffeine.autoEndOnLowBattery ? "\(caffeine.lowBatteryThreshold)%" : "Off")…") { caffeine.promptLowBattery() }
            Menu("Menu Bar Icon") {
                Button("☕ / 🫗 (Default)") { caffeine.setIcons(active: "☕", inactive: "🫗") }
                Button("⚡️ / 💤") { caffeine.setIcons(active: "⚡️", inactive: "💤") }
                Button("🟢 / ⚪️") { caffeine.setIcons(active: "🟢", inactive: "⚪️") }
                Button("Custom…") { caffeine.promptCustomIcons() }
            }
            Button("Hot Key: \(caffeine.hotKeyString)…") { caffeine.promptHotKey() }
        }
    }

    // MARK: Autoclicker

    @ViewBuilder
    private var autoClickerMenu: some View {
        Button(autoClicker.isRunning ? "Stop Clicking" : "Start Clicking") {
            autoClicker.toggleRunning()
        }
        .disabled(!autoClicker.isRunning && !autoClicker.canStart)

        Text("Shortcut: \(HotkeyManager.shortcutDescription)")

        Divider()

        Button("Show Autoclicker Window") {
            openDashboard(at: .autoclicker)
        }
    }

    // MARK: About

    private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "RALBE OSX Toolbox"
        alert.informativeText = """
        A unified macOS menu bar toolbox combining:
          • Caffeine Injection - keep the Mac awake, with automation triggers
          • Autoclicker - simulate keyboard/mouse input
          • App Cleaner - find and remove leftover files for an app
          • App Updater - checks Sparkle-enabled apps and Homebrew/Cask packages for updates and installs them
          • App Installer - installs new apps via Homebrew, the Mac App Store (via `mas`), or a direct download URL
          • Disk Analyzer, Startup & Login Manager, Permissions Inspector,
            Network Toolbox, Quick Utilities, Process Monitor
          • Clipboard Manager, Window Manager, Quick File Finder,
            Screenshot Toolbox, File Conversion, Image Editor
          • Web Dashboard - live device stats in your browser (127.0.0.1 only)

        First time here? Open "Request Permissions" from the sidebar (under
        Setup) to grant Accessibility, Input Monitoring, Full Disk Access,
        Location Services, and Automation access all in one place.

        Caffeine Injection AppleScript support:
          osascript -e 'tell application id "local.ralbeosxtoolbox" to «event cAFFstrt»'   -- start indefinite session
          osascript -e 'tell application id "local.ralbeosxtoolbox" to «event cAFFstop»'   -- end session
          osascript -e 'tell application id "local.ralbeosxtoolbox" to «event cAFFdriv»'   -- toggle Drive Alive

        Autoclicker global start/stop shortcut: \(HotkeyManager.shortcutDescription)
        Caffeine Injection global toggle shortcut: \(caffeine.hotKeyString)

        Note: WiFi SSID detection, global hotkeys, Full Disk Access, and
        Login Item management may each require granting a separate
        permission in System Settings > Privacy & Security - see the
        Request Permissions tab for a one-stop overview.
        """
        alert.runModal()
    }
}
