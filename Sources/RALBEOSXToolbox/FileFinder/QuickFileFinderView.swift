import SwiftUI

struct QuickFileFinderView: View {
    @ObservedObject var manager: QuickFileFinderManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick File Finder").font(.title2).bold()

            HStack {
                TextField("Search filenames/contents, or a wildcard like *.js or *test*…", text: $manager.query, onCommit: { manager.search() })
                    .textFieldStyle(.roundedBorder)
                Button("Search") { manager.search() }
                Picker("Sort", selection: $manager.sortOption) {
                    ForEach(QuickFileFinderManager.SortOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 180)
                Toggle("Large files only (>100MB)", isOn: $manager.largeFilesOnly)
            }

            Text("Use * to match any run of characters and ? for a single character (e.g. *.js for all JS files, *test* for anything with \"test\" in the name) - wildcard searches match filenames only, not file contents.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
