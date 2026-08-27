import SwiftUI

struct WebDashboardView: View {
    @ObservedObject var manager: WebDashboardManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Web Dashboard").font(.title2).bold()
            Text("Live CPU, memory, disk, battery, network, and process stats rendered as a small local web page.")
                .foregroundStyle(.secondary)

            HStack {
                Circle()
                    .fill(manager.isRunning ? Color.green : Color.secondary)
                    .frame(width: 10, height: 10)
                Text(manager.isRunning ? "Running at http://127.0.0.1:\(manager.port)/" : "Stopped")
            }

            if let lanURL = manager.lanURL {
                HStack {
                    Text("On your network: \(lanURL)").font(.caption).foregroundStyle(.secondary)
                    Button("Copy") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(lanURL, forType: .string)
                    }
                }
            }

            HStack {
                Stepper("Port: \(manager.port)", value: Binding(
                    get: { Int(manager.port) },
                    set: { manager.port = UInt16(clamping: $0) }
                ), in: 1024...65535)
                .disabled(manager.isRunning)
                .frame(width: 200)

                Button(manager.isRunning ? "Stop Server" : "Start Server") {
                    manager.isRunning ? manager.stop() : manager.start()
                }
                Button("Open in Browser") { manager.openInBrowser() }
            }

            Toggle("Allow access from other devices on this network", isOn: $manager.allowLANAccess)
            if manager.allowLANAccess {
                Text("⚠️ The dashboard has no login or password - anyone on this network can view these stats while it's running. Only enable this on networks you trust.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("Off by default: only this Mac can open the dashboard, via 127.0.0.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = manager.lastError {
                Text(error).foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

