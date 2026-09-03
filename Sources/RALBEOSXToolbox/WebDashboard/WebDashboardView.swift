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

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("LAN File Transfers").font(.headline)
                Text("Select files or folders to send. Each transfer is bundled, then the receiver approves it once before anything is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable receiving files", isOn: Binding(
                    get: { manager.isReceivingFiles },
                    set: { enabled in
                        enabled ? manager.enableReceivingFiles() : manager.disableReceivingFiles()
                    }
                ))
                if manager.isReceivingFiles {
                    Text("Received transfers are extracted into ~/.osxtoolbox/")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                HStack {
                    Button(manager.isScanningForPeers ? "Scanning…" : "Scan for Receiving Devices") {
                        manager.scanForTransferPeers()
                    }
                    .disabled(manager.isScanningForPeers)
                    Text("Both devices need a running server with network access enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !manager.discoveredPeers.isEmpty {
                    GroupBox("Available Receivers") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(manager.discoveredPeers) { peer in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(peer.hostName)
                                        Text("\(peer.ipAddress):\(peer.port)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Send Files or Folders…") { manager.chooseItemsToSend(to: peer) }
                                }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                if !manager.incomingTransfers.isEmpty {
                    GroupBox("Incoming Transfer Requests") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(manager.incomingTransfers) { transfer in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("From \(transfer.senderName) (\(transfer.senderIP))").font(.subheadline).bold()
                                    Text("\(transfer.itemNames.joined(separator: ", ")) · \(ByteCountFormatter.string(fromByteCount: transfer.byteCount, countStyle: .file))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(transfer.message ?? transfer.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                    if transfer.status == .pending {
                                        HStack {
                                            Button("Approve") { manager.approveIncomingTransfer(id: transfer.id) }
                                            Button("Decline", role: .destructive) { manager.declineIncomingTransfer(id: transfer.id) }
                                        }
                                    }
                                }
                                if transfer.id != manager.incomingTransfers.last?.id { Divider() }
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                if !manager.outgoingTransfers.isEmpty {
                    GroupBox("Outgoing Transfers") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(manager.outgoingTransfers) { transfer in
                                Text("\(transfer.itemNames.joined(separator: ", ")) → \(transfer.recipientName): \(transfer.message ?? transfer.status.rawValue)")
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
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

