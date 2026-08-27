import AppKit

struct DiskItem: Identifiable {
    let id = UUID()
    let url: URL
    let size: Int64
    let isDirectory: Bool
    let modificationDate: Date?
}

/// Scans a chosen folder (non-recursively past the first level, but each
/// child's total size is computed recursively) and lets the user sort by
/// size/name/date, reveal in Finder, or move an item to the Trash.
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

    private init() {}

    func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(path: url.path)
    }

    func scanHomeFolder() { scan(path: NSHomeDirectory()) }

    func scan(path: String) {
        currentPath = path
        isScanning = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var results: [DiskItem] = []
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) {
                for url in contents {
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    let size = directorySize(url.path)
                    results.append(DiskItem(url: url, size: size, isDirectory: isDir, modificationDate: modDate))
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
            Task { @MainActor in self?.scan(path: self?.currentPath ?? NSHomeDirectory()) }
        }
    }
}
