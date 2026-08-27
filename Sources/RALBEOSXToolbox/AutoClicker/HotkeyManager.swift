import AppKit
import Carbon.HIToolbox

/// Listens for a global "toggle start/stop" hotkey (⌥⇧C) so the user can
/// start/stop clicking from anywhere without switching focus to this app's
/// window. Uses both a global monitor (for when another app is frontmost)
/// and a local monitor (for when AutoClicker's own window is focused).
///
/// Note: plain function keys (F1-F12) are intentionally avoided as the
/// default shortcut. On most Mac keyboards, those keys send hardware
/// media/brightness events instead of a standard key-down unless the user
/// holds Fn (or has "Use F1, F2, etc. as standard function keys" enabled),
/// so a bare F-key shortcut silently never fires for most users. A
/// modifier+letter combo doesn't have that problem.
///
/// Receiving *global* key events also requires the app to be granted
/// "Input Monitoring" access in System Settings (separate from
/// Accessibility, which is only needed for posting synthetic events).
final class HotkeyManager {
    static let shortcutDescription = "⌥⇧C"

    private static let requiredKeyCode = UInt16(kVK_ANSI_C)
    private static let requiredModifiers: NSEvent.ModifierFlags = [.option, .shift]
    private static let relevantModifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hasConfirmedGlobalMonitoring = false

    var onToggle: (() -> Void)?

    func start() {
        stop()
        DebugLogger.shared.log("Hotkey manager starting (shortcut: \(Self.shortcutDescription)).")

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleGlobal(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event, isGlobal: false)
            return event
        }

        if globalMonitor == nil {
            DebugLogger.shared.log("WARNING: failed to install the global key monitor.")
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    deinit {
        stop()
    }

    private func handleGlobal(_ event: NSEvent) {
        if !hasConfirmedGlobalMonitoring {
            hasConfirmedGlobalMonitoring = true
            DebugLogger.shared.log("Global key monitoring is receiving events (Input Monitoring permission looks granted).")
        }
        handle(event, isGlobal: true)
    }

    private func handle(_ event: NSEvent, isGlobal: Bool) {
        let modifiers = event.modifierFlags.intersection(Self.relevantModifierMask)
        guard event.keyCode == Self.requiredKeyCode, modifiers == Self.requiredModifiers else { return }

        DebugLogger.shared.log("Hotkey \(Self.shortcutDescription) detected (\(isGlobal ? "global" : "local monitor")) - toggling.")
        onToggle?()
    }
}
