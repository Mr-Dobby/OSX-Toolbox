import AppKit
import ApplicationServices

/// Wraps the macOS Accessibility (AX) trust check that is required before this
/// app is allowed to synthesize keyboard/mouse events via CGEvent.
enum AccessibilityPermission {
    /// Returns whether this process is currently trusted for Accessibility.
    /// - Parameter promptIfNeeded: When true and the app is not yet trusted,
    ///   macOS shows its native "AutoClicker would like to control this
    ///   computer" prompt and adds the app to the Accessibility list.
    @discardableResult
    static func isTrusted(promptIfNeeded: Bool = false) -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [promptKey: promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to the Privacy & Security > Accessibility pane.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Opens System Settings directly to the Privacy & Security > Input Monitoring
    /// pane. Required for the global start/stop hotkey to receive key events
    /// while another app is frontmost. There is no public API to query this
    /// permission's current state, unlike Accessibility.
    static func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
