import AppKit

struct DiskItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let isDirectory: Bool
    let modificationDate: Date?
}

/// Scans one or more chosen folders (non-recursively past the first level,
/// but each child's total size is computed recursively) and lets the user
/// sort by size/name/date, reveal in Finder, or move an item to the Trash.
/// Duplicate-file detection is NOT implemented in this pass (would need a
/// full content-hash pass over the whole disk to be reliable).
@MainActor
final class DiskAnalyzerManager: ObservableObject {
    static let shared = DiskAnalyzerManager()

    enum SortOption: String, CaseIterable, Identifiable {
        case size = "Size", name = "Name", date = "Date Modified"
        var id: String { rawValue }
    }

    @Published var items: [DiskItem] = []
    @Published var isScanning = false
    @Published var currentPath: String = NSHomeDirectory()
    @Published var sortOption: SortOption = .size

    private var scannedPaths: [String] = [NSHomeDirectory()]
    private var excludedPaths: Set<String> = []

    private init() {}

    func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK else { return }
        scan(paths: panel.urls.map(\.path))
    }

    func scanHomeFolder() { scan(path: NSHomeDirectory()) }
    func scanApplicationsFolder() {
        scan(
            paths: ["/Applications", NSHomeDirectory() + "/Applications"],
            excluding: ["/Applications/Utilities"]
        )
    }

    func scanLogsAndCaches() {
        scan(paths: [
            NSHomeDirectory() + "/Library/Logs",
            "/Library/Logs",
            NSHomeDirectory() + "/Library/Caches",
            "/Library/Caches"
        ])
    }

    func scan(path: String) {
        scan(paths: [path])
    }

    func scan(paths: [String], excluding excludedPaths: [String] = []) {
        let paths = Array(Set(paths.filter { FileManager.default.fileExists(atPath: $0) })).sorted()
        guard !paths.isEmpty else {
            items = []
            currentPath = "No selected folders were found."
            return
        }
        scannedPaths = paths
        self.excludedPaths = Set(excludedPaths)
        currentPath = paths.joined(separator: " • ")
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [DiskItem] = []
            for path in paths {
                if let contents = try? FileManager.default.contentsOfDirectory(
                    at: URL(fileURLWithPath: path),
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                ) {
                    for url in contents {
                        guard !excludedPaths.contains(url.path) else { continue }
                        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                        let size = directorySize(url.path)
                        results.append(DiskItem(url: url, size: size, isDirectory: isDir, modificationDate: modDate))
                    }
                }
            }
            Task { @MainActor in
                self?.items = results
                self?.isScanning = false
            }
        }
    }

    var sortedItems: [DiskItem] {
        switch sortOption {
        case .size: return items.sorted { $0.size > $1.size }
        case .name: return items.sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }
        case .date: return items.sorted { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) }
        }
    }

    func reveal(_ item: DiskItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func moveToTrash(_ item: DiskItem) {
        NSWorkspace.shared.recycle([item.url]) { [weak self] _, _ in
            Task { @MainActor in
                self?.scan(
                    paths: self?.scannedPaths ?? [NSHomeDirectory()],
                    excluding: Array(self?.excludedPaths ?? [])
                )
            }
        }
    }
}
