import SwiftUI

struct DiskAnalyzerView: View {
    @ObservedObject var manager: DiskAnalyzerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Disk Space Analyzer").font(.title2).bold()
                Spacer()
                Picker("Sort", selection: $manager.sortOption) {
                    ForEach(DiskAnalyzerManager.SortOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 220)
                Button("Choose Folders…") { manager.pickFolderAndScan() }
                Button("Scan Home Folder") { manager.scanHomeFolder() }
                Button("Scan Applications") { manager.scanApplicationsFolder() }
                Button("Scan Logs & Caches") { manager.scanLogsAndCaches() }
            }

            Text(manager.currentPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if manager.isScanning {
                ProgressView("Scanning…").frame(maxWidth: .infinity, alignment: .center)
            }

            List(manager.sortedItems) { item in
                HStack {
                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                        .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                    VStack(alignment: .leading) {
                        Text(item.url.lastPathComponent)
                        if let date = item.modificationDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                        .foregroundStyle(.secondary)
                    Button("Reveal") { manager.reveal(item) }
                    Button("Trash") { manager.moveToTrash(item) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
