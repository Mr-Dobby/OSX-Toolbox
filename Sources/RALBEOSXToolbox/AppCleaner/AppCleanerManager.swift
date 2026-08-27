import AppKit

func directorySize(_ path: String) -> Int64 {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue {
        let attrs = try? fm.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? 0
    }
    var total: Int64 = 0
    if let enumerator = fm.enumerator(atPath: path) {
        for case let file as String in enumerator {
            let full = "\(path)/\(file)"
            if let attrs = try? fm.attributesOfItem(atPath: full), let size = attrs[.size] as? Int64 {
                total += size
            }
        }
    }
    return total
}

final class AppCleanEntry: NSObject {
    let path: String
    let size: Int64
    var selected: Bool
    init(path: String, size: Int64, selected: Bool = true) {
        self.path = path
        self.size = size
        self.selected = selected
    }
}

final class AppCleanWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var entries: [AppCleanEntry] = []
    var tableView: NSTableView!

    convenience init(appName: String, entries: [AppCleanEntry]) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
                               styleMask: [.titled, .closable, .resizable],
                               backing: .buffered, defer: false)
        window.title = "App Clean — \(appName)"
        window.center()
        self.init(window: window)
        self.entries = entries
        buildUI()
    }

    func buildUI() {
        guard let window = window, let contentView = window.contentView else { return }

        let scroll = NSScrollView(frame: NSRect(x: 12, y: 56, width: 536, height: 340))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true

        let table = NSTableView(frame: scroll.bounds)
        table.usesAlternatingRowBackgroundColors = true

        let checkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkColumn.title = ""
        checkColumn.width = 30
        table.addTableColumn(checkColumn)

        let pathColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        pathColumn.title = "Path"
        pathColumn.width = 400
        table.addTableColumn(pathColumn)

        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("size"))
        sizeColumn.title = "Size"
        sizeColumn.width = 90
        table.addTableColumn(sizeColumn)

        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        contentView.addSubview(scroll)
        tableView = table

        let selectAllButton = NSButton(title: "Select All", target: self, action: #selector(selectAllEntries))
        selectAllButton.frame = NSRect(x: 12, y: 12, width: 90, height: 30)
        contentView.addSubview(selectAllButton)

        let deselectAllButton = NSButton(title: "Deselect All", target: self, action: #selector(deselectAllEntries))
        deselectAllButton.frame = NSRect(x: 108, y: 12, width: 100, height: 30)
        contentView.addSubview(deselectAllButton)

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 340, y: 12, width: 90, height: 30)
        contentView.addSubview(cancel)

        let trash = NSButton(title: "Move to Trash", target: self, action: #selector(moveToTrash))
        trash.frame = NSRect(x: 436, y: 12, width: 112, height: 30)
        trash.keyEquivalent = "\r"
        contentView.addSubview(trash)

        table.reloadData()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        guard let id = tableColumn?.identifier.rawValue else { return nil }
        switch id {
        case "check":
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(checkboxToggled(_:)))
            button.state = entry.selected ? .on : .off
            button.tag = row
            return button
        case "path":
            let field = NSTextField(labelWithString: entry.path)
            field.lineBreakMode = .byTruncatingMiddle
            return field
        default:
            return NSTextField(labelWithString: ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
        }
    }

    @objc func checkboxToggled(_ sender: NSButton) {
        entries[sender.tag].selected = (sender.state == .on)
    }

    @objc func selectAllEntries() { entries.forEach { $0.selected = true }; tableView.reloadData() }
    @objc func deselectAllEntries() { entries.forEach { $0.selected = false }; tableView.reloadData() }
    @objc func cancel() { window?.close() }

    @objc func moveToTrash() {
        let selected = entries.filter { $0.selected }
        guard !selected.isEmpty else { window?.close(); return }
        let urls = selected.map { URL(fileURLWithPath: $0.path) }
        NSWorkspace.shared.recycle(urls) { _, error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error = error {
                    alert.messageText = "Some items could not be removed"
                    alert.informativeText = error.localizedDescription
                } else {
                    alert.messageText = "Moved \(urls.count) item(s) to Trash"
                }
                alert.runModal()
            }
        }
        window?.close()
    }
}

/// Finds and offers to remove leftover cache/log/support files for an
/// uninstalled (or about-to-be-removed) app. Ported from CaffeineInjection's
/// "App Clean" feature.
@MainActor
final class AppCleanerManager: NSObject, ObservableObject {
    static let shared = AppCleanerManager()

    private var windowController: AppCleanWindowController?

    @Published private(set) var hasFullDiskAccess = SystemPermissions.hasFullDiskAccess()

    func refreshFullDiskAccess() {
        hasFullDiskAccess = SystemPermissions.hasFullDiskAccess()
    }

    func pickAndClean() {
        refreshFullDiskAccess()
        if !hasFullDiskAccess { SystemPermissions.promptFullDiskAccess() }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Clean"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runAppClean(for: url)
    }

    private func runAppClean(for appURL: URL) {
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier ?? ""
        let appName = appURL.deletingPathExtension().lastPathComponent
        let needles = [bundleID.lowercased(), appName.lowercased()].filter { !$0.isEmpty }

        let home = NSHomeDirectory()
        let searchRoots = [
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support",
            "\(home)/Library/Preferences",
            "\(home)/Library/Preferences/ByHost",
            "\(home)/Library/Logs",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/WebKit",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Cookies",
            "\(home)/Library/LaunchAgents",
            "/Library/Caches",
            "/Library/Application Support",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
        ]

        var matches: [AppCleanEntry] = []
        let fm = FileManager.default
        for root in searchRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items {
                let lower = item.lowercased()
                if needles.contains(where: { lower.contains($0) }) {
                    let fullPath = "\(root)/\(item)"
                    matches.append(AppCleanEntry(path: fullPath, size: directorySize(fullPath)))
                }
            }
        }
        matches.append(AppCleanEntry(path: appURL.path, size: directorySize(appURL.path)))

        guard !matches.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Leftover Files Found"
            alert.informativeText = "No cache, log, or support files were found for \(appName)."
            alert.runModal()
            return
        }

        let controller = AppCleanWindowController(appName: appName, entries: matches)
        windowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
