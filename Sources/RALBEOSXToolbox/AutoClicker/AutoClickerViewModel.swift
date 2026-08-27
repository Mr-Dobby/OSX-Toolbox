import AppKit
import Combine
import Foundation

@MainActor
final class AutoClickerViewModel: ObservableObject {
    @Published var keysInputText: String = ""
    @Published var selectedMouseButtons: Set<MouseButtonOption> = []
    @Published var intervalValue: Double = 100
    @Published var intervalUnit: TimeUnit = .milliseconds
    @Published var runningApps: [RunningAppInfo] = []
    @Published var selectedAppID: pid_t?
    @Published var isRunning: Bool = false
    @Published var accessibilityTrusted: Bool = false
    @Published var isSyncing: Bool = false
    @Published var syncStatusMessage: String?
    @Published var isConsoleVisible: Bool = true

    private let engine = ClickerEngine()
    private let hotkeyManager = HotkeyManager()
    private var permissionTimer: Timer?
    private var syncStatusResetTask: Task<Void, Never>?

    init() {
        DebugLogger.shared.log("AutoClicker launched.")
        refreshRunningApps()
        accessibilityTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
        DebugLogger.shared.log("Accessibility trusted: \(accessibilityTrusted).")
        startPermissionPolling()

        hotkeyManager.onToggle = { [weak self] in
            Task { @MainActor in
                self?.toggleRunning()
            }
        }
        hotkeyManager.start()
    }

    deinit {
        permissionTimer?.invalidate()
        syncStatusResetTask?.cancel()
    }

    /// Re-checks Accessibility trust and refreshes the running-app list on
    /// demand, so the user can confirm everything is set up correctly right
    /// after granting permissions in System Settings (without waiting for the
    /// background poll or relaunching the app).
    func syncSetup() {
        isSyncing = true
        DebugLogger.shared.log("Sync requested by user.")
        accessibilityTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
        refreshRunningApps()
        isSyncing = false

        syncStatusMessage = accessibilityTrusted
            ? "Synced - Accessibility access is granted."
            : "Synced - Accessibility access is still not detected."
        DebugLogger.shared.log(syncStatusMessage ?? "")

        syncStatusResetTask?.cancel()
        syncStatusResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            self?.syncStatusMessage = nil
        }
    }

    func refreshRunningApps() {
        runningApps = RunningAppsProvider.fetch()
        if let selectedAppID, !runningApps.contains(where: { $0.id == selectedAppID }) {
            self.selectedAppID = nil
        }
        DebugLogger.shared.log("Refreshed running applications: \(runningApps.count) found.")
    }

    func requestAccessibilityAccess() {
        accessibilityTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: true)
        DebugLogger.shared.log("Requested Accessibility access - trusted: \(accessibilityTrusted).")
        if !accessibilityTrusted {
            AccessibilityPermission.openAccessibilitySettings()
        }
    }

    func toggleMouse(_ button: MouseButtonOption) {
        if selectedMouseButtons.contains(button) {
            selectedMouseButtons.remove(button)
        } else {
            selectedMouseButtons.insert(button)
        }
    }

    /// Unique keys parsed live from `keysInputText` (e.g. "1, 2, 3" or "a s d
    /// space") - used for the chip preview, where each key should only show once.
    var parsedKeys: [KeyOption] {
        KeysInputParser.parse(keysInputText).keys
    }

    /// Every recognized key in the order typed, duplicates preserved (e.g.
    /// "h,e,l,l,o" keeps both `l`s) - this is what actually gets played back,
    /// one key at a time, so typing a word works as expected.
    var keyPlaybackSequence: [KeyOption] {
        KeysInputParser.parse(keysInputText).sequence
    }

    /// Tokens in `keysInputText` that couldn't be matched to a known key.
    var unrecognizedKeyTokens: [String] {
        KeysInputParser.parse(keysInputText).unrecognizedTokens
    }

    var canStart: Bool {
        (!parsedKeys.isEmpty || !selectedMouseButtons.isEmpty) && intervalValue > 0 && accessibilityTrusted
    }

    func toggleRunning() {
        isRunning ? stop() : start()
    }

    func start() {
        guard canStart else {
            DebugLogger.shared.log("Start blocked: \(startBlockedReason).")
            return
        }
        let keyCodes = keyPlaybackSequence.map { $0.keyCode }
        let interval = intervalUnit.toSeconds(intervalValue)
        engine.start(
            keyCodes: keyCodes,
            mouseButtons: Array(selectedMouseButtons),
            interval: interval,
            targetPid: selectedAppID
        )
        isRunning = true
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    private var startBlockedReason: String {
        if !accessibilityTrusted { return "Accessibility permission not granted" }
        if parsedKeys.isEmpty && selectedMouseButtons.isEmpty { return "no keys or mouse buttons selected" }
        if intervalValue <= 0 { return "interval must be greater than 0" }
        return "unknown"
    }

    /// Polls the Accessibility trust state periodically so the banner in the
    /// UI clears itself automatically after the user grants access in
    /// System Settings, without needing to relaunch the app.
    private func startPermissionPolling() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.accessibilityTrusted = AccessibilityPermission.isTrusted(promptIfNeeded: false)
            }
        }
    }
}
