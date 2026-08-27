import SwiftUI

struct WindowManagerView: View {
    @ObservedObject var manager: WindowManagerService

    private let columns = [GridItem(.adaptive(minimum: 150))]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Window Manager").font(.title2).bold()
            Text("Applies to whatever window is currently frontmost. Requires Accessibility access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(WindowManagerService.Placement.allCases) { placement in
                    Button(placement.rawValue) { manager.apply(placement) }
                        .frame(maxWidth: .infinity)
                }
            }

            Button("Move to Next Display") { manager.moveToNextDisplay() }

            Text("Not implemented: moving windows to a specific Space (no public API) and remembering/restoring window positions.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
