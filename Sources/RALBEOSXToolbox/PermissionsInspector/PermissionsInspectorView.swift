import SwiftUI

struct PermissionsInspectorView: View {
    @ObservedObject var manager: PermissionsInspectorManager

    private var groupedByClient: [(client: String, grants: [PermissionGrant])] {
        Dictionary(grouping: manager.grants, by: { $0.client })
            .map { (client: $0.key, grants: $0.value) }
            .sorted { $0.client.localizedCaseInsensitiveCompare($1.client) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Permissions Inspector").font(.title2).bold()
                Spacer()
                Button("Refresh") { manager.refresh() }
            }

            if let error = manager.lastError {
                Text(error).foregroundStyle(.orange)
            }

            List {
                ForEach(groupedByClient, id: \.client) { group in
                    Section(group.client) {
                        ForEach(group.grants) { grant in
                            HStack {
                                Text(PermissionsInspectorManager.serviceDisplayName(grant.service))
                                Spacer()
                                Text(PermissionsInspectorManager.authDescription(grant.authValue))
                                    .foregroundStyle(grant.authValue == 2 ? .green : (grant.authValue == 0 ? .red : .secondary))
                                Button("Settings…") { manager.openSettings(for: grant.service) }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { manager.refresh() }
    }
}
