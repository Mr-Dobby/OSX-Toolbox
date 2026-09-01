import Foundation

/// Wraps `/usr/bin/caffeinate` to keep the system awake. Flags are recomputed
/// and the process restarted whenever the desired configuration changes.
final class AwakeEngine {
    private var process: Process?
    private var lastFlags: [String] = []

    var isEngaged: Bool { process != nil }

    func setEngaged(_ engaged: Bool, allowDisplaySleep: Bool, driveAlive: Bool) {
        guard engaged else {
            stop()
            return
        }

        let flags = computeFlags(allowDisplaySleep: allowDisplaySleep, driveAlive: driveAlive)
        if process != nil, flags == lastFlags { return }
        process?.terminate()
        process = nil

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        p.arguments = flags
        do {
            try p.run()
            process = p
            lastFlags = flags
        } catch {
            print("caffeinate failed: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
        lastFlags = []
    }

    private func computeFlags(allowDisplaySleep: Bool, driveAlive: Bool) -> [String] {
        var flags = ["-i"] // prevent idle system sleep, always, while engaged
        if !allowDisplaySleep { flags.append("-d") }
        if driveAlive { flags.append("-m") }
        return flags
    }
}
