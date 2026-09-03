import AppKit
import Darwin

/// A minimal raw-socket HTTP/1.1 server for the "open a live stats
/// dashboard in your browser" feature. Bound to 127.0.0.1 ONLY by default -
/// never reachable off this Mac - unless the user explicitly opts in to
/// `allowLANAccess`, which binds 0.0.0.0 instead so other devices on the
/// same network can reach it via this Mac's LAN IP. There is still no
/// authentication of any kind, so LAN access should only be enabled on
/// networks you trust. Serves two routes: `/` (the HTML page) and `/stats`
/// (a JSON snapshot polled by that page's JS every 2s).
@MainActor
final class WebDashboardManager: ObservableObject {
    static let shared = WebDashboardManager()

    @Published var isRunning = false
    @Published var port: UInt16 = 17321
    @Published var lastError: String?
    @Published var isReceivingFiles: Bool {
        didSet {
            UserDefaults.standard.set(isReceivingFiles, forKey: "webdash.receiveFiles")
            if isReceivingFiles { createReceiveDirectoryIfNeeded() }
        }
    }
    @Published private(set) var discoveredPeers: [LANTransferPeer] = []
    @Published private(set) var incomingTransfers: [IncomingLANTransfer] = []
    @Published private(set) var outgoingTransfers: [OutgoingLANTransfer] = []
    @Published private(set) var isScanningForPeers = false
    @Published var allowLANAccess: Bool {
        didSet {
            UserDefaults.standard.set(allowLANAccess, forKey: "webdash.allowLAN")
            if isRunning { restart() }
        }
    }

    private var serverSocket: Int32 = -1
    private var acceptThread: Thread?
    private var shouldStop = false

    private init() {
        allowLANAccess = UserDefaults.standard.bool(forKey: "webdash.allowLAN")
        isReceivingFiles = UserDefaults.standard.bool(forKey: "webdash.receiveFiles")
    }

    /// The address a browser on another device should use, if LAN access is
    /// on and a routable IPv4 address could be found.
    var lanURL: String? {
        guard allowLANAccess, let ip = ipv4Addresses().first(where: { $0 != "127.0.0.1" }) else { return nil }
        return "http://\(ip):\(port)/"
    }

    func start() {
        guard !isRunning else { return }
        lastError = nil
        shouldStop = false

        let bindAddress = allowLANAccess ? "0.0.0.0" : "127.0.0.1"

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else {
            lastError = "Could not create socket."
            return
        }

        var reuse: Int32 = 1
        setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr(bindAddress)

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            lastError = "Could not bind to \(bindAddress):\(port) (port already in use?)."
            close(sock)
            return
        }
        guard listen(sock, 8) == 0 else {
            lastError = "Could not listen on socket."
            close(sock)
            return
        }

        serverSocket = sock
        isRunning = true

        let thread = Thread { [weak self] in
            self?.acceptLoop(serverSocket: sock)
        }
        thread.name = "RALBEOSXToolbox.WebDashboard"
        thread.start()
        acceptThread = thread
    }

    func stop() {
        guard isRunning else { return }
        shouldStop = true
        if serverSocket >= 0 { close(serverSocket) }
        serverSocket = -1
        isRunning = false
    }

    private func restart() {
        stop()
        start()
    }

    func openInBrowser() {
        if !isRunning { start() }
        guard let url = URL(string: "http://127.0.0.1:\(port)/") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Enables receiver mode and creates the fixed local destination on first use.
    func enableReceivingFiles() {
        guard allowLANAccess, isRunning else {
            lastError = "Start the server and enable network access before receiving files."
            return
        }
        isReceivingFiles = true
    }

    func disableReceivingFiles() {
        isReceivingFiles = false
    }

    func scanForTransferPeers() {
        guard allowLANAccess, isRunning else {
            lastError = "Start the server and enable network access before scanning for devices."
            return
        }
        guard let localIP = ipv4Addresses().first(where: { $0 != "127.0.0.1" }),
              let lastDot = localIP.lastIndex(of: ".") else {
            lastError = "Could not determine this Mac's local IPv4 network."
            return
        }

        isScanningForPeers = true
        discoveredPeers = []
        let prefix = String(localIP[...lastDot])
        let dashboardPort = port
        DispatchQueue.global(qos: .userInitiated).async {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 0.45
            configuration.timeoutIntervalForResource = 0.6
            let session = URLSession(configuration: configuration)
            let group = DispatchGroup()
            let lock = NSLock()
            let limit = DispatchSemaphore(value: 24)
            var peers: [LANTransferPeer] = []

            for host in 1...254 {
                let ip = "\(prefix)\(host)"
                guard ip != localIP else { continue }
                limit.wait()
                group.enter()
                let url = URL(string: "http://\(ip):\(dashboardPort)/transfer/capabilities")!
                session.dataTask(with: url) { data, _, _ in
                    defer { limit.signal(); group.leave() }
                    guard let data,
                          let capability = try? JSONDecoder().decode(TransferCapabilityResponse.self, from: data),
                          capability.receivingEnabled else { return }
                    lock.lock()
                    peers.append(LANTransferPeer(hostName: capability.hostName, ipAddress: ip, port: capability.port))
                    lock.unlock()
                }.resume()
            }
            group.wait()
            session.invalidateAndCancel()
            Task { @MainActor in
                self.discoveredPeers = peers.sorted { $0.hostName.localizedCaseInsensitiveCompare($1.hostName) == .orderedAscending }
                self.isScanningForPeers = false
                if peers.isEmpty { self.lastError = "No receivers were found on this network." }
            }
        }
    }

    func chooseItemsToSend(to peer: LANTransferPeer) {
        guard allowLANAccess, isRunning else {
            lastError = "Start the server and enable network access before sending files."
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Choose files and folders to send to \(peer.hostName)"
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        let transferID = UUID().uuidString
        outgoingTransfers.append(OutgoingLANTransfer(id: transferID, recipientName: peer.hostName, recipientIP: peer.ipAddress, itemNames: urls.map(\.lastPathComponent), status: .awaitingApproval, message: "Preparing transfer…"))
        DispatchQueue.global(qos: .userInitiated).async {
            self.prepareRequestAndUpload(id: transferID, items: urls, peer: peer)
        }
    }

    func approveIncomingTransfer(id: String) {
        guard let index = incomingTransfers.firstIndex(where: { $0.id == id }) else { return }
        incomingTransfers[index].status = .approved
        incomingTransfers[index].message = "The sender may now upload this transfer."
    }

    func declineIncomingTransfer(id: String) {
        guard let index = incomingTransfers.firstIndex(where: { $0.id == id }) else { return }
        incomingTransfers[index].status = .declined
        incomingTransfers[index].message = "Declined by receiver."
    }

    private func handleControlRequest(method: String, path: String, body: Data) -> HTTPResult {
        if method == "GET" && path == "/" {
            return HTTPResult(status: 200, body: Data(dashboardHTMLPage.utf8), contentType: "text/html; charset=utf-8")
        }
        if method == "GET" && path == "/stats" {
            return HTTPResult(status: 200, body: Data(DeviceStatsSnapshot.currentJSON().utf8), contentType: "application/json")
        }
        if method == "GET" && path == "/transfer/capabilities" {
            let response = TransferCapabilityResponse(receivingEnabled: allowLANAccess && isRunning && isReceivingFiles, hostName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName, port: port)
            return jsonResult(response)
        }
        if method == "POST" && path == "/transfer/request" {
            guard allowLANAccess, isReceivingFiles,
                  let request = try? JSONDecoder().decode(TransferRequestPayload.self, from: body),
                  request.byteCount > 0, request.byteCount <= 4_294_967_296,
                  !request.itemNames.isEmpty, !request.archiveName.isEmpty else {
                return HTTPResult(status: 403, body: Data("Receiving is disabled or request is invalid.".utf8), contentType: "text/plain")
            }
            let id = UUID().uuidString
            incomingTransfers.append(IncomingLANTransfer(id: id, senderName: request.senderName, senderIP: request.senderIP, itemNames: request.itemNames, archiveName: request.archiveName, byteCount: request.byteCount, status: .pending, message: nil))
            return jsonResult(TransferRequestResponse(requestID: id), status: 201)
        }
        if method == "GET", path.hasPrefix("/transfer/request/") {
            let id = String(path.dropFirst("/transfer/request/".count))
            guard let transfer = incomingTransfers.first(where: { $0.id == id }) else {
                return HTTPResult(status: 400, body: Data("Unknown transfer.".utf8), contentType: "text/plain")
            }
            let status: String
            switch transfer.status {
            case .approved, .receiving, .extracting, .completed: status = "approved"
            case .declined: status = "declined"
            case .failed: status = "failed"
            case .pending: status = "pending"
            }
            return jsonResult(TransferRequestStatusResponse(status: status))
        }
        return HTTPResult(status: 400, body: Data("Unknown route.".utf8), contentType: "text/plain")
    }

    private func jsonResult<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResult {
        let body = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResult(status: status, body: body, contentType: "application/json")
    }

    private func beginUpload(id: String, byteCount: Int64) -> URL? {
          guard allowLANAccess, isReceivingFiles,
              let index = incomingTransfers.firstIndex(where: { $0.id == id }),
              incomingTransfers[index].status == .approved,
              incomingTransfers[index].byteCount == byteCount else { return nil }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("RALBETransfer-\(id).zip")
        try? FileManager.default.removeItem(at: temporary)
        incomingTransfers[index].status = .receiving
        incomingTransfers[index].message = "Receiving \(byteCount.formatted()) bytes…"
        return temporary
    }

    private func finishUpload(id: String, archiveURL: URL) {
        guard let index = incomingTransfers.firstIndex(where: { $0.id == id }) else { return }
        incomingTransfers[index].status = .extracting
        incomingTransfers[index].message = "Extracting into ~/.osxtoolbox…"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.extractReceivedArchive(archiveURL, transferID: id)
            Task { @MainActor in
                guard let current = self.incomingTransfers.firstIndex(where: { $0.id == id }) else { return }
                self.incomingTransfers[current].status = result == nil ? .completed : .failed
                self.incomingTransfers[current].message = result ?? "Saved in ~/.osxtoolbox"
            }
        }
    }

    private func failIncomingTransfer(id: String, message: String) {
        guard let index = incomingTransfers.firstIndex(where: { $0.id == id }) else { return }
        incomingTransfers[index].status = .failed
        incomingTransfers[index].message = message
    }

    private func createReceiveDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: receiveDirectory, withIntermediateDirectories: true)
    }

    private var receiveDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".osxtoolbox", isDirectory: true)
    }

    nonisolated private static func extractReceivedArchive(_ archiveURL: URL, transferID: String) -> String? {
        let destination = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".osxtoolbox", isDirectory: true).appendingPathComponent("Transfer-\(transferID.prefix(8))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archiveURL.path, destination.path]
            try process.run()
            process.waitUntilExit()
            try FileManager.default.removeItem(at: archiveURL)
            if process.terminationStatus == 0 { return nil }
            try? FileManager.default.removeItem(at: destination)
            return "Could not extract the received archive."
        } catch {
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: destination)
            return "Could not save the received transfer: \(error.localizedDescription)"
        }
    }

    nonisolated private func prepareRequestAndUpload(id: String, items: [URL], peer: LANTransferPeer) {
        do {
            let archive = try Self.createTransferArchive(items: items, id: id)
            defer { try? FileManager.default.removeItem(at: archive) }
            let size = (try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            guard size > 0 else { throw CocoaError(.fileReadUnknown) }
            let senderIP = ipv4Addresses().first(where: { $0 != "127.0.0.1" }) ?? "Unknown"
            let request = TransferRequestPayload(senderName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName, senderIP: senderIP, itemNames: items.map(\.lastPathComponent), archiveName: archive.lastPathComponent, byteCount: size)
            let requestData = try JSONEncoder().encode(request)
            var requestURL = URLRequest(url: URL(string: "http://\(peer.ipAddress):\(peer.port)/transfer/request")!)
            requestURL.httpMethod = "POST"
            requestURL.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requestURL.httpBody = requestData
            let (data, response) = Self.syncDataTask(requestURL)
            guard (response as? HTTPURLResponse)?.statusCode == 201,
                  let data, let responseID = try? JSONDecoder().decode(TransferRequestResponse.self, from: data).requestID else {
                        throw URLError(.networkConnectionLost)
            }
            Self.updateOutgoing(id: id, status: .awaitingApproval, message: "Waiting for \(peer.hostName) to approve…")
            guard Self.waitForApproval(id: responseID, peer: peer) else {
                Self.updateOutgoing(id: id, status: .declined, message: "The receiver declined or did not approve the request.")
                return
            }
            Self.updateOutgoing(id: id, status: .uploading, message: "Uploading…")
            var upload = URLRequest(url: URL(string: "http://\(peer.ipAddress):\(peer.port)/transfer/upload")!)
            upload.httpMethod = "POST"
            upload.setValue(responseID, forHTTPHeaderField: "X-Transfer-ID")
            upload.setValue("application/zip", forHTTPHeaderField: "Content-Type")
            let (_, uploadResponse) = Self.syncUploadTask(upload, fileURL: archive)
            guard (uploadResponse as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.networkConnectionLost) }
            Self.updateOutgoing(id: id, status: .completed, message: "Sent to \(peer.hostName).")
        } catch {
            Self.updateOutgoing(id: id, status: .failed, message: "Transfer failed: \(error.localizedDescription)")
        }
    }

    nonisolated private static func createTransferArchive(items: [URL], id: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RALBETransfer-\(id)", isDirectory: true)
        let contents = root.appendingPathComponent("Contents", isDirectory: true)
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("RALBETransfer-\(id).zip")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        for item in items {
            var target = contents.appendingPathComponent(item.lastPathComponent)
            var suffix = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = contents.appendingPathComponent("\(item.deletingPathExtension().lastPathComponent) \(suffix).\(item.pathExtension)")
                suffix += 1
            }
            try FileManager.default.copyItem(at: item, to: target)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", root.path, archive.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return archive
    }

    nonisolated private static func waitForApproval(id: String, peer: LANTransferPeer) -> Bool {
        for _ in 0..<120 {
            let url = URL(string: "http://\(peer.ipAddress):\(peer.port)/transfer/request/\(id)")!
            let (data, response) = syncDataTask(URLRequest(url: url))
            if (response as? HTTPURLResponse)?.statusCode == 200,
               let data, let status = try? JSONDecoder().decode(TransferRequestStatusResponse.self, from: data).status {
                if status == "approved" { return true }
                if status == "declined" || status == "failed" { return false }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        return false
    }

    nonisolated private static func syncDataTask(_ request: URLRequest) -> (Data?, URLResponse?) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?) = (nil, nil)
        URLSession.shared.dataTask(with: request) { data, response, _ in result = (data, response); semaphore.signal() }.resume()
        semaphore.wait()
        return result
    }

    nonisolated private static func syncUploadTask(_ request: URLRequest, fileURL: URL) -> (Data?, URLResponse?) {
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data?, URLResponse?) = (nil, nil)
        URLSession.shared.uploadTask(with: request, fromFile: fileURL) { data, response, _ in result = (data, response); semaphore.signal() }.resume()
        semaphore.wait()
        return result
    }

    nonisolated private static func updateOutgoing(id: String, status: OutgoingLANTransfer.Status, message: String) {
        Task { @MainActor in
            guard let index = WebDashboardManager.shared.outgoingTransfers.firstIndex(where: { $0.id == id }) else { return }
            WebDashboardManager.shared.outgoingTransfers[index].status = status
            WebDashboardManager.shared.outgoingTransfers[index].message = message
        }
    }

    // Runs on a background thread for the lifetime of the server.
    nonisolated private func acceptLoop(serverSocket: Int32) {
        while true {
            var clientAddr = sockaddr()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr>.size)
            let clientSocket = accept(serverSocket, &clientAddr, &clientAddrLen)
            if clientSocket < 0 { break }
            Self.handleClient(clientSocket)
        }
    }

    nonisolated private static func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }
        guard let parsed = readRequestHead(clientSocket) else { return }
        let contentLength = Int(parsed.headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0, contentLength <= 4_294_967_296 else {
            sendResponse(clientSocket, status: 413, body: Data("Request is too large.".utf8), contentType: "text/plain")
            return
        }

        if parsed.path == "/transfer/upload" && parsed.method == "POST" {
            handleUpload(clientSocket, parsed: parsed, contentLength: contentLength)
            return
        }

        guard contentLength <= 512_000, let body = readBody(clientSocket, initial: parsed.initialBody, contentLength: contentLength) else {
            sendResponse(clientSocket, status: 400, body: Data("Invalid request body.".utf8), contentType: "text/plain")
            return
        }
        let result: HTTPResult = onMainActor {
            WebDashboardManager.shared.handleControlRequest(method: parsed.method, path: parsed.path, body: body)
        }
        sendResponse(clientSocket, status: result.status, body: result.body, contentType: result.contentType)
    }

    nonisolated private static func requestPath(from request: String) -> String {
        guard let firstLine = request.split(separator: "\r\n").first else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }

    private struct HTTPResult {
        let status: Int
        let body: Data
        let contentType: String
    }

    private struct ParsedRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let initialBody: Data
    }

    nonisolated private static func readRequestHead(_ socket: Int32) -> ParsedRequest? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count < 65_536 {
            let received = recv(socket, &buffer, buffer.count, 0)
            guard received > 0 else { return nil }
            data.append(buffer, count: received)
            if let range = data.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: data[..<range.lowerBound], encoding: .utf8) ?? ""
                let lines = head.components(separatedBy: "\r\n")
                guard let first = lines.first else { return nil }
                let parts = first.split(separator: " ")
                guard parts.count >= 2 else { return nil }
                var headers: [String: String] = [:]
                for line in lines.dropFirst() {
                    guard let colon = line.firstIndex(of: ":") else { continue }
                    headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
                return ParsedRequest(method: String(parts[0]), path: String(parts[1]).components(separatedBy: "?").first ?? "/", headers: headers, initialBody: Data(data[range.upperBound...]))
            }
        }
        return nil
    }

    nonisolated private static func readBody(_ socket: Int32, initial: Data, contentLength: Int) -> Data? {
        guard initial.count <= contentLength else { return nil }
        var body = initial
        var buffer = [UInt8](repeating: 0, count: 8192)
        while body.count < contentLength {
            let received = recv(socket, &buffer, min(buffer.count, contentLength - body.count), 0)
            guard received > 0 else { return nil }
            body.append(buffer, count: received)
        }
        return body
    }

    nonisolated private static func handleUpload(_ socket: Int32, parsed: ParsedRequest, contentLength: Int) {
        guard let id = parsed.headers["x-transfer-id"], !id.isEmpty else {
            sendResponse(socket, status: 400, body: Data("Missing transfer ID.".utf8), contentType: "text/plain")
            return
        }
        let destination: URL? = onMainActor { WebDashboardManager.shared.beginUpload(id: id, byteCount: Int64(contentLength)) }
        guard let destination else {
            sendResponse(socket, status: 403, body: Data("Transfer is not approved.".utf8), contentType: "text/plain")
            return
        }
        guard parsed.initialBody.count <= contentLength else {
            onMainActor { WebDashboardManager.shared.failIncomingTransfer(id: id, message: "Upload request was malformed.") }
            sendResponse(socket, status: 400, body: Data("Invalid upload body.".utf8), contentType: "text/plain")
            return
        }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else {
            sendResponse(socket, status: 500, body: Data("Could not create transfer file.".utf8), contentType: "text/plain")
            return
        }
        defer { try? handle.close() }
        do {
            try handle.write(contentsOf: parsed.initialBody)
            var remaining = contentLength - parsed.initialBody.count
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while remaining > 0 {
                let received = recv(socket, &buffer, min(buffer.count, remaining), 0)
                guard received > 0 else { throw CocoaError(.fileReadUnknown) }
                try handle.write(contentsOf: Data(buffer[0..<received]))
                remaining -= received
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            onMainActor { WebDashboardManager.shared.failIncomingTransfer(id: id, message: "Upload was interrupted.") }
            sendResponse(socket, status: 400, body: Data("Upload failed.".utf8), contentType: "text/plain")
            return
        }
        onMainActor { WebDashboardManager.shared.finishUpload(id: id, archiveURL: destination) }
        sendResponse(socket, status: 200, body: Data("Received.".utf8), contentType: "text/plain")
    }

    nonisolated private static func sendResponse(_ socket: Int32, status: Int, body: Data, contentType: String) {
        let reason = status == 200 ? "OK" : status == 201 ? "Created" : status == 403 ? "Forbidden" : status == 413 ? "Payload Too Large" : "Bad Request"
        let header = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        sendData(socket, header)
        sendData(socket, body)
    }

    nonisolated private static func sendData(_ socket: Int32, _ data: Data) {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var remaining = data.count
            while remaining > 0 {
                let sent = send(socket, pointer, remaining, 0)
                guard sent > 0 else { return }
                remaining -= sent
                pointer = pointer.advanced(by: sent)
            }
        }
    }

    nonisolated private static func onMainActor<T>(_ action: @escaping @MainActor () -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T!
        Task { @MainActor in result = action(); semaphore.signal() }
        semaphore.wait()
        return result
    }
}
