import AppKit
import Testing
@testable import NagiUI

/// The key-equivalent matcher is pure, so the rules can be pinned down without a
/// window, an event loop, or a real key press.
@Suite("CaptureKeyBinding")
struct CaptureKeyBindingTests {
    private func command(
        _ characters: String?,
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags
    ) -> CaptureCommand? {
        CaptureKeyBinding.command(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: the three bindings

    @Test("⌘Return は保存")
    func commandReturnSaves() {
        #expect(command("\r", 36, [.command]) == .save)
    }

    @Test("テンキーの Enter でも ⌘ で保存")
    func commandKeypadEnterSaves() {
        #expect(command("\u{3}", 76, [.command, .numericPad]) == .save)
    }

    @Test("⌘⇧S は退避")
    func commandShiftSStashes() {
        // charactersIgnoringModifiers keeps Shift applied, so this arrives uppercase.
        #expect(command("S", 1, [.command, .shift]) == .stash)
    }

    @Test("⌘⇧S は日本語入力中でもキーコードで拾える")
    func commandShiftSWorksWithIME() {
        // With a Japanese IME the characters may not be the Latin letter.
        #expect(command("す", 1, [.command, .shift]) == .stash)
    }

    @Test("⌘, は設定")
    func commandCommaOpensSettings() {
        #expect(command(",", 43, [.command]) == .settings)
    }

    // MARK: things that must NOT match

    @Test("修飾なしの Return は素通し（改行を奪わない）")
    func plainReturnIsNotACommand() {
        #expect(command("\r", 36, []) == nil)
    }

    @Test("⌘S だけでは退避しない")
    func commandSAloneIsNotStash() {
        #expect(command("s", 1, [.command]) == nil)
    }

    @Test("通常の編集ショートカットは奪わない")
    func editingShortcutsPassThrough() {
        #expect(command("a", 0, [.command]) == nil)   // select all
        #expect(command("c", 8, [.command]) == nil)   // copy
        #expect(command("v", 9, [.command]) == nil)   // paste
        #expect(command("z", 6, [.command]) == nil)   // undo
        #expect(command("z", 6, [.command, .shift]) == nil)  // redo
    }

    @Test("余計な修飾キーが付いていたら発火しない")
    func extraModifiersDoNotMatch() {
        #expect(command("\r", 36, [.command, .option]) == nil)
        #expect(command("\r", 36, [.command, .shift]) == nil)
        #expect(command("S", 1, [.command, .shift, .control]) == nil)
        #expect(command(",", 43, [.command, .shift]) == nil)
    }

    @Test("⌘ が無ければ何も発火しない")
    func withoutCommandNothingMatches() {
        #expect(command("s", 1, [.shift]) == nil)
        #expect(command(",", 43, []) == nil)
    }

    @Test("Esc はここでは扱わない（IME の変換取り消しを壊さないため）")
    func escapeIsNotHandledHere() {
        #expect(command("\u{1b}", 53, []) == nil)
        #expect(command("\u{1b}", 53, [.command]) == nil)
    }

    // MARK: incidental flags

    @Test("CapsLock や Fn が付いていても判定は変わらない")
    func incidentalFlagsAreIgnored() {
        #expect(command("\r", 36, [.command, .capsLock]) == .save)
        #expect(command("S", 1, [.command, .shift, .function]) == .stash)
    }
}
