import SwiftUI

/// Full in-window configuration screen for Caffeine Injection, mirroring the
/// menu bar submenu but laid out as a scrollable form so everything is
/// visible and editable at once.
struct CaffeineInjectionSettingsView: View {
    @ObservedObject var caffeine: CaffeineInjectionManager

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Current State", value: caffeine.statusTitle())
                HStack {
                    Button(caffeine.manualActive ? "End Session" : "Keep Awake Indefinitely") {
                        caffeine.toggleIndefinite()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("5m") { caffeine.startTimed(minutes: 5) }
                    Button("15m") { caffeine.startTimed(minutes: 15) }
                    Button("30m") { caffeine.startTimed(minutes: 30) }
                    Button("1h") { caffeine.startTimed(minutes: 60) }
                    Button("2h") { caffeine.startTimed(minutes: 120) }
                }
                HStack {
                    Button("Custom Duration…") { caffeine.promptCustomDuration() }
                    Button("Until a Specified Time…") { caffeine.promptUntilTime() }
                    Button("While a File Downloads…") { caffeine.promptWhileFile() }
                    Button("While an App Is Running…") { caffeine.promptWhileApp() }
                }
            }

            Section("Awake Behavior") {
                Toggle("Drive Alive (Keep Drive Awake)", isOn: $caffeine.driveAlive)
                Toggle("Allow Display Sleep While Awake", isOn: $caffeine.allowDisplaySleep)
                Toggle("Show Session Time Remaining", isOn: $caffeine.showRemainingTime)
                Toggle("Use 24-Hour Time", isOn: $caffeine.use24Hour)
            }

            Section("Automation Triggers") {
                Toggle("External Display Connected", isOn: $caffeine.triggerExternalDisplay)
                Toggle("USB Device Connected", isOn: $caffeine.triggerUSB)
                Toggle("Bluetooth Device Connected", isOn: $caffeine.triggerBluetooth)
                Toggle("AC Power Connected", isOn: $caffeine.triggerAC)
                Toggle("VPN Connected", isOn: $caffeine.triggerVPN)
                Toggle("Headphones / Audio Output In Use", isOn: $caffeine.triggerAudio)

                Toggle("App Running", isOn: $caffeine.triggerAppRunning)
                TextField("App name", text: $caffeine.appBundleName)
                    .disabled(!caffeine.triggerAppRunning)

                Toggle("App Running & Frontmost", isOn: $caffeine.triggerAppFrontmost)
                TextField("App name", text: $caffeine.appFrontName)
                    .disabled(!caffeine.triggerAppFrontmost)

                Toggle("Battery Charging / Above Threshold", isOn: $caffeine.triggerBattery)
                Stepper("Battery threshold: \(caffeine.batteryThresholdPercent)%", value: $caffeine.batteryThresholdPercent, in: 1...100)
                    .disabled(!caffeine.triggerBattery)

                Toggle("Specific IP Address", isOn: $caffeine.triggerIP)
                TextField("IP address", text: $caffeine.targetIP)
                    .disabled(!caffeine.triggerIP)

                Toggle("Specific WiFi Network", isOn: $caffeine.triggerWifi)
                TextField("SSID", text: $caffeine.targetSSID)
                    .disabled(!caffeine.triggerWifi)

                Toggle("Specific Volume Mounted", isOn: $caffeine.triggerVolume)
                TextField("Volume name", text: $caffeine.targetVolumeName)
                    .disabled(!caffeine.triggerVolume)

                Toggle("CPU Utilization Threshold", isOn: $caffeine.triggerCPU)
                Stepper("CPU threshold: \(caffeine.cpuThresholdPercent)%", value: $caffeine.cpuThresholdPercent, in: 1...100)
                    .disabled(!caffeine.triggerCPU)
            }

            Section("Screen Saver & Battery") {
                Toggle("Allow Screen Saver After Inactivity", isOn: $caffeine.allowScreenSaver)
                Stepper("Idle minutes: \(Int(caffeine.screenSaverIdleMinutes))", value: $caffeine.screenSaverIdleMinutes, in: 1...120)
                    .disabled(!caffeine.allowScreenSaver)

                Toggle("Auto-End on Low Battery", isOn: $caffeine.autoEndOnLowBattery)
                Stepper("Threshold: \(caffeine.lowBatteryThreshold)%", value: $caffeine.lowBatteryThreshold, in: 1...100)
                    .disabled(!caffeine.autoEndOnLowBattery)
            }

            Section("Menu Bar Icon") {
                HStack {
                    Text("Active: \(caffeine.activeIcon)")
                    Text("Inactive: \(caffeine.inactiveIcon)")
                    Spacer()
                    Button("☕/🫗") { caffeine.setIcons(active: "☕", inactive: "🫗") }
                    Button("⚡️/💤") { caffeine.setIcons(active: "⚡️", inactive: "💤") }
                    Button("🟢/⚪️") { caffeine.setIcons(active: "🟢", inactive: "⚪️") }
                    Button("Custom…") { caffeine.promptCustomIcons() }
                }
            }

            Section("Hot Key") {
                TextField("e.g. option+shift+c", text: $caffeine.hotKeyString)
                Text("Modifiers: cmd, option, shift, ctrl - combined with a letter or digit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
