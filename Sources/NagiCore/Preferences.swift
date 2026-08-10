import Foundation

/// Typed access to the app's settings.
///
/// The `UserDefaults` instance is injected so tests can run against a throwaway
/// domain instead of the real user's preferences.
public final class Preferences {
    private enum Key {
        static let notesDirectory = "notesDirectoryPath"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Where notes are saved. `nil` until the user picks a folder — the app
    /// prompts rather than guessing a location and scattering files.
    public var notesDirectory: URL? {
        get {
            guard let path = defaults.string(forKey: Key.notesDirectory), !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        set {
            if let newValue {
                defaults.set(newValue.standardizedFileURL.path, forKey: Key.notesDirectory)
            } else {
                defaults.removeObject(forKey: Key.notesDirectory)
            }
        }
    }

    /// The global hotkey that summons the capture window.
    public var hotkey: Hotkey {
        get {
            guard defaults.object(forKey: Key.hotkeyKeyCode) != nil else {
                return .defaultHotkey
            }
            return Hotkey(
                keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotkeyModifiers)
        }
    }
}
