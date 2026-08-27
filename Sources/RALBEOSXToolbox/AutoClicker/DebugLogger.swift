import Foundation

/// A tiny in-memory, thread-safe log used to power the in-app debug console.
/// Any thread may call `log(_:)` (the engine posts events from a background
/// queue); UI-facing mutations are always dispatched onto the main thread so
/// SwiftUI observers stay safe.
final class DebugLogger: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
    }

    static let shared = DebugLogger()

    @Published private(set) var entries: [Entry] = []

    private let maxEntries = 500

    private init() {}

    func log(_ message: String) {
        let entry = Entry(timestamp: Date(), message: message)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }
    }

    func clear() {
        DispatchQueue.main.async { [weak self] in
            self?.entries.removeAll()
        }
    }
}
