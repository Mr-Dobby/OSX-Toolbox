import AppKit

struct ProcessInfoItem: Identifiable {
    let id: Int32
    let name: String
    let cpu: Double
    let memPercent: Double
}

/// A friendlier, read-only-by-default Activity Monitor built on `ps` output
/// (no private APIs). Quit/Force Quit only work for processes owned by the
/// current user (macOS will simply refuse otherwise).
@MainActor
final class ProcessMonitorManager: ObservableObject {
    static let shared = ProcessMonitorManager()

    @Published var processes: [ProcessInfoItem] = []
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func refresh() {
        // Off the main thread: `ps` blocks via Process.waitUntilExit(), whose
        // internal run loop pump can reenter SwiftUI's attribute graph and
        // crash if it fires mid-transaction (same root cause as the
        // StartupManager launch crash).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let output = caffeineShell("/bin/ps", ["-Ao", "pid,pcpu,pmem,comm", "-r"])
            var results: [ProcessInfoItem] = []
            for line in output.split(separator: "\n").dropFirst() {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                guard parts.count >= 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let mem = Double(parts[2]) else { continue }
                let name = (String(parts[3]) as NSString).lastPathComponent
                results.append(ProcessInfoItem(id: pid, name: name, cpu: cpu, memPercent: mem))
            }
            let capped = Array(results.prefix(60))
            Task { @MainActor in self?.processes = capped }
        }
    }

    func quit(_ item: ProcessInfoItem) { kill(item.id, SIGTERM) }
    func forceQuit(_ item: ProcessInfoItem) { kill(item.id, SIGKILL) }

    func reveal(_ item: ProcessInfoItem) {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == item.id }),
           let url = app.bundleURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func searchWeb(_ item: ProcessInfoItem) {
        guard let encoded = item.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)+macos+process") else { return }
        NSWorkspace.shared.open(url)
    }
}
