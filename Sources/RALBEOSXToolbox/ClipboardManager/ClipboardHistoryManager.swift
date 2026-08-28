import AppKit

struct ClipboardEntry: Identifiable {
    let id = UUID()
    let text: String
    let date: Date
    var pinned: Bool = false
}

/// Polls `NSPasteboard.general` (there's no push notification for clipboard
/// changes) to build a history. Skips anything tagged with the unofficial
/// `org.nspasteboard.ConcealedType` convention that password managers use to
/// mark secrets, so passwords aren't recorded. Entries are in-memory only
/// (not persisted to disk) so history doesn't survive a relaunch - this is
/// deliberate for a "clipboard", which often holds sensitive text.
@MainActor
final class ClipboardHistoryManager: ObservableObject {
    static let shared = ClipboardHistoryManager()

    @Published var history: [ClipboardEntry] = []
    @Published var isEnabled = true
    @Published var searchText = ""

    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let maxEntries = 200

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollPasteboard() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    var filteredHistory: [ClipboardEntry] {
        guard !searchText.isEmpty else { return history }
        return history.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    /// Pinned entries keep their relative order but surface separately so
    /// they don't get buried by newer unpinned copies further down the list.
    var pinnedHistory: [ClipboardEntry] { filteredHistory.filter { $0.pinned } }
    var unpinnedHistory: [ClipboardEntry] { filteredHistory.filter { !$0.pinned } }

    private func pollPasteboard() {
        guard isEnabled else { return }
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let types = pb.types ?? []
        if types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) { return }

        guard let text = pb.string(forType: .string), !text.isEmpty else { return }
        if history.first?.text == text { return }
        history.insert(ClipboardEntry(text: text, date: Date()), at: 0)
        if history.count > maxEntries {
            history.removeLast(history.count - maxEntries)
        }
    }

    func copyToPasteboard(_ entry: ClipboardEntry) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    func copyPrevious() {
        guard history.count > 1 else { return }
        copyToPasteboard(history[1])
    }

    func togglePin(_ entry: ClipboardEntry) {
        guard let idx = history.firstIndex(where: { $0.id == entry.id }) else { return }
        history[idx].pinned.toggle()
    }

    func remove(_ entry: ClipboardEntry) {
        history.removeAll { $0.id == entry.id }
    }

    func clearUnpinned() {
        history.removeAll { !$0.pinned }
    }
}
