import AppKit
import CoreGraphics

/// Repeatedly synthesizes keyboard and mouse events on a background timer.
///
/// Keys are typed one at a time, cycling through `keyCodes` in order (so
/// duplicates are preserved and a sequence like h,e,l,l,o is typed as
/// "hello" rather than every key firing at once). Mouse buttons still fire
/// every tick alongside whichever key is due next.
///
/// If `targetPid` is non-nil, every event is delivered directly to that
/// process via `CGEvent.postToPid`, regardless of which app currently has
/// focus. If `targetPid` is nil, events are targeted at whatever application
/// is frontmost at the moment each tick fires (re-resolved every tick so it
/// tracks focus changes live).
final class ClickerEngine {
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.autoclicker.engine", qos: .userInteractive)
    private let eventSource = CGEventSource(stateID: .hidSystemState)
    private var keySequenceIndex = 0

    var isRunning: Bool { timer != nil }

    func start(keyCodes: [CGKeyCode], mouseButtons: [MouseButtonOption], interval: TimeInterval, targetPid: pid_t?) {
        stop()
        keySequenceIndex = 0

        // Guard against a zero/negative interval which would spin the CPU forever.
        let clampedInterval = max(interval, 0.0001)
        let targetDescription = targetPid.map { "pid \($0)" } ?? "focused app"
        DebugLogger.shared.log("Clicking started: typing \(keyCodes.count) key(s) in sequence, \(mouseButtons.count) mouse button(s), every \(clampedInterval)s, target: \(targetDescription).")

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: clampedInterval, leeway: .nanoseconds(0))
        source.setEventHandler { [weak self] in
            self?.fireTick(keyCodes: keyCodes, mouseButtons: mouseButtons, targetPid: targetPid)
        }
        source.resume()
        timer = source
    }

    func stop() {
        guard timer != nil else { return }
        timer?.cancel()
        timer = nil
        DebugLogger.shared.log("Clicking stopped.")
    }

    private func fireTick(keyCodes: [CGKeyCode], mouseButtons: [MouseButtonOption], targetPid: pid_t?) {
        // No app explicitly selected: always re-resolve the current frontmost app
        // so clicks follow whatever window/application is in focus right now.
        let resolvedPid = targetPid ?? NSWorkspace.shared.frontmostApplication?.processIdentifier

        if !keyCodes.isEmpty {
            let keyCode = keyCodes[keySequenceIndex % keyCodes.count]
            keySequenceIndex += 1
            postKey(keyCode, targetPid: resolvedPid)
        }
        for button in mouseButtons {
            postMouseClick(button, targetPid: resolvedPid)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, targetPid: pid_t?) {
        guard
            let down = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        else {
            DebugLogger.shared.log("WARNING: failed to create key event for key code \(keyCode).")
            return
        }

        post(down, up, targetPid: targetPid)
    }

    private func postMouseClick(_ button: MouseButtonOption, targetPid: pid_t?) {
        let location = CGEvent(source: eventSource)?.location ?? .zero
        let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) = {
            switch button {
            case .left: return (.leftMouseDown, .leftMouseUp, .left)
            case .right: return (.rightMouseDown, .rightMouseUp, .right)
            }
        }()

        guard
            let down = CGEvent(mouseEventSource: eventSource, mouseType: downType, mouseCursorPosition: location, mouseButton: cgButton),
            let up = CGEvent(mouseEventSource: eventSource, mouseType: upType, mouseCursorPosition: location, mouseButton: cgButton)
        else { return }

        post(down, up, targetPid: targetPid)
    }

    private func post(_ down: CGEvent, _ up: CGEvent, targetPid: pid_t?) {
        if let pid = targetPid {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
