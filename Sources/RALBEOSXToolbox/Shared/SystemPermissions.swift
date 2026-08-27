import AppKit
import ApplicationServices

/// Full Disk Access has no public "request" API - only a way to detect it
/// (by probing a TCC-protected directory) and deep-link to System Settings.
/// Accessibility and Input Monitoring live in `AutoClicker/PermissionsManager.swift`
/// as `AccessibilityPermission` and are reused as-is by every sub-app here.
enum SystemPermissions {
    static func hasFullDiskAccess() -> Bool {
        let path = NSHomeDirectory() + "/Library/Safari"
        return (try? FileManager.default.contentsOfDirectory(atPath: path)) != nil
    }

    static func promptFullDiskAccess() {
        let alert = NSAlert()
        alert.messageText = "Full Disk Access Needed"
        alert.informativeText = "App Cleaner needs Full Disk Access to find leftover app files (caches, logs, preferences, support files). Grant it in System Settings > Privacy & Security > Full Disk Access, then relaunch RALBE OSX Toolbox."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
        }
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

    static func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    /// Triggers the Automation TCC prompt for "System Events" (used by the
    /// Startup Manager to list/remove Login Items) by making a harmless call.
    static func triggerAutomationPrompt() {
        _ = caffeineShell("/usr/bin/osascript", ["-e", "tell application \"System Events\" to get the name of every login item"])
    }

    /// Requests every permission used across the three sub-apps, once per
    /// install. Accessibility/Input Monitoring prompts are native macOS
    /// dialogs; Full Disk Access can only be surfaced via our own alert
    /// since there's no system prompt for it.
    static func requestAllIfNeeded() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "didRequestPermissions") else { return }
        d.set(true, forKey: "didRequestPermissions")

        _ = AccessibilityPermission.isTrusted(promptIfNeeded: true)
        if !hasFullDiskAccess() { promptFullDiskAccess() }
    }
}
