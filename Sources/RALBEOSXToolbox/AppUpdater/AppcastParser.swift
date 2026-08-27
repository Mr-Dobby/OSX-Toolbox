import Foundation

/// One item parsed from a Sparkle appcast XML feed.
struct AppcastItem {
    var version: String?
    var shortVersionString: String?
    var enclosureURL: URL?
    var enclosureType: String?
    var description: String?
}

/// Minimal Sparkle appcast (RSS + sparkle: namespace) parser. Namespace
/// resolution is left off (`shouldProcessNamespaces = false`, the default),
/// so attribute/element names arrive as raw strings like "sparkle:version".
final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [AppcastItem] = []
    private var currentItem: AppcastItem?
    private var currentElement = ""
    private var currentText = ""

    /// Returns the first `<item>` in the feed - appcasts list newest first.
    func parseLatestItem(data: Data) -> AppcastItem? {
        items = []
        currentItem = nil
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return items.first
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""
        if elementName == "item" {
            currentItem = AppcastItem()
        } else if elementName == "enclosure" {
            currentItem?.enclosureURL = attributeDict["url"].flatMap { URL(string: $0) }
            currentItem?.enclosureType = attributeDict["type"]
            if let v = attributeDict["sparkle:shortVersionString"] { currentItem?.shortVersionString = v }
            if let v = attributeDict["sparkle:version"] { currentItem?.version = v }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "sparkle:shortVersionString":
            if !text.isEmpty { currentItem?.shortVersionString = text }
        case "sparkle:version":
            if !text.isEmpty { currentItem?.version = text }
        case "description":
            if !text.isEmpty { currentItem?.description = text }
        case "item":
            if let item = currentItem { items.append(item) }
            currentItem = nil
        default:
            break
        }
    }
}

/// Compares dot-separated numeric version strings component by component.
enum VersionComparator {
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = components(a)
        let pb = components(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}
