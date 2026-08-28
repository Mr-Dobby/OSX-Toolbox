import AppKit

/// Spotlight-backed search (NSMetadataQuery) - filename and/or file-content
/// search, optional "large files only" filter, sortable results. No
/// dedicated global keyboard shortcut in this pass (see ClipboardHistoryManager
/// for the same note); open via the sidebar or menu bar instead.
@MainActor
final class QuickFileFinderManager: NSObject, ObservableObject {
    static let shared = QuickFileFinderManager()

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size", date = "Date Modified"
        var id: String { rawValue }
    }

    @Published var query = ""
    @Published var results: [URL] = []
    @Published var isSearching = false
    @Published var largeFilesOnly = false
    @Published var sortOption: SortOption = .name

    private var metadataQuery: NSMetadataQuery?

    private override init() { super.init() }

    func search() {
        stopQuery()
        guard !query.isEmpty else { results = []; return }

        let mq = NSMetadataQuery()
        mq.searchScopes = [NSMetadataQueryUserHomeScope]

        var predicateFormat: String
        var args: [Any]
        if Self.isWildcardPattern(query) {
            // NSPredicate's LIKE operator natively treats * as "any run of
            // characters" and ? as "exactly one character" - unlike CONTAINS,
            // which would match them as literal text. Filename-only, since a
            // glob pattern doesn't make sense against file contents.
            predicateFormat = "kMDItemFSName LIKE[cd] %@"
            args = [query]
        } else {
            predicateFormat = "(kMDItemFSName CONTAINS[cd] %@) OR (kMDItemTextContent CONTAINS[cd] %@)"
            args = [query, query]
        }
        if largeFilesOnly {
            predicateFormat = "(\(predicateFormat)) AND (kMDItemFSSize > %@)"
            args.append(NSNumber(value: 100 * 1024 * 1024))
        }
        mq.predicate = NSPredicate(format: predicateFormat, argumentArray: args)

        NotificationCenter.default.addObserver(self, selector: #selector(queryDidFinish), name: .NSMetadataQueryDidFinishGathering, object: mq)
        metadataQuery = mq
        isSearching = true
        mq.start()
    }

    nonisolated private static func isWildcardPattern(_ text: String) -> Bool {
        text.contains("*") || text.contains("?")
    }

    @objc private func queryDidFinish(_ note: Notification) {
        guard let mq = metadataQuery else { return }
        mq.disableUpdates()
        let items = (mq.results as? [NSMetadataItem]) ?? []
        let urls = items.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }.map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: mq)
        mq.stop()
        Task { @MainActor in
            self.results = self.sorted(Array(urls.prefix(300)))
            self.isSearching = false
            self.metadataQuery = nil
        }
    }

    private func sorted(_ urls: [URL]) -> [URL] {
        switch sortOption {
        case .name: return urls.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
        case .size: return urls.sorted { fileSize($0) > fileSize($1) }
        case .date: return urls.sorted { modDate($0) > modDate($1) }
        }
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize.map(Int64.init) ?? 0
    }

    private func modDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }

    func stopQuery() {
        metadataQuery?.stop()
        metadataQuery = nil
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func copyPath(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.path, forType: .string)
    }
}
