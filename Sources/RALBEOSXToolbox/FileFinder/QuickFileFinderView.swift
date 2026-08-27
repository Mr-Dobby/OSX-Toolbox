import SwiftUI

struct QuickFileFinderView: View {
    @ObservedObject var manager: QuickFileFinderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick File Finder").font(.title2).bold()

            HStack {
                TextField("Search filenames and file contents…", text: $manager.query, onCommit: { manager.search() })
                    .textFieldStyle(.roundedBorder)
                Button("Search") { manager.search() }
                Picker("Sort", selection: $manager.sortOption) {
                    ForEach(QuickFileFinderManager.SortOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 180)
                Toggle("Large files only (>100MB)", isOn: $manager.largeFilesOnly)
            }

            if manager.isSearching { ProgressView("Searching…") }

            List(manager.results, id: \.self) { url in
                HStack {
                    VStack(alignment: .leading) {
                        Text(url.lastPathComponent)
                        Text(url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Open") { manager.open(url) }
                    Button("Reveal") { manager.reveal(url) }
                    Button("Copy Path") { manager.copyPath(url) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
