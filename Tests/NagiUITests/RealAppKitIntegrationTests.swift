import AppKit
import Foundation
import NagiCore
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

    @Test("本文の Escape はキーイベントから hide 要求に変換される")
    func escapeInBodyReachesCancel() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var cancelled = false
        textView.onCancel = { cancelled = true }
        panel.contentView?.addSubview(textView)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }

        #expect(panel.makeFirstResponder(textView))

        // Esc は修飾なしなので key equivalent にはならない。標準のキーバインドで
        // cancelOperation: に落ち、responder chain を上がってくる経路を実際に通す。
        textView.keyDown(with: keyEvent(characters: "\u{1B}", keyCode: 53, modifiers: []))
        #expect(cancelled)
    }

    @Test("本文にフォーカスがあっても ⌘Return はパネルが先に受け取る")
    func commandReturnWinsAgainstTheTextView() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        panel.contentView?.addSubview(textView)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        #expect(panel.makeFirstResponder(textView))

        var received: [CaptureCommand] = []
        panel.onCommand = { received.append($0) }

        #expect(panel.performKeyEquivalent(with: keyEvent(characters: "\r", keyCode: 36, modifiers: [.command])))
        #expect(received == [.save])
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
}

extension Tag {
    @Tag static var gui: Self
}
