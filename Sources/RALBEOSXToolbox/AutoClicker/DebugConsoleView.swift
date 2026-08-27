import SwiftUI

/// Right-hand debug console panel showing a live feed of what AutoClicker is
/// doing internally (permission checks, hotkey activity, start/stop events),
/// to help diagnose issues like the global shortcut not firing.
struct DebugConsoleView: View {
    @ObservedObject private var logger = DebugLogger.shared

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Console", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    logger.clear()
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(logger.entries) { entry in
                            Text("[\(Self.timeFormatter.string(from: entry.timestamp))] \(entry.message)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: logger.entries.count) { _ in
                    if let lastID = logger.entries.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.gray.opacity(0.06))
    }
}
