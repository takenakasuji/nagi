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

    @Test("⌘S も保存（テキストを書くアプリで最も反射的に押される）")
    func commandSSaves() {
        #expect(command("s", 1, [.command]) == .save)
    }

    @Test("⌘S は日本語入力中でもキーコードで拾える")
    func commandSWorksWithIME() {
        #expect(command("と", 1, [.command]) == .save)
    }

    // MARK: things that must NOT match

    @Test("修飾なしの Return は素通し（改行を奪わない）")
    func plainReturnIsNotACommand() {
        #expect(command("\r", 36, []) == nil)
    }

    @Test("⌘S は退避ではない（退避は ⇧ が要る）")
    func commandSAloneIsNotStash() {
        #expect(command("s", 1, [.command]) != .stash)
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

    @Test("Esc はコマンドにしない（窓を閉じるのは .cancelAction ボタンの仕事）")
    func escapeIsNotHandledHere() {
        #expect(command("\u{1b}", 53, []) == nil)
        #expect(command("\u{1b}", 53, [.command]) == nil)
    }

    // MARK: 素の Esc の見分け

    /// `CapturePanel` が変換中に身を引くかどうかの判定材料。修飾つきの Esc まで
    /// 巻き込むと、⌘Esc などが入力メソッド任せになって窓に届かなくなる。
    @Test("修飾なしの Esc だけを素の Esc と見なす")
    func bareEscapeIsRecognised() {
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 53, modifiers: []))
        // CapsLock / Fn が乗っていても素の Esc のまま。
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 53, modifiers: [.capsLock]))
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 53, modifiers: [.function]))

        #expect(CaptureKeyBinding.isBareEscape(keyCode: 53, modifiers: [.command]) == false)
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 53, modifiers: [.shift]) == false)
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 53, modifiers: [.option]) == false)
    }

    @Test("Esc 以外のキーは素の Esc ではない")
    func otherKeysAreNotBareEscape() {
        // 修飾なしの Return / Tab / ふつうの文字。ここを取りこぼすと、変換中に
        // すべてのキーが key equivalent の段で捨てられる。
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 36, modifiers: []) == false)
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 48, modifiers: []) == false)
        #expect(CaptureKeyBinding.isBareEscape(keyCode: 0, modifiers: []) == false)
    }

    // MARK: incidental flags

    @Test("CapsLock や Fn が付いていても判定は変わらない")
    func incidentalFlagsAreIgnored() {
        #expect(command("\r", 36, [.command, .capsLock]) == .save)
        #expect(command("S", 1, [.command, .shift, .function]) == .stash)
    }
}

/// The settings window has to close itself: SwiftUI's generated menu for a
/// MenuBarExtra-only app has no File menu, so ⌘W is never dispatched.
@Suite("SettingsKeyBinding")
struct SettingsKeyBindingTests {
    private func closes(
        _ characters: String?,
        _ keyCode: UInt16,
        _ modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        SettingsKeyBinding.closes(characters: characters, keyCode: keyCode, modifiers: modifiers)
    }

    @Test("⌘W で閉じる")
    func commandWCloses() {
        #expect(closes("w", 13, [.command]))
    }

    @Test("⌘W は日本語入力中でもキーコードで拾える")
    func commandWWorksWithIME() {
        #expect(closes("て", 13, [.command]))
    }

    @Test("修飾なしの W では閉じない")
    func plainWDoesNotClose() {
        #expect(closes("w", 13, []) == false)
    }

    @Test("余計な修飾キーが付いていたら閉じない")
    func extraModifiersDoNotClose() {
        #expect(closes("w", 13, [.command, .shift]) == false)
        #expect(closes("w", 13, [.command, .option]) == false)
    }

    @Test("⌘Q は奪わない（終了はアプリメニューの仕事）")
    func commandQPassesThrough() {
        #expect(closes("q", 12, [.command]) == false)
    }
}
