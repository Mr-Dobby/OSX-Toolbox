import SwiftUI

struct ProcessMonitorView: View {
    @ObservedObject var manager: ProcessMonitorManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Process Monitor").font(.title2).bold()
                Spacer()
                Button("Refresh") { manager.refresh() }
            }

            List(manager.processes) { item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(String(format: "CPU %.1f%%", item.cpu)).frame(width: 90, alignment: .trailing)
                    Text(String(format: "MEM %.1f%%", item.memPercent)).frame(width: 90, alignment: .trailing)
                    Button("Reveal") { manager.reveal(item) }
                    Button("Search Web") { manager.searchWeb(item) }
                    Button("Quit") { manager.quit(item) }
                    Button("Force Quit") { manager.forceQuit(item) }
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
