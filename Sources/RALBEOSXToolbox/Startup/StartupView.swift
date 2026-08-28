import SwiftUI

struct StartupView: View {
    @ObservedObject var manager: StartupManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(manager.items.count) things can start automatically").font(.title2).bold()
                Spacer()
                Button("Add App to Login Items…") { manager.pickAppToAddAsLoginItem() }
                Button("Refresh") { manager.refresh() }
            }
            Text("System-scoped items may prompt for your admin password to disable/remove; Login Items never need it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(manager.items) { item in
                HStack {
                    VStack(alignment: .leading) {
                        Text(item.label)
                        Text(item.scope).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reveal") { manager.reveal(item) }
                        .disabled(item.scope == "Login Item")
                    Toggle("", isOn: Binding(get: { item.enabled }, set: { _ in manager.toggle(item) }))
                        .labelsHidden()
                        .disabled(item.scope == "Login Item")
                    Button("Remove", role: .destructive) { manager.remove(item) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { manager.refresh() }
    }
}
