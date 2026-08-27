import Foundation

/// Result of parsing the free-form "keys to click" text field.
struct ParsedKeysResult {
    /// Unique keys, in order of first appearance - used for the chip preview.
    let keys: [KeyOption]
    /// Every recognized token, in the order typed, with duplicates preserved
    /// (e.g. "h,e,l,l,o" keeps both `l`s) - used for actual playback so the
    /// app can type the exact sequence the user entered.
    let sequence: [KeyOption]
    let unrecognizedTokens: [String]
}

/// Parses free-form user text (e.g. "1, 2, 3" or "a s d space") into the
/// matching `KeyOption`s. Tokens can be separated by commas, spaces, tabs or
/// newlines, and common aliases are recognized (enter, esc, space, arrow
/// names, f1-f12, etc.) in addition to single characters (a-z, 0-9).
enum KeysInputParser {
    private static let aliases: [String: String] = [
        "enter": "Return", "return": "Return",
        "esc": "Escape", "escape": "Escape",
        "del": "Delete", "delete": "Delete", "backspace": "Delete",
        "space": "Space", "spacebar": "Space",
        "tab": "Tab",
        "up": "Up", "uparrow": "Up",
        "down": "Down", "downarrow": "Down",
        "left": "Left", "leftarrow": "Left",
        "right": "Right", "rightarrow": "Right"
    ]

    static func parse(_ text: String) -> ParsedKeysResult {
        let separators = CharacterSet(charactersIn: ", \t\n")
        let tokens = text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var keys: [KeyOption] = []
        var sequence: [KeyOption] = []
        var unrecognized: [String] = []
        var seenIDs = Set<String>()

        for token in tokens {
            guard
                let canonicalID = canonicalID(for: token),
                let match = KeyCatalog.byID[canonicalID]
            else {
                unrecognized.append(token)
                continue
            }

            sequence.append(match)
            if seenIDs.insert(canonicalID).inserted {
                keys.append(match)
            }
        }

        return ParsedKeysResult(keys: keys, sequence: sequence, unrecognizedTokens: unrecognized)
    }

    private static func canonicalID(for token: String) -> String? {
        let lower = token.lowercased()

        if let alias = aliases[lower] {
            return alias
        }
        if lower.count == 1 {
            return lower.uppercased()
        }
        if lower.hasPrefix("f"), let number = Int(lower.dropFirst()), (1...12).contains(number) {
            return "F\(number)"
        }
        return nil
    }
}
