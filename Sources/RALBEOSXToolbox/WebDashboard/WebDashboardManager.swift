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
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(clientSocket, &buffer, buffer.count, 0)
        guard bytesRead > 0 else { return }
        let request = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
        let path = requestPath(from: request)

        let responseBody: String
        let contentType: String
        if path == "/stats" {
            responseBody = DeviceStatsSnapshot.currentJSON()
            contentType = "application/json"
        } else {
            responseBody = dashboardHTMLPage
            contentType = "text/html; charset=utf-8"
        }

        let response = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(responseBody.utf8.count)\r\nConnection: close\r\n\r\n\(responseBody)"
        response.withCString { ptr in
            _ = send(clientSocket, ptr, strlen(ptr), 0)
        }
    }

    nonisolated private static func requestPath(from request: String) -> String {
        guard let firstLine = request.split(separator: "\r\n").first else { return "/" }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "/" }
        return String(parts[1])
    }
}
