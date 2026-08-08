import Foundation
import Testing
@testable import NagiCore

@Suite("Preferences")
struct PreferencesTests {
    /// Preferences backed by an isolated defaults domain.
    private func withPreferences<T>(_ body: (Preferences) throws -> T) throws -> T {
        let suiteName = "NagiPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        return try body(Preferences(defaults: defaults))
    }

    @Test("既定のホットキーは ⌥Space")
    func defaultHotkeyIsOptionSpace() throws {
        try withPreferences { prefs in
            #expect(prefs.hotkey == Hotkey.defaultHotkey)
            #expect(prefs.hotkey.keyCode == 49)          // space
            #expect(prefs.hotkey.carbonModifiers == 2048) // optionKey
        }
    }

    @Test("ホットキーを保存して読み戻せる")
    func hotkeyRoundTrips() throws {
        try withPreferences { prefs in
            prefs.hotkey = Hotkey(keyCode: 45, carbonModifiers: 256) // ⌘N
            #expect(prefs.hotkey == Hotkey(keyCode: 45, carbonModifiers: 256))
        }
    }

    @Test("保存先は既定では未設定")
    func notesDirectoryStartsUnset() throws {
        try withPreferences { prefs in
            #expect(prefs.notesDirectory == nil)
        }
    }

    @Test("保存先を保存して読み戻せる")
    func notesDirectoryRoundTrips() throws {
        try withPreferences { prefs in
            let dir = URL(fileURLWithPath: "/tmp/nagi-notes", isDirectory: true)
            prefs.notesDirectory = dir

            #expect(prefs.notesDirectory?.standardizedFileURL.path == dir.standardizedFileURL.path)
        }
    }

    @Test("保存先はクリアできる")
    func notesDirectoryCanBeCleared() throws {
        try withPreferences { prefs in
            prefs.notesDirectory = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
            prefs.notesDirectory = nil

            #expect(prefs.notesDirectory == nil)
        }
    }

    @Test("ファンクションキーの表示名")
    func functionKeyNames() {
        #expect(Hotkey.keyName(for: 122) == "F1")
        #expect(Hotkey.keyName(for: 111) == "F12")
        #expect(Hotkey.keyName(for: 106) == "F16")
        #expect(Hotkey.keyName(for: 90) == "F20")
    }

    @Test("矢印・編集キーの表示名")
    func navigationKeyNames() {
        #expect(Hotkey.keyName(for: 123) == "←")
        #expect(Hotkey.keyName(for: 126) == "↑")
        #expect(Hotkey.keyName(for: 51) == "Delete")
        #expect(Hotkey.keyName(for: 115) == "Home")
        #expect(Hotkey.keyName(for: 121) == "PageDown")
    }

    @Test("テンキーの表示名")
    func keypadKeyNames() {
        #expect(Hotkey.keyName(for: 82) == "テンキー0")
        #expect(Hotkey.keyName(for: 92) == "テンキー9")
        #expect(Hotkey.keyName(for: 76) == "テンキーEnter")
        #expect(Hotkey.keyName(for: 75) == "テンキー/")
    }

    @Test("記号キーの表示名")
    func punctuationKeyNames() {
        #expect(Hotkey.keyName(for: 43) == ",")
        #expect(Hotkey.keyName(for: 47) == ".")
        #expect(Hotkey.keyName(for: 27) == "-")
    }

    @Test("未知のキーコードでも空にはならない")
    func unknownKeyStillRenders() {
        #expect(Hotkey.keyName(for: 9999) == "Key9999")
    }

    @Test("ホットキーの表示文字列が読める形になる")
    func hotkeyDisplayString() {
        #expect(Hotkey(keyCode: 49, carbonModifiers: 2048).displayString == "⌥Space")
        #expect(Hotkey(keyCode: 45, carbonModifiers: 256).displayString == "⌘N")
        // Modifiers are shown in the conventional macOS order: ⌃⌥⇧⌘
        #expect(Hotkey(keyCode: 49, carbonModifiers: 256 | 2048 | 512 | 4096).displayString
                == "⌃⌥⇧⌘Space")
    }
}
