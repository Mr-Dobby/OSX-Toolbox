import SwiftUI

struct ClipboardManagerView: View {
    @ObservedObject var manager: ClipboardHistoryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Clipboard Manager").font(.title2).bold()
                Spacer()
                Toggle("Recording", isOn: $manager.isEnabled)
                Button("Copy Previous") { manager.copyPrevious() }
                Button("Clear Unpinned") { manager.clearUnpinned() }
            }

            TextField("Search history…", text: $manager.searchText)
                .textFieldStyle(.roundedBorder)

            Text("Sensitive items marked by password managers (org.nspasteboard.ConcealedType) are skipped automatically. No dedicated global keyboard shortcut yet - open this screen from the sidebar or menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(manager.filteredHistory) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.text).lineLimit(2)
                        Text(entry.date.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(entry.pinned ? "Unpin" : "Pin") { manager.togglePin(entry) }
                    Button("Copy") { manager.copyToPasteboard(entry) }
                    Button("Remove") { manager.remove(entry) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
