import AppKit
import ApplicationServices

/// Moves/resizes the frontmost window via the Accessibility (AX) API.
/// "Remember window positions" from the original feature list is NOT
/// implemented (needs persistent per-app-window identity tracking, out of
/// scope for this pass); moving to another Space is also not implemented
/// (Spaces have no public API). Moving between displays IS implemented.
@MainActor
final class WindowManagerService: ObservableObject {
    static let shared = WindowManagerService()

    enum Placement: String, CaseIterable, Identifiable {
        case leftHalf = "Left Half", rightHalf = "Right Half"
        case topHalf = "Top Half", bottomHalf = "Bottom Half"
        case topLeftQuarter = "Top-Left Quarter", topRightQuarter = "Top-Right Quarter"
        case bottomLeftQuarter = "Bottom-Left Quarter", bottomRightQuarter = "Bottom-Right Quarter"
        case center = "Center", maximize = "Maximize"
        var id: String { rawValue }
    }

    /// The last app that was frontmost before RALBE OSX Toolbox itself became
    /// active. Clicking a placement button in our own window makes US the
    /// frontmost app, so `NSWorkspace.frontmostApplication` at that point
    /// would always resolve to our own window - tracking activation
    /// notifications lets placement act on whatever app the user was
    /// actually using beforehand, like Rectangle/Magnet do.
    @Published private(set) var targetAppName: String?
    private var lastExternalApp: NSRunningApplication?
    private var isObserving = false

    private init() {}

    func start() {
        guard !isObserving else { return }
        isObserving = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            lastExternalApp = app
            targetAppName = app.localizedName
        }
    }

    func stop() {
        guard isObserving else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        isObserving = false
    }

    @objc nonisolated private func activeAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        Task { @MainActor in
            self.lastExternalApp = app
            self.targetAppName = app.localizedName
        }
    }

    func apply(_ placement: Placement) {
        guard AccessibilityPermission.isTrusted(promptIfNeeded: true) else { return }
        guard let window = targetWindow(), let screenFrame = NSScreen.main?.visibleFrame else { return }
        let frame = self.frame(for: placement, in: screenFrame)
        setFrame(frame, for: window, screenHeight: NSScreen.main!.frame.maxY)
    }

    func moveToNextDisplay() {
        guard AccessibilityPermission.isTrusted(promptIfNeeded: true) else { return }
        guard let window = targetWindow() else { return }
        let screens = NSScreen.screens
        guard screens.count > 1, let mainScreen = NSScreen.main else { return }
        let idx = screens.firstIndex(where: { $0 === mainScreen }) ?? 0
        let nextScreen = screens[(idx + 1) % screens.count]
        setFrame(nextScreen.visibleFrame, for: window, screenHeight: nextScreen.frame.maxY)
    }

    private func frame(for placement: Placement, in screen: CGRect) -> CGRect {
        let w = screen.width, h = screen.height
        switch placement {
        case .leftHalf: return CGRect(x: screen.minX, y: screen.minY, width: w / 2, height: h)
        case .rightHalf: return CGRect(x: screen.minX + w / 2, y: screen.minY, width: w / 2, height: h)
        case .topHalf: return CGRect(x: screen.minX, y: screen.minY + h / 2, width: w, height: h / 2)
        case .bottomHalf: return CGRect(x: screen.minX, y: screen.minY, width: w, height: h / 2)
        case .topLeftQuarter: return CGRect(x: screen.minX, y: screen.minY + h / 2, width: w / 2, height: h / 2)
        case .topRightQuarter: return CGRect(x: screen.minX + w / 2, y: screen.minY + h / 2, width: w / 2, height: h / 2)
        case .bottomLeftQuarter: return CGRect(x: screen.minX, y: screen.minY, width: w / 2, height: h / 2)
        case .bottomRightQuarter: return CGRect(x: screen.minX + w / 2, y: screen.minY, width: w / 2, height: h / 2)
        case .center: return CGRect(x: screen.minX + w / 4, y: screen.minY + h / 4, width: w / 2, height: h / 2)
        case .maximize: return screen
        }
    }

    /// Resolves the focused window of the last app the user was actually
    /// using rather than whatever is frontmost right now - see the doc
    /// comment on `lastExternalApp` above for why that distinction matters.
    private func targetWindow() -> AXUIElement? {
        guard let app = lastExternalApp, !app.isTerminated else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    /// AX uses a top-left origin; NSScreen/CGRect use bottom-left, so the Y
    /// axis has to be flipped when handing a frame to the Accessibility API.
    private func setFrame(_ frame: CGRect, for window: AXUIElement, screenHeight: CGFloat) {
        var origin = CGPoint(x: frame.minX, y: screenHeight - frame.minY - frame.height)
        var size = frame.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }
}
