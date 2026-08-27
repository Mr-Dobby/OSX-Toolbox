import Carbon.HIToolbox
import CoreGraphics

/// A single selectable key, identified by a stable string id and its macOS virtual key code.
struct KeyOption: Identifiable, Hashable {
    let id: String
    let label: String
    let keyCode: CGKeyCode
}

/// Static catalog of every key the user is allowed to pick in the UI.
enum KeyCatalog {
    static let digits: [KeyOption] = [
        KeyOption(id: "0", label: "0", keyCode: CGKeyCode(kVK_ANSI_0)),
        KeyOption(id: "1", label: "1", keyCode: CGKeyCode(kVK_ANSI_1)),
        KeyOption(id: "2", label: "2", keyCode: CGKeyCode(kVK_ANSI_2)),
        KeyOption(id: "3", label: "3", keyCode: CGKeyCode(kVK_ANSI_3)),
        KeyOption(id: "4", label: "4", keyCode: CGKeyCode(kVK_ANSI_4)),
        KeyOption(id: "5", label: "5", keyCode: CGKeyCode(kVK_ANSI_5)),
        KeyOption(id: "6", label: "6", keyCode: CGKeyCode(kVK_ANSI_6)),
        KeyOption(id: "7", label: "7", keyCode: CGKeyCode(kVK_ANSI_7)),
        KeyOption(id: "8", label: "8", keyCode: CGKeyCode(kVK_ANSI_8)),
        KeyOption(id: "9", label: "9", keyCode: CGKeyCode(kVK_ANSI_9))
    ]

    static let letters: [KeyOption] = [
        KeyOption(id: "A", label: "A", keyCode: CGKeyCode(kVK_ANSI_A)),
        KeyOption(id: "B", label: "B", keyCode: CGKeyCode(kVK_ANSI_B)),
        KeyOption(id: "C", label: "C", keyCode: CGKeyCode(kVK_ANSI_C)),
        KeyOption(id: "D", label: "D", keyCode: CGKeyCode(kVK_ANSI_D)),
        KeyOption(id: "E", label: "E", keyCode: CGKeyCode(kVK_ANSI_E)),
        KeyOption(id: "F", label: "F", keyCode: CGKeyCode(kVK_ANSI_F)),
        KeyOption(id: "G", label: "G", keyCode: CGKeyCode(kVK_ANSI_G)),
        KeyOption(id: "H", label: "H", keyCode: CGKeyCode(kVK_ANSI_H)),
        KeyOption(id: "I", label: "I", keyCode: CGKeyCode(kVK_ANSI_I)),
        KeyOption(id: "J", label: "J", keyCode: CGKeyCode(kVK_ANSI_J)),
        KeyOption(id: "K", label: "K", keyCode: CGKeyCode(kVK_ANSI_K)),
        KeyOption(id: "L", label: "L", keyCode: CGKeyCode(kVK_ANSI_L)),
        KeyOption(id: "M", label: "M", keyCode: CGKeyCode(kVK_ANSI_M)),
        KeyOption(id: "N", label: "N", keyCode: CGKeyCode(kVK_ANSI_N)),
        KeyOption(id: "O", label: "O", keyCode: CGKeyCode(kVK_ANSI_O)),
        KeyOption(id: "P", label: "P", keyCode: CGKeyCode(kVK_ANSI_P)),
        KeyOption(id: "Q", label: "Q", keyCode: CGKeyCode(kVK_ANSI_Q)),
        KeyOption(id: "R", label: "R", keyCode: CGKeyCode(kVK_ANSI_R)),
        KeyOption(id: "S", label: "S", keyCode: CGKeyCode(kVK_ANSI_S)),
        KeyOption(id: "T", label: "T", keyCode: CGKeyCode(kVK_ANSI_T)),
        KeyOption(id: "U", label: "U", keyCode: CGKeyCode(kVK_ANSI_U)),
        KeyOption(id: "V", label: "V", keyCode: CGKeyCode(kVK_ANSI_V)),
        KeyOption(id: "W", label: "W", keyCode: CGKeyCode(kVK_ANSI_W)),
        KeyOption(id: "X", label: "X", keyCode: CGKeyCode(kVK_ANSI_X)),
        KeyOption(id: "Y", label: "Y", keyCode: CGKeyCode(kVK_ANSI_Y)),
        KeyOption(id: "Z", label: "Z", keyCode: CGKeyCode(kVK_ANSI_Z))
    ]

    static let specialKeys: [KeyOption] = [
        KeyOption(id: "Space", label: "Space", keyCode: CGKeyCode(kVK_Space)),
        KeyOption(id: "Return", label: "Return", keyCode: CGKeyCode(kVK_Return)),
        KeyOption(id: "Tab", label: "Tab", keyCode: CGKeyCode(kVK_Tab)),
        KeyOption(id: "Escape", label: "Esc", keyCode: CGKeyCode(kVK_Escape)),
        KeyOption(id: "Delete", label: "Del", keyCode: CGKeyCode(kVK_Delete)),
        KeyOption(id: "Up", label: "\u{2191}", keyCode: CGKeyCode(kVK_UpArrow)),
        KeyOption(id: "Down", label: "\u{2193}", keyCode: CGKeyCode(kVK_DownArrow)),
        KeyOption(id: "Left", label: "\u{2190}", keyCode: CGKeyCode(kVK_LeftArrow)),
        KeyOption(id: "Right", label: "\u{2192}", keyCode: CGKeyCode(kVK_RightArrow))
    ]

    static let functionKeys: [KeyOption] = [
        KeyOption(id: "F1", label: "F1", keyCode: CGKeyCode(kVK_F1)),
        KeyOption(id: "F2", label: "F2", keyCode: CGKeyCode(kVK_F2)),
        KeyOption(id: "F3", label: "F3", keyCode: CGKeyCode(kVK_F3)),
        KeyOption(id: "F4", label: "F4", keyCode: CGKeyCode(kVK_F4)),
        KeyOption(id: "F5", label: "F5", keyCode: CGKeyCode(kVK_F5)),
        KeyOption(id: "F6", label: "F6", keyCode: CGKeyCode(kVK_F6)),
        KeyOption(id: "F7", label: "F7", keyCode: CGKeyCode(kVK_F7)),
        KeyOption(id: "F8", label: "F8", keyCode: CGKeyCode(kVK_F8)),
        KeyOption(id: "F9", label: "F9", keyCode: CGKeyCode(kVK_F9)),
        KeyOption(id: "F10", label: "F10", keyCode: CGKeyCode(kVK_F10)),
        KeyOption(id: "F11", label: "F11", keyCode: CGKeyCode(kVK_F11)),
        KeyOption(id: "F12", label: "F12", keyCode: CGKeyCode(kVK_F12))
    ]

    /// All keys in display order: digits, letters, special keys, then function keys.
    static let all: [KeyOption] = digits + letters + specialKeys + functionKeys

    /// Fast lookup from a canonical id (e.g. "A", "F6", "Return") to its `KeyOption`.
    static let byID: [String: KeyOption] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}

/// Mouse buttons the user can toggle on independently of keyboard keys.
enum MouseButtonOption: String, CaseIterable, Identifiable, Hashable {
    case left = "Left Click"
    case right = "Right Click"

    var id: String { rawValue }
}

/// Interval unit the user picks alongside the numeric interval value.
enum TimeUnit: String, CaseIterable, Identifiable, Hashable {
    case milliseconds = "ms"
    case seconds = "sec"
    case minutes = "min"

    var id: String { rawValue }

    func toSeconds(_ value: Double) -> Double {
        switch self {
        case .milliseconds: return value / 1000.0
        case .seconds: return value
        case .minutes: return value * 60.0
        }
    }
}
