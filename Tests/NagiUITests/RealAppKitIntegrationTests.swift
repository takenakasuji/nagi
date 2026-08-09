import AppKit
import Foundation
import NagiCore
import SwiftUI
import Testing
@testable import NagiUI

/// Exercises the real AppKit and Carbon objects rather than stubs: the actual
/// `RegisterEventHotKey` call and the actual `NSPanel`.
///
/// These need a window server, so they're tagged `.gui` and can be excluded with
/// `--skip gui` on a headless machine.
@Suite("Real AppKit integration", .tags(.gui), .serialized)
@MainActor
struct RealAppKitIntegrationTests {
    /// Makes sure AppKit is initialised before any window is created.
    private func bootstrapAppKit() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
    }

    @Test("Carbon に ⌥Space を実際に登録できる")
    func registersRealCarbonHotkey() {
        bootstrapAppKit()

        let manager = HotkeyManager(onPress: {})
        #expect(manager.register(.defaultHotkey))

        // Re-registering must replace cleanly rather than fail on the second go.
        #expect(manager.register(.defaultHotkey))
        #expect(manager.register(Hotkey(keyCode: 45, carbonModifiers: Hotkey.cmdKey | Hotkey.shiftKey)))
    }

    @Test("実際のパネルはキーウインドウになれる")
    func realPanelCanBecomeKey() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        // The whole editor depends on this: a plain NSPanel refuses key status,
        // which would make typing impossible.
        #expect(panel.canBecomeKey)
        #expect(panel.canBecomeMain)
    }

    @Test("実際のウインドウを表示・非表示でき、本文にフォーカス要求が出る")
    func realWindowShowsAndHides() {
        bootstrapAppKit()

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NagiRealWindow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }

        let suiteName = "NagiRealWindowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.notesDirectory = scratch.appendingPathComponent("notes")

        let env = AppEnvironment(
            preferences: preferences,
            store: StashStore(fileURL: scratch.appendingPathComponent("state.json")),
            directoryPicker: { nil }
        )
        let controller = CaptureWindowController(env: env)
        env.start(window: controller,
                  hotkey: HotkeyManager(onPress: {}),
                  settings: SettingsWindowController(env: env))

        controller.show()
        #expect(controller.isVisible)
        #expect(env.ui.focusRequest?.field == .body)

        controller.hide()
        #expect(controller.isVisible == false)
    }

    /// Builds a real key-down event, the way AppKit would deliver one.
    private func keyEvent(
        characters: String,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @Test("実パネルが ⌘Return / ⌘⇧S / ⌘, を受け取り、編集用の ⌘A は素通しする")
    func realPanelRoutesKeyEquivalents() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        var received: [CaptureCommand] = []
        panel.onCommand = { received.append($0) }

        #expect(panel.performKeyEquivalent(with: keyEvent(characters: "\r", keyCode: 36, modifiers: [.command])))
        #expect(panel.performKeyEquivalent(with: keyEvent(characters: "S", keyCode: 1, modifiers: [.command, .shift])))
        #expect(panel.performKeyEquivalent(with: keyEvent(characters: ",", keyCode: 43, modifiers: [.command])))

        #expect(received == [.save, .stash, .settings])

        // Ordinary editing shortcuts must reach the text system untouched.
        received.removeAll()
        _ = panel.performKeyEquivalent(with: keyEvent(characters: "a", keyCode: 0, modifiers: [.command]))
        _ = panel.performKeyEquivalent(with: keyEvent(characters: "v", keyCode: 9, modifiers: [.command]))
        #expect(received.isEmpty)
    }

    @Test("実UIを組み立てた状態で保存すると .md が書かれる")
    func savingThroughRealWindowWritesFile() throws {
        bootstrapAppKit()

        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NagiRealSave-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let notes = scratch.appendingPathComponent("notes")

        let suiteName = "NagiRealSaveTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = Preferences(defaults: defaults)
        preferences.notesDirectory = notes

        let env = AppEnvironment(
            preferences: preferences,
            store: StashStore(fileURL: scratch.appendingPathComponent("state.json")),
            directoryPicker: { nil }
        )
        let controller = CaptureWindowController(env: env)
        env.start(window: controller,
                  hotkey: HotkeyManager(onPress: {}),
                  settings: SettingsWindowController(env: env))

        controller.show()
        env.session.filename = "実UIテスト"
        env.session.body = "ホットキーから書いた本文"
        env.save()

        let written = notes.appendingPathComponent("実UIテスト.md")
        #expect(FileManager.default.fileExists(atPath: written.path))
        #expect(try String(contentsOf: written, encoding: .utf8) == "ホットキーから書いた本文")
        #expect(controller.isVisible == false)
    }

    /// Drives a key-down the way `NSApplication.sendEvent` does: the key
    /// equivalent stage first, and the responder chain only if nothing consumed
    /// it.
    ///
    /// `panel.sendEvent(_:)` on its own is **not** that order. `NSWindow`'s
    /// implementation goes to the first responder immediately and only falls back
    /// to key equivalents if the chain declines, so driving through it alone
    /// silently skips the stage where the contest is actually decided.
    /// `NSApp.sendEvent(_:)` cannot stand in either: its window half is gated on
    /// there being a key window, and a `swift test` binary cannot make one (it is
    /// not a bundle, and `CGSSessionScreenIsLocked` blocks activation outright).
    /// `素の Escape も key equivalent の段に流れる` pins the half that can be
    /// measured directly.
    ///
    /// - Returns: whether the key equivalent stage consumed the event.
    @discardableResult
    private func dispatch(_ event: NSEvent, through panel: CapturePanel) -> Bool {
        if panel.performKeyEquivalent(with: event) { return true }
        panel.sendEvent(event)
        return false
    }

    /// Builds the capture panel the way `CaptureWindowController.makePanel()`
    /// does, so the hidden `.cancelAction` button is genuinely in the view tree.
    private func makeHostedPanel(
        env: AppEnvironment,
        onRequestHide: @escaping () -> Void
    ) -> CapturePanel {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let root = CaptureView(session: env.session, ui: env.ui, onRequestHide: onRequestHide)
            .environment(env)
        panel.contentView = NSHostingView(rootView: root)
        panel.makeKeyAndOrderFront(nil)
        panel.contentView?.layoutSubtreeIfNeeded()
        // NSHostingView instantiates the representable's NSView during its first
        // update pass, which needs the run loop to turn over once.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        return panel
    }

    private func firstDescendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let hit = view as? T { return hit }
        for subview in view.subviews {
            if let hit = firstDescendant(type, in: subview) { return hit }
        }
        return nil
    }

    /// A throwaway environment plus its scratch directory, torn down by the
    /// returned closure.
    private func makeScratchEnvironment() -> (env: AppEnvironment, cleanUp: () -> Void) {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NagiRealAppKit-\(UUID().uuidString)")
        let suiteName = "NagiRealAppKitTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = Preferences(defaults: defaults)
        preferences.notesDirectory = scratch.appendingPathComponent("notes")

        let env = AppEnvironment(
            preferences: preferences,
            store: StashStore(fileURL: scratch.appendingPathComponent("state.json")),
            directoryPicker: { nil }
        )
        return (env, {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: scratch)
        })
    }

    /// The load-bearing half of the Escape measurement, and the one that can be
    /// taken without a key window: AppKit runs the key equivalent stage *before*
    /// the responder chain, and a bare, unmodified Escape goes through it exactly
    /// like ⌘Return does. Menu and window key equivalents are dispatched by the
    /// same pass, and the menu half needs no activation — so the menu stands in
    /// for the window here.
    @Test("素の Escape も key equivalent の段に流れる")
    func bareEscapeReachesTheKeyEquivalentStage() {
        bootstrapAppKit()

        final class Target: NSObject, NSMenuItemValidation {
            var hits = 0
            @objc func hit(_ sender: Any?) { hits += 1 }
            func validateMenuItem(_ item: NSMenuItem) -> Bool { true }
        }

        func menu(keyEquivalent: String, mask: NSEvent.ModifierFlags, target: Target) -> NSMenu {
            let root = NSMenu()
            let holder = NSMenuItem()
            let submenu = NSMenu()
            let item = NSMenuItem(title: "テスト",
                                  action: #selector(Target.hit(_:)),
                                  keyEquivalent: keyEquivalent)
            item.keyEquivalentModifierMask = mask
            item.target = target
            submenu.addItem(item)
            holder.submenu = submenu
            root.addItem(holder)
            return root
        }

        let previousMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMenu }

        // 対照: 修飾つきのキー。ここが動かなければ測り方が壊れている。
        let control = Target()
        NSApp.mainMenu = menu(keyEquivalent: "\r", mask: [.command], target: control)
        NSApp.sendEvent(keyEvent(characters: "\r", keyCode: 36, modifiers: [.command]))
        #expect(control.hits == 1)

        // 本題: 修飾なしの Escape も同じ段で消費される。
        let escape = Target()
        NSApp.mainMenu = menu(keyEquivalent: "\u{1B}", mask: [], target: escape)
        NSApp.sendEvent(keyEvent(characters: "\u{1B}", keyCode: 53, modifiers: []))
        #expect(escape.hits == 1)
    }

    /// 実測。本文にフォーカスがあっても Escape を取るのは
    /// `NagiTextView.cancelOperation` ではなく、`CaptureView` の隠しボタンのほう。
    ///
    /// key equivalent の段が responder chain より先に走り、そこが素の Escape も
    /// 受け付ける（上のテスト）。その段で `.cancelAction` ボタンが true を返して
    /// 消費するので、本文の `cancelOperation(_:)` にはそもそも届かない。
    @Test("本文にフォーカスがあっても Escape は .cancelAction ボタンが先に取る")
    func escapeInBodyIsTakenByTheCancelActionButton() {
        bootstrapAppKit()

        let (env, cleanUp) = makeScratchEnvironment()
        defer { cleanUp() }

        var log: [String] = []
        let panel = makeHostedPanel(env: env, onRequestHide: { log.append("cancelAction") })
        defer { panel.orderOut(nil) }

        guard let textView = firstDescendant(NagiTextView.self, in: panel.contentView!) else {
            Issue.record("NagiTextView が view tree に無い")
            return
        }
        textView.onCancel = { log.append("cancelOperation") }
        #expect(panel.makeFirstResponder(textView))

        let consumed = dispatch(keyEvent(characters: "\u{1B}", keyCode: 53, modifiers: []),
                                through: panel)

        #expect(consumed)
        #expect(log == ["cancelAction"])
    }

    /// 隠しボタンに届く前に本文へ Escape が渡った場合の受け皿。現状その経路は
    /// 通らない（上のテスト）が、`cancelOperation` の中身自体はここで固定する。
    @Test("本文が Escape を受け取った場合、変換中は握りつぶす")
    func cancelOperationYieldsToTheInputMethod() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var cancelled = 0
        textView.onCancel = { cancelled += 1 }
        panel.contentView?.addSubview(textView)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        #expect(panel.makeFirstResponder(textView))

        let escape = keyEvent(characters: "\u{1B}", keyCode: 53, modifiers: [])

        // 変換中の Escape は入力メソッドのもの。窓は閉じない。
        textView.setMarkedText("かんじ",
                               selectedRange: NSRange(location: 3, length: 0),
                               replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.hasMarkedText())
        textView.keyDown(with: escape)
        #expect(cancelled == 0)
        #expect(textView.hasMarkedText())

        // 確定後は hide 要求に変換される。
        textView.unmarkText()
        textView.keyDown(with: escape)
        #expect(cancelled == 1)
    }

    @Test("本文にフォーカスがあっても ⌘Return はパネルが先に受け取り、本文には届かない")
    func commandReturnWinsAgainstTheTextView() {
        bootstrapAppKit()

        let (env, cleanUp) = makeScratchEnvironment()
        defer { cleanUp() }

        let panel = makeHostedPanel(env: env, onRequestHide: {})
        defer { panel.orderOut(nil) }

        guard let textView = firstDescendant(NagiTextView.self, in: panel.contentView!) else {
            Issue.record("NagiTextView が view tree に無い")
            return
        }
        textView.string = "打ちかけの本文"
        #expect(panel.makeFirstResponder(textView))

        var received: [CaptureCommand] = []
        panel.onCommand = { received.append($0) }

        let consumed = dispatch(keyEvent(characters: "\r", keyCode: 36, modifiers: [.command]),
                                through: panel)

        // 素通りしていたら responder chain まで落ちている。
        #expect(consumed)
        #expect(received == [.save])
        // ⌘Return がただの改行として text system に届いていないこと。
        #expect(textView.string == "打ちかけの本文")
    }

    @Test("外から本文を差し替えると、前の文書は Undo で戻ってこない")
    func externalReplacementClearsTheUndoStack() {
        bootstrapAppKit()

        let (env, cleanUp) = makeScratchEnvironment()
        defer { cleanUp() }

        let panel = makeHostedPanel(env: env, onRequestHide: {})
        defer { panel.orderOut(nil) }

        guard let textView = firstDescendant(NagiTextView.self, in: panel.contentView!) else {
            Issue.record("NagiTextView が view tree に無い")
            return
        }
        #expect(panel.makeFirstResponder(textView))

        // ユーザーが打った状態を作る（undo が積まれる経路を通す）。
        textView.insertText("退避される下書き", replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.string == "退避される下書き")
        #expect(textView.undoManager?.canUndo == true)

        // ⌘⇧S 相当。窓は開いたままエディタだけが空になる。
        env.session.body = ""
        MarkdownTextViewHighlighting.replaceDocument(of: textView, with: env.session.body)
        #expect(textView.string == "")

        // ⌘Z。前の文書が蘇ってはいけない（蘇ると textDidChange が
        // session.body に書き戻し、退避一覧とエディタに同じ下書きが二重に残る）。
        #expect(textView.undoManager?.canUndo == false)
        textView.undoManager?.undo()
        #expect(textView.string == "")
    }

    /// 変換中に退避を開いた、という場合。差し替えは `string` の代入だけで済ませ、
    /// 明示的な `unmarkText()` を足してはいけない — 足すと変換文字列が古い文書に
    /// 確定され、その古い文字列で `textDidChange` が飛び、そのあとの代入は何も
    /// 通知しないので `session.body` に読みかけが残る。ここはその再発防止。
    @Test("変換中に外から差し替えても、塗られ、delegate には新しい本文だけが届く")
    func externalReplacementDuringComposition() {
        bootstrapAppKit()

        final class Spy: NSObject, NSTextViewDelegate {
            var seen: [String] = []
            func textDidChange(_ notification: Notification) {
                guard let textView = notification.object as? NSTextView else { return }
                seen.append(textView.string)
            }
        }

        let spy = Spy()
        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.delegate = spy
        textView.string = "もとの下書き"
        textView.setMarkedText("かんじ",
                               selectedRange: NSRange(location: 3, length: 0),
                               replacementRange: NSRange(location: 0, length: 0))
        #expect(textView.hasMarkedText())
        spy.seen.removeAll()

        MarkdownTextViewHighlighting.replaceDocument(of: textView, with: "## 見出し")

        #expect(textView.hasMarkedText() == false)
        #expect(textView.string == "## 見出し")
        // 塗り漏れがない（apply の hasMarkedText ガードに引っかかっていない）
        #expect(textView.textStorage?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .heading))
        // delegate が読みかけを一度も見ていない
        #expect(spy.seen == ["## 見出し"])
    }

    @Test("色付けは本文全体を塗り直し、記号と地の色を塗り分ける")
    func highlightingPaintsMarkersAndBody() {
        bootstrapAppKit()

        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "## 見出し\n- 項目"
        MarkdownTextViewHighlighting.apply(to: textView)

        guard let storage = textView.textStorage else {
            Issue.record("text storage が無い")
            return
        }
        // UTF-16 の位置: "## 見出し" が 0..<6、改行が 6、"- 項目" が 7..<11。
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .heading))
        // 箇条書きの "-"
        #expect(storage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .marker))
        // 記号のうしろは地の色に戻る
        #expect(storage.attribute(.foregroundColor, at: 9, effectiveRange: nil) as? NSColor
                == MarkdownTheme.bodyColor)
    }

    /// `attributes(for:)` が色以外に足すのはこの下線だけで、`color(for:)` 経由の
    /// テストでは触れられない。
    @Test("リンクの文字列には下線がつき、URL にはつかない")
    func linkTextIsUnderlined() {
        bootstrapAppKit()

        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "[ラベル](https://example.com)"
        MarkdownTextViewHighlighting.apply(to: textView)

        guard let storage = textView.textStorage else {
            Issue.record("text storage が無い")
            return
        }
        // UTF-16 の位置: "[" が 0、"ラベル" が 1..<4、"](" が 4..<6、URL が 6..<25。
        #expect(storage.attribute(.underlineStyle, at: 1, effectiveRange: nil) as? Int
                == NSUnderlineStyle.single.rawValue)
        #expect(storage.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .linkText))
        // URL は同じ色だが下線は引かない
        #expect(storage.attribute(.underlineStyle, at: 10, effectiveRange: nil) == nil)
        #expect(storage.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .linkURL))
    }
    /// 実際の text view に delegate を繋いで、キー由来のコマンドを流し込む。
    ///
    /// ウインドウに載せるのは undo のため。`NSResponder.undoManager` は responder
    /// chain を辿って `NSWindow` から取るので、宙に浮いた view では nil になり
    /// ⌘Z が検証できない。
    private func makeBodyEditor(text: String, caret: Int)
        -> (panel: CapturePanel, view: NagiTextView, coordinator: MarkdownTextView.Coordinator) {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 本文の書き戻し先はこれらのテストでは見ない（判定はすべて view.string）ので、
        // 束縛は定数で足りる。
        let representable = MarkdownTextView(text: .constant(""), focusToken: nil, onCancel: {})
        let coordinator = representable.makeCoordinator()

        let view = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.delegate = coordinator
        view.allowsUndo = true
        panel.contentView?.addSubview(view)
        view.string = text
        view.setSelectedRange(NSRange(location: caret, length: 0))
        return (panel, view, coordinator)
    }

    @Test("本文で Return を押すと箇条書きが引き継がれる")
    func returnContinuesBullet() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 来週リリース", caret: 8)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(editor.view.string == "- 来週リリース\n- ")
        #expect(editor.view.selectedRange().location == 11)
    }

    @Test("空の項目で Return を押すとリストを抜ける")
    func returnOnEmptyItemLeavesTheList() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 親\n- ", caret: 6)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(editor.view.string == "- 親\n")
    }

    @Test("リスト行の Tab は階層を下げ、⇧Tab は戻す")
    func tabMovesListLevels() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 親\n- 子", caret: 7)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(editor.view.string == "- 親\n  - 子")

        editor.view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(editor.view.string == "- 親\n- 子")
    }

    @Test("リストでない行の Return と Tab は横取りしない")
    func plainLinesAreLeftAlone() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "ただのメモ", caret: 5)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)
        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertTab(_:))) == false)
        #expect(editor.view.string == "ただのメモ")
    }

    @Test("選択範囲があるときは横取りしない")
    func selectionsAreLeftAlone() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 項目", caret: 0)
        // マーカーの外（内容の中）を選択する。ここに caret があれば Core は
        // 単独では継続を返す位置なので、選択ガードが外れたときに検知できる。
        editor.view.setSelectedRange(NSRange(location: 2, length: 2))

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)
        #expect(editor.view.string == "- 項目")
    }

    @Test("リスト継続は ⌘Z で 1 手で取り消せる")
    func listContinuationIsOneUndoStep() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 来週リリース", caret: 8)

        _ = editor.coordinator.textView(editor.view,
                                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(editor.view.string == "- 来週リリース\n- ")

        editor.view.undoManager?.undo()
        #expect(editor.view.string == "- 来週リリース")
    }
}

extension Tag {
    @Tag static var gui: Self
}
