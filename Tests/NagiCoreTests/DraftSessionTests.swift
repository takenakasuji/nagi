import Foundation
import Testing
@testable import NagiCore

/// These tests pin down the app's *behaviour* — the rules the user agreed to —
/// independently of any SwiftUI view:
///   * ⌘Enter saves and clears; a blank filename is refused.
///   * ⌘⇧S stashes and clears.
///   * Esc keeps the buffer as the active draft (never discards).
///   * Opening a stash moves it out of the list and into the editor.
@Suite("DraftSession")
struct DraftSessionTests {
    private func makeSession(
        state: NagiState = .empty
    ) -> (DraftSession, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DraftSessionTests-\(UUID().uuidString)")
        let store = StashStore(fileURL: dir.appendingPathComponent("state.json"))
        try? store.save(state)
        let session = DraftSession(store: store, notesDirectory: dir.appendingPathComponent("notes"))
        return (session, dir)
    }

    // MARK: - restoring

    @Test("起動時に前回のアクティブ下書きを復元する")
    func restoresActiveDraft() {
        let (session, _) = makeSession(
            state: NagiState(activeDraft: Draft(filename: "続き", body: "書きかけ"), stashes: [])
        )

        #expect(session.filename == "続き")
        #expect(session.body == "書きかけ")
    }

    @Test("アクティブ下書きが無ければ空で始まる")
    func startsEmptyWithoutActiveDraft() {
        let (session, _) = makeSession()

        #expect(session.filename.isEmpty)
        #expect(session.body.isEmpty)
    }

    // MARK: - saving

    @Test("保存するとファイルが出来てエディタが空になる")
    func saveWritesFileAndClearsEditor() throws {
        let (session, dir) = makeSession()
        session.filename = "会議メモ"
        session.body = "決まったこと"

        let url = try session.save()

        #expect(url.lastPathComponent == "会議メモ.md")
        #expect(try String(contentsOf: url, encoding: .utf8) == "決まったこと")
        #expect(session.filename.isEmpty)
        #expect(session.body.isEmpty)
        // The saved note lives in the notes folder, not in the state file.
        #expect(url.deletingLastPathComponent().lastPathComponent == "notes")
        #expect(dir.pathComponents.count > 0)
    }

    @Test("保存後はアクティブ下書きが永続化から消える")
    func saveClearsPersistedActiveDraft() throws {
        let (session, _) = makeSession()
        session.filename = "n"
        session.body = "b"
        _ = try session.save()

        #expect(session.store.load().activeDraft == nil)
    }

    @Test("ファイル名が空なら保存せず emptyFilename を投げる")
    func saveRefusesBlankFilename() {
        let (session, _) = makeSession()
        session.body = "本文はある"
        session.filename = "   "

        #expect(throws: NoteWriterError.emptyFilename) { try session.save() }
        // The user's text must survive a refused save.
        #expect(session.body == "本文はある")
    }

    // MARK: - stashing

    @Test("退避すると一覧の先頭に積まれエディタが空になる")
    func stashPushesAndClears() throws {
        let (session, _) = makeSession()
        session.filename = "あとで"
        session.body = "下書き1"

        try session.stash()

        #expect(session.stashes.count == 1)
        #expect(session.stashes.first?.body == "下書き1")
        #expect(session.filename.isEmpty)
        #expect(session.body.isEmpty)
    }

    @Test("退避は新しいものが先頭に来る")
    func stashIsNewestFirst() throws {
        let (session, _) = makeSession()
        session.body = "古い"
        try session.stash()
        session.body = "新しい"
        try session.stash()

        #expect(session.stashes.map(\.body) == ["新しい", "古い"])
    }

    @Test("空の内容は退避しない")
    func stashIgnoresEmptyContent() throws {
        let (session, _) = makeSession()
        session.body = "  \n "
        session.filename = " "

        try session.stash()

        #expect(session.stashes.isEmpty)
    }

    @Test("退避は永続化される")
    func stashPersists() throws {
        let (session, _) = makeSession()
        session.body = "残るはず"
        try session.stash()

        #expect(session.store.load().stashes.first?.body == "残るはず")
    }

    // MARK: - hiding (Esc)

    @Test("Escで隠しても内容は失われずアクティブ下書きになる")
    func suspendKeepsBufferAsActiveDraft() throws {
        let (session, _) = makeSession()
        session.filename = "途中"
        session.body = "まだ書いてる"

        try session.suspend()

        #expect(session.store.load().activeDraft?.body == "まだ書いてる")
        #expect(session.store.load().activeDraft?.filename == "途中")
        // Still in the editor, too — Esc only hides the window.
        #expect(session.body == "まだ書いてる")
    }

    @Test("空のままEscならアクティブ下書きは作らない")
    func suspendWithEmptyBufferStoresNothing() throws {
        let (session, _) = makeSession()

        try session.suspend()

        #expect(session.store.load().activeDraft == nil)
    }

    // MARK: - opening a stash

    @Test("スタッシュを開くとエディタに載り一覧から外れる")
    func openStashMovesItToEditor() throws {
        let target = Draft(filename: "退避済み", body: "退避本文")
        let (session, _) = makeSession(
            state: NagiState(activeDraft: nil, stashes: [target, Draft(body: "別のもの")])
        )

        try session.openStash(target.id)

        #expect(session.filename == "退避済み")
        #expect(session.body == "退避本文")
        #expect(session.stashes.count == 1)
        #expect(session.stashes.first?.body == "別のもの")
    }

    @Test("編集中の内容があるスタッシュを開くと、現在の内容は失わず退避される")
    func openStashPreservesCurrentWork() throws {
        let target = Draft(filename: "開く方", body: "開く本文")
        let (session, _) = makeSession(state: NagiState(activeDraft: nil, stashes: [target]))
        session.body = "いま書いていた分"

        try session.openStash(target.id)

        #expect(session.body == "開く本文")
        // The in-progress text was pushed to the stash rather than dropped.
        #expect(session.stashes.contains { $0.body == "いま書いていた分" })
    }

    @Test("スタッシュを破棄すると一覧から消える")
    func discardStashRemovesIt() throws {
        let doomed = Draft(body: "消す")
        let keeper = Draft(body: "残す")
        let (session, _) = makeSession(
            state: NagiState(activeDraft: nil, stashes: [doomed, keeper])
        )

        try session.discardStash(doomed.id)

        #expect(session.stashes.map(\.body) == ["残す"])
        #expect(session.store.load().stashes.map(\.body) == ["残す"])
    }

    // MARK: - discarding the editor

    @Test("エディタを破棄すると内容もアクティブ下書きも消える")
    func discardCurrentClearsEverything() throws {
        let (session, _) = makeSession(
            state: NagiState(activeDraft: Draft(filename: "f", body: "b"), stashes: [])
        )

        try session.discardCurrent()

        #expect(session.body.isEmpty)
        #expect(session.filename.isEmpty)
        #expect(session.store.load().activeDraft == nil)
    }
}
