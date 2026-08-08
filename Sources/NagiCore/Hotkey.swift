import Foundation

/// A global hotkey, stored as the raw values Carbon's `RegisterEventHotKey`
/// wants: a virtual key code plus a Carbon modifier mask.
///
/// Kept free of Carbon imports so it stays testable and `Sendable`; the actual
/// registration lives in the app target.
public struct Hotkey: Codable, Equatable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    // Carbon modifier masks (from Events.h), restated so this file needs no import.
    public static let cmdKey: UInt32 = 256
    public static let shiftKey: UInt32 = 512
    public static let optionKey: UInt32 = 2048
    public static let controlKey: UInt32 = 4096

    /// ⌥Space. Deliberately not ⌘Space, which Spotlight owns.
    public static let defaultHotkey = Hotkey(keyCode: 49, carbonModifiers: optionKey)

    /// Human-readable form, e.g. `⌥Space`, using the conventional macOS
    /// modifier order (⌃⌥⇧⌘).
    public var displayString: String {
        var result = ""
        if carbonModifiers & Hotkey.controlKey != 0 { result += "⌃" }
        if carbonModifiers & Hotkey.optionKey != 0 { result += "⌥" }
        if carbonModifiers & Hotkey.shiftKey != 0 { result += "⇧" }
        if carbonModifiers & Hotkey.cmdKey != 0 { result += "⌘" }
        return result + Hotkey.keyName(for: keyCode)
    }

    /// Label for a virtual key code. Covers the keys people actually bind;
    /// anything else falls back to the raw code so the UI never shows nothing.
    static func keyName(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 53: return "Esc"
        case 0: return "A"
        case 11: return "B"
        case 8: return "C"
        case 2: return "D"
        case 14: return "E"
        case 3: return "F"
        case 5: return "G"
        case 4: return "H"
        case 34: return "I"
        case 38: return "J"
        case 40: return "K"
        case 37: return "L"
        case 46: return "M"
        case 45: return "N"
        case 31: return "O"
        case 35: return "P"
        case 12: return "Q"
        case 15: return "R"
        case 1: return "S"
        case 17: return "T"
        case 32: return "U"
        case 9: return "V"
        case 13: return "W"
        case 7: return "X"
        case 16: return "Y"
        case 6: return "Z"
        case 29: return "0"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"

        // Function keys. Note they are not in numeric order.
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        case 90: return "F20"

        // Arrows and the editing cluster.
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 51: return "Delete"
        case 117: return "ForwardDelete"
        case 115: return "Home"
        case 119: return "End"
        case 116: return "PageUp"
        case 121: return "PageDown"

        // Keypad. Labelled so it is distinguishable from the number row.
        case 82: return "テンキー0"
        case 83: return "テンキー1"
        case 84: return "テンキー2"
        case 85: return "テンキー3"
        case 86: return "テンキー4"
        case 87: return "テンキー5"
        case 88: return "テンキー6"
        case 89: return "テンキー7"
        case 91: return "テンキー8"
        case 92: return "テンキー9"
        case 65: return "テンキー."
        case 67: return "テンキー*"
        case 69: return "テンキー+"
        case 71: return "テンキーClear"
        case 75: return "テンキー/"
        case 76: return "テンキーEnter"
        case 78: return "テンキー-"
        case 81: return "テンキー="

        // Punctuation.
        case 27: return "-"
        case 24: return "="
        case 33: return "["
        case 30: return "]"
        case 42: return "\\"
        case 41: return ";"
        case 39: return "'"
        case 43: return ","
        case 47: return "."
        case 44: return "/"
        case 50: return "`"
        case 10: return "§"

        default: return "Key\(keyCode)"
        }
    }
}
