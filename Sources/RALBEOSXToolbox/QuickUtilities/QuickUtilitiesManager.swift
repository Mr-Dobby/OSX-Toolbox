import AppKit
import CoreAudio

/// Small always-available menu bar utilities. Focus Mode toggling and
/// fan/temperature sensor readouts are intentionally NOT implemented here -
/// macOS has no public API for either (Focus requires private
/// com.apple.donotdisturbd IPC, sensors require private SMC calls), so
/// faking them would be misleading.
@MainActor
final class QuickUtilitiesManager: ObservableObject {
    static let shared = QuickUtilitiesManager()

    @Published var isMicMuted = false
    @Published var wifiOn = true
    @Published var battery: (percent: Int, isCharging: Bool, acConnected: Bool) = (100, true, true)
    @Published var displays: [String] = []

    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        battery = batteryInfo()
        displays = NSScreen.screens.enumerated().map { index, screen in
            "Display \(index + 1): \(Int(screen.frame.width))x\(Int(screen.frame.height))"
        }
    }

    func ejectAllExternalDisks() {
        guard let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else { return }
        for volume in volumes where volume != "Macintosh HD" {
            _ = caffeineShell("/usr/sbin/diskutil", ["eject", "/Volumes/\(volume)"])
        }
    }

    func toggleWifi() {
        wifiOn.toggle()
        _ = caffeineShell("/usr/sbin/networksetup", ["-setairportpower", "en0", wifiOn ? "on" : "off"])
    }

    func toggleMicrophoneMute() {
        isMicMuted.toggle()
        setInputVolume(isMicMuted ? 0.0 : 0.5)
    }

    private func setInputVolume(_ value: Float32) {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr else { return }

        var volume = value
        var volumeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: 0)
        AudioObjectSetPropertyData(deviceID, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
    }
}
