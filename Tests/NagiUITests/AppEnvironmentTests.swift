import Foundation
import NagiCore
import Testing
@testable import NagiUI

// MARK: - stubs

@MainActor
private final class StubWindow: CaptureWindowPresenting {
    var isVisible = false
    var showCount = 0
    var hideCount = 0

    /// Lets a test observe the world *at the moment* the window is hidden —
    /// needed to pin down that feedback is set before the window goes away.
    var onHide: (@MainActor () -> Void)?

    func show() {
        showCount += 1
        isVisible = true
    }

    func hide() {
        hideCount += 1
        isVisible = false
        onHide?()
    }
}

@MainActor
private final class StubSettings: SettingsWindowPresenting {
    var showCount = 0
    func show() { showCount += 1 }
}

@MainActor
private final class StubHotkey: GlobalHotkeyRegistering {
    var registered: [Hotkey] = []
    /// Set to make the next registration fail, as if another app owns the key.
    var shouldFail = false

    func register(_ hotkey: Hotkey) -> Bool {
        registered.append(hotkey)
        return !shouldFail
    }
}

/// Collects the folders the app asked Finder to reveal.
@MainActor
private final class StubRevealer {
    var revealed: [URL] = []
}

/// Builds an environment with every side effect stubbed out.
@MainActor
private struct Harness {
    let env: AppEnvironment
    let window = StubWindow()
    let hotkey = StubHotkey()
    let settings = StubSettings()
    let revealer = StubRevealer()
    let notesDir: URL
    let scratch: URL

    init(configureNotesDirectory: Bool = true, pickerReturns: URL? = nil) {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AppEnvTests-\(UUID().uuidString)")
        notesDir = scratch.appendingPathComponent("notes")

        let suiteName = "NagiAppEnvTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let preferences = Preferences(defaults: defaults)
        if configureNotesDirectory {
            preferences.notesDirectory = notesDir
        }

        let picked = pickerReturns
        let recorder = revealer
        env = AppEnvironment(
            preferences: preferences,
            store: StashStore(fileURL: scratch.appendingPathComponent("state.json")),
            directoryPicker: { picked },
            folderRevealer: { recorder.revealed.append($0) }
        )
        env.start(window: window, hotkey: hotkey, settings: settings)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: scratch)
    }

    func savedFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: notesDir.path)) ?? []
        return names.sorted()
    }
}

// MARK: - tests

@Suite("AppEnvironment")
@MainActor
struct AppEnvironmentTests {
    // MARK: startup

    @Test("起動時に設定されたホットキーを登録する")
    func registersHotkeyOnStart() {
        let h = Harness()
        defer { h.cleanUp() }

        #expect(h.hotkey.registered == [Hotkey.defaultHotkey])
    }

    @Test("ホットキーが使用中なら警告を出す")
    func warnsWhenHotkeyUnavailable() {
        let h = Harness()
        defer { h.cleanUp() }

        h.hotkey.shouldFail = true
        h.env.setHotkey(Hotkey(keyCode: 45, carbonModifiers: Hotkey.cmdKey))

        #expect(h.env.ui.message?.kind == .warning)
        #expect(h.env.ui.message?.text.contains("使用中") == true)
    }

    // MARK: saving

    @Test("保存すると .md が書かれ、ウインドウが隠れる")
    func saveWritesFileAndHidesWindow() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.filename = "議事録"
        h.env.session.body = "決まったこと"
        h.env.save()

        #expect(h.savedFiles() == ["議事録.md"])
        #expect(h.window.hideCount == 1)
        #expect(h.env.ui.message?.kind == .info)
    }

    @Test("ファイル名が空なら保存せず、名前欄にフォーカスを移す")
    func saveWithoutFilenameFocusesNameField() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "本文だけ書いた"
        h.env.save()

        #expect(h.savedFiles().isEmpty)
        #expect(h.env.ui.focusRequest?.field == .filename)
        #expect(h.env.ui.message?.kind == .warning)
        // The text must survive a refused save.
        #expect(h.env.session.body == "本文だけ書いた")
        #expect(h.window.hideCount == 0)
    }

    @Test("空のメモは保存しない")
    func saveIgnoresEmptyNote() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.save()

        #expect(h.savedFiles().isEmpty)
        #expect(h.env.ui.message?.kind == .warning)
        #expect(h.window.hideCount == 0)
    }

    @Test("保存先が未設定なら保存せずフォルダ選択を促す")
    func saveWithoutNotesDirectoryPrompts() {
        let h = Harness(configureNotesDirectory: false)
        defer { h.cleanUp() }

        h.env.session.filename = "n"
        h.env.session.body = "b"
        h.env.save()

        #expect(h.env.hasNotesDirectory == false)
        #expect(h.env.ui.message?.kind == .warning)
        #expect(h.window.hideCount == 0)
    }

    @Test("フォルダ選択後は保存先が設定され保存できる")
    func choosingDirectoryEnablesSaving() {
        let picked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PickedNotes-\(UUID().uuidString)")
        let h = Harness(configureNotesDirectory: false, pickerReturns: picked)
        defer {
            h.cleanUp()
            try? FileManager.default.removeItem(at: picked)
        }

        h.env.chooseNotesDirectory()

        #expect(h.env.hasNotesDirectory)

        h.env.session.filename = "あとで"
        h.env.session.body = "本文"
        h.env.save()

        let names = (try? FileManager.default.contentsOfDirectory(atPath: picked.path)) ?? []
        #expect(names == ["あとで.md"])
    }

    @Test("フォルダ選択をキャンセルしたら未設定のまま")
    func cancellingPickerLeavesDirectoryUnset() {
        let h = Harness(configureNotesDirectory: false, pickerReturns: nil)
        defer { h.cleanUp() }

        h.env.chooseNotesDirectory()

        #expect(h.env.hasNotesDirectory == false)
    }

    @Test("保存先未設定でも、フォルダを選べたらそのまま保存まで進む")
    func saveFallsThroughAfterChoosingDirectory() {
        let picked = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FallThrough-\(UUID().uuidString)")
        let h = Harness(configureNotesDirectory: false, pickerReturns: picked)
        defer {
            h.cleanUp()
            try? FileManager.default.removeItem(at: picked)
        }

        h.env.session.filename = "初回"
        h.env.session.body = "本文"
        h.env.save()

        // ⌘Enter twice is friction the user should not have to discover.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: picked.path)) ?? []
        #expect(names == ["初回.md"])
        #expect(h.window.hideCount == 1)
    }

    // MARK: feedback

    @Test("保存の知らせはウインドウを隠す前に立てる")
    func saveMessageIsSetBeforeHiding() {
        let h = Harness()
        defer { h.cleanUp() }

        var messageAtHide: CaptureUIState.Message?
        h.window.onHide = { messageAtHide = h.env.ui.message }

        h.env.session.filename = "順序"
        h.env.session.body = "本文"
        h.env.save()

        // Setting it after the hide meant nothing could ever render it.
        #expect(messageAtHide?.kind == .info)
        #expect(messageAtHide?.text.contains("順序.md") == true)
    }

    @Test("ウインドウを開くと前回の知らせは持ち越さない")
    func showingClearsStaleMessage() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.filename = "前回"
        h.env.session.body = "本文"
        h.env.save()
        #expect(h.env.ui.message != nil)

        h.env.showCaptureWindow()

        // Otherwise a brand new, empty note greets the user with "保存しました".
        #expect(h.env.ui.message == nil)
    }

    @Test("編集中のメモがあるままスタッシュを開いたら、退避したことを知らせる")
    func openStashAnnouncesTheSwap() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "先に退避したもの"
        h.env.stash()
        let id = h.env.session.stashes[0].id
        h.env.session.body = "いま書いていた分"

        h.env.openStash(id)

        #expect(h.env.session.body == "先に退避したもの")
        #expect(h.env.session.stashes.map(\.body) == ["いま書いていた分"])
        #expect(h.env.ui.message?.kind == .info)
        #expect(h.env.ui.message?.text.contains("退避") == true)
    }

    @Test("編集中が空ならスタッシュを開いても余計な知らせは出さない")
    func openStashStaysQuietWhenEditorEmpty() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "退避済み"
        h.env.stash()
        let id = h.env.session.stashes[0].id

        h.env.openStash(id)

        #expect(h.env.ui.message == nil)
    }

    @Test("新規メモで書きかけを退避したときは知らせる")
    func newNoteAnnouncesTheStash() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "書きかけ"
        h.env.newNote()

        #expect(h.env.ui.message?.kind == .info)
        #expect(h.env.ui.message?.text.contains("退避") == true)
    }

    // MARK: undoing a discard

    @Test("破棄したスタッシュは元の位置に戻せる")
    func discardedStashCanBeUndone() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "古い方"
        h.env.stash()
        h.env.session.body = "新しい方"
        h.env.stash()
        // Newest first, so index 1 is 古い方.
        let id = h.env.session.stashes[1].id

        h.env.discardStash(id)
        #expect(h.env.session.stashes.map(\.body) == ["新しい方"])
        #expect(h.env.canUndoDiscard)

        h.env.undoDiscardStash()

        #expect(h.env.session.stashes.map(\.body) == ["新しい方", "古い方"])
        #expect(h.env.canUndoDiscard == false)
    }

    @Test("破棄したら取り消せることを知らせる")
    func discardOffersUndo() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "消す"
        h.env.stash()
        h.env.discardStash(h.env.session.stashes[0].id)

        #expect(h.env.ui.message?.kind == .info)
        #expect(h.env.canUndoDiscard)
    }

    @Test("別の操作をしたら破棄の取り消しはもう出さない")
    func undoExpiresOnTheNextAction() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "消す"
        h.env.stash()
        h.env.discardStash(h.env.session.stashes[0].id)
        #expect(h.env.canUndoDiscard)

        h.env.session.body = "次の作業"
        h.env.stash()

        // Offering an undo long after the fact restores something unexpected.
        #expect(h.env.canUndoDiscard == false)
    }

    // MARK: revealing the notes folder

    @Test("保存先を Finder で開ける")
    func revealsNotesDirectory() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.revealNotesDirectory()

        // Compare paths: Preferences hands back a URL flagged as a directory,
        // which differs from the test's URL only by a trailing slash.
        #expect(h.revealer.revealed.map(\.path) == [h.notesDir.path])
    }

    @Test("保存先が未設定なら Finder は開かない")
    func revealDoesNothingWithoutNotesDirectory() {
        let h = Harness(configureNotesDirectory: false)
        defer { h.cleanUp() }

        h.env.revealNotesDirectory()

        #expect(h.revealer.revealed.isEmpty)
    }

    // MARK: discarding the editor

    @Test("編集中のメモを破棄できる")
    func discardCurrentEmptiesTheEditor() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.filename = "要らない"
        h.env.session.body = "書いたが要らない"

        h.env.discardCurrent()

        #expect(h.env.session.body.isEmpty)
        #expect(h.env.session.filename.isEmpty)
        #expect(h.env.session.store.load().activeDraft == nil)
        #expect(h.env.ui.focusRequest?.field == .body)
    }

    // MARK: stashing

    @Test("退避するとスタッシュに積まれエディタが空になる")
    func stashMovesToList() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "あとで書く"
        h.env.stash()

        #expect(h.env.session.stashes.count == 1)
        #expect(h.env.session.body.isEmpty)
        // Stashing keeps the window up so the user can carry on with a new note.
        #expect(h.window.hideCount == 0)
    }

    @Test("空のときは退避せず警告する")
    func stashRefusesWhenEmpty() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.stash()

        #expect(h.env.session.stashes.isEmpty)
        #expect(h.env.ui.message?.kind == .warning)
    }

    @Test("スタッシュを開くと一覧を閉じて本文にフォーカスする")
    func openStashClosesListAndFocusesBody() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "退避する本文"
        h.env.stash()
        h.env.ui.isStashListVisible = true
        let id = h.env.session.stashes[0].id

        h.env.openStash(id)

        #expect(h.env.session.body == "退避する本文")
        #expect(h.env.ui.isStashListVisible == false)
        #expect(h.env.ui.focusRequest?.field == .body)
    }

    @Test("スタッシュを破棄すると一覧から消える")
    func discardStashRemovesEntry() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "消す"
        h.env.stash()
        let id = h.env.session.stashes[0].id

        h.env.discardStash(id)

        #expect(h.env.session.stashes.isEmpty)
    }

    // MARK: new note

    @Test("新規メモは書きかけを失わず退避してから開く")
    func newNoteStashesWorkInProgress() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.body = "書きかけ"
        h.env.newNote()

        #expect(h.env.session.body.isEmpty)
        #expect(h.env.session.stashes.map(\.body) == ["書きかけ"])
        #expect(h.window.showCount == 1)
    }

    @Test("空のときの新規メモは余計なスタッシュを作らない")
    func newNoteWithEmptyEditorStashesNothing() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.newNote()

        #expect(h.env.session.stashes.isEmpty)
        #expect(h.window.showCount == 1)
    }

    // MARK: hiding

    @Test("ウインドウを隠すと書きかけが永続化される")
    func hidingPersistsDraft() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.showCaptureWindow()
        h.env.session.filename = "途中"
        h.env.session.body = "まだ書いてる"

        h.env.hideCaptureWindow()

        // The rule belongs here, not in the window adapter — otherwise any other
        // hide path would silently drop the draft.
        #expect(h.env.session.store.load().activeDraft?.body == "まだ書いてる")
        #expect(h.window.hideCount == 1)
    }

    @Test("トグルは表示中なら隠し、非表示なら出す")
    func toggleFollowsVisibility() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.toggleCaptureWindow()
        #expect(h.window.showCount == 1)
        #expect(h.window.isVisible)

        h.env.toggleCaptureWindow()
        #expect(h.window.hideCount == 1)
        #expect(h.window.isVisible == false)
    }

    @Test("トグルで隠すときも書きかけは永続化される")
    func togglePersistsDraftWhenHiding() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.toggleCaptureWindow()
        h.env.session.body = "トグルで隠す前の本文"
        h.env.toggleCaptureWindow()

        #expect(h.env.session.store.load().activeDraft?.body == "トグルで隠す前の本文")
    }

    // MARK: settings

    @Test("設定を開くとキャプチャ窓を退かせてから設定窓を出す")
    func showSettingsHidesCaptureWindowFirst() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.showCaptureWindow()
        h.env.showSettings()

        // The capture panel is .floating (level 3) and the settings window is
        // level 0, so leaving it up would hide the settings window behind it.
        #expect(h.settings.showCount == 1)
        #expect(h.window.hideCount == 1)
        #expect(h.window.isVisible == false)
    }

    @Test("設定を開いても書きかけは失われない")
    func showSettingsPreservesDraft() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.session.filename = "途中"
        h.env.session.body = "書きかけ"
        h.env.showSettings()

        #expect(h.env.session.body == "書きかけ")
        // Hiding routes through suspend(), so it is on disk too.
        #expect(h.env.session.store.load().activeDraft?.body == "書きかけ")
    }

    @Test("スタッシュ一覧を開いた状態で設定を開くと一覧は閉じる")
    func showSettingsClosesStashPopover() {
        let h = Harness()
        defer { h.cleanUp() }

        h.env.ui.isStashListVisible = true
        h.env.showSettings()

        #expect(h.env.ui.isStashListVisible == false)
    }

    // MARK: display values

    @Test("保存先の表示はホームを ~ に短縮する")
    func notesDirectoryDisplayAbbreviatesHome() {
        let h = Harness(configureNotesDirectory: false)
        defer { h.cleanUp() }

        #expect(h.env.notesDirectoryDisplay == "未設定")

        h.env.preferences.notesDirectory = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Notes")
        h.env.refreshPreferencesDisplay()

        #expect(h.env.notesDirectoryDisplay == "~/Notes")
    }

    @Test("ホットキーの表示は設定値を反映する")
    func hotkeyDisplayReflectsPreference() {
        let h = Harness()
        defer { h.cleanUp() }

        #expect(h.env.hotkeyDisplay == "⌥Space")

        h.env.setHotkey(Hotkey(keyCode: 45, carbonModifiers: Hotkey.cmdKey))

        #expect(h.env.hotkeyDisplay == "⌘N")
    }
}
