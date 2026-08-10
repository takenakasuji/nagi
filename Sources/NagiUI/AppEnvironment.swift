import AppKit
import NagiCore
import Observation

/// Turns user actions into core-model transitions, and owns the app's long-lived
/// objects.
///
/// Every side effect it needs — the window, the hotkey registration, the folder
/// picker — is injected, so this orchestration is unit-tested against stubs while
/// the real implementations stay thin adapters.
@MainActor
@Observable
public final class AppEnvironment {
    public let preferences: Preferences
    public let session: DraftSession
    public let ui = CaptureUIState()

    @ObservationIgnored private let directoryPicker: DirectoryPicker
    @ObservationIgnored private let folderRevealer: FolderRevealer
    @ObservationIgnored private var window: CaptureWindowPresenting?
    @ObservationIgnored private var hotkeyRegistrar: GlobalHotkeyRegistering?
    @ObservationIgnored private var settingsWindow: SettingsWindowPresenting?

    /// Bumped when preferences change so `@Observable` views re-read the derived
    /// display values below (`Preferences` is plain storage, not observable).
    private var preferencesRevision = 0

    public init(
        preferences: Preferences,
        store: StashStore,
        directoryPicker: @escaping DirectoryPicker,
        folderRevealer: @escaping FolderRevealer
    ) {
        self.preferences = preferences
        self.directoryPicker = directoryPicker
        self.folderRevealer = folderRevealer
        // Until a folder is configured the session points at a placeholder;
        // `save()` refuses to run while `hasNotesDirectory` is false, so nothing
        // is ever written there.
        self.session = DraftSession(
            store: store,
            notesDirectory: preferences.notesDirectory
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        )
    }

    /// Connects the injected collaborators and registers the hotkey.
    public func start(
        window: CaptureWindowPresenting,
        hotkey: GlobalHotkeyRegistering,
        settings: SettingsWindowPresenting
    ) {
        self.window = window
        self.hotkeyRegistrar = hotkey
        self.settingsWindow = settings
        applyHotkey()
    }

    // MARK: - derived display values

    public var hasNotesDirectory: Bool {
        _ = preferencesRevision
        return preferences.notesDirectory != nil
    }

    public var notesDirectoryDisplay: String {
        _ = preferencesRevision
        guard let dir = preferences.notesDirectory else { return "未設定" }
        return (dir.path as NSString).abbreviatingWithTildeInPath
    }

    public var hotkeyDisplay: String {
        _ = preferencesRevision
        return preferences.hotkey.displayString
    }

    /// Tells observers to re-read the derived values after preferences change
    /// outside this object.
    public func refreshPreferencesDisplay() {
        preferencesRevision += 1
    }

    // MARK: - preferences

    public func setHotkey(_ hotkey: Hotkey) {
        preferences.hotkey = hotkey
        applyHotkey()
    }

    private func applyHotkey() {
        let hotkey = preferences.hotkey
        if let hotkeyRegistrar, !hotkeyRegistrar.register(hotkey) {
            ui.warn("ホットキー \(hotkey.displayString) は他のアプリが使用中です")
        }
        refreshPreferencesDisplay()
    }

    /// Asks for the notes folder and adopts the choice. Cancelling changes
    /// nothing.
    public func chooseNotesDirectory() {
        guard let url = directoryPicker() else { return }

        preferences.notesDirectory = url
        session.notesDirectory = url
        refreshPreferencesDisplay()
        ui.inform("保存先: \((url.path as NSString).abbreviatingWithTildeInPath)")
    }

    /// Shows the notes folder in Finder — the next step of the workflow this app
    /// deliberately stops short of.
    public func revealNotesDirectory() {
        guard let url = preferences.notesDirectory else { return }
        folderRevealer(url)
    }

    // MARK: - window

    public func showCaptureWindow() {
        // Feedback from the previous session must not survive into this one:
        // a fresh, empty note greeting the user with "保存しました" reads as if
        // they had just saved something.
        beginAction()
        window?.show()
    }

    /// Hides the capture window, keeping whatever is in the editor as the active
    /// draft.
    ///
    /// The `suspend()` belongs here rather than in the window adapter: it is a
    /// rule about the user's text, not about AppKit, and putting it in the
    /// adapter meant every other hide path silently dropped the draft.
    public func hideCaptureWindow() {
        try? session.suspend()
        window?.hide()
    }

    public func toggleCaptureWindow() {
        if window?.isVisible == true {
            hideCaptureWindow()
        } else {
            showCaptureWindow()
        }
    }

    /// Opens Settings.
    ///
    /// The capture panel is `.floating` (level 3) and the settings window is a
    /// normal level-0 window, so the panel would sit on top of it no matter how
    /// the settings window is presented. Get the panel out of the way first —
    /// hiding routes through `suspend()`, so the draft is kept.
    public func showSettings() {
        ui.isStashListVisible = false
        hideCaptureWindow()
        settingsWindow?.show()
    }

    // MARK: - actions

    /// Clears the transient feedback a previous action left behind.
    ///
    /// The undo offer expires here too: taking back a discard long after the
    /// fact would restore something the user is no longer thinking about.
    private func beginAction() {
        ui.clearMessage()
        lastDiscarded = nil
    }

    /// ⌘Enter / ⌘S. Guides rather than failing silently: no folder → picker,
    /// no filename → focus the name field, and the text is never lost.
    public func save() {
        beginAction()

        if !hasNotesDirectory {
            // Carry on into the save once a folder is chosen. Returning here
            // meant the user had to press ⌘Enter a second time for no reason
            // they could see.
            chooseNotesDirectory()
            guard hasNotesDirectory else {
                ui.warn("先に保存先フォルダを選んでください")
                return
            }
        }
        guard !session.isCurrentEmpty else {
            ui.warn("メモが空です")
            return
        }

        do {
            let url = try session.save()
            ui.isStashListVisible = false
            // Before hiding, not after: once the window is gone nothing can
            // render the message, and it lingers into the next session.
            ui.inform("保存しました: \(url.lastPathComponent)")
            hideCaptureWindow()
        } catch NoteWriterError.emptyFilename {
            ui.warn("ファイル名を入れてください")
            ui.focusRequest = .filename
        } catch {
            ui.warn("保存できませんでした: \(error.localizedDescription)")
        }
    }

    /// ⌘⇧S. Keeps the window open so the user can start the next note.
    public func stash() {
        beginAction()
        guard !session.isCurrentEmpty else {
            ui.warn("退避するものがありません")
            return
        }
        do {
            try session.stash()
            ui.inform("退避しました")
            ui.focusRequest = .body
        } catch {
            ui.warn("退避できませんでした: \(error.localizedDescription)")
        }
    }

    /// Loads a stashed draft. Anything already in the editor is parked rather
    /// than dropped — say so, because otherwise the swap is silent.
    public func openStash(_ id: UUID) {
        beginAction()
        let hadWorkInProgress = !session.isCurrentEmpty
        try? session.openStash(id)
        ui.isStashListVisible = false
        ui.focusRequest = .body
        if hadWorkInProgress {
            ui.inform("編集中のメモは退避しました")
        }
    }

    // MARK: - discarding

    /// The last discarded stash and where it sat, so the discard can be undone.
    /// A discarded draft exists nowhere on disk, so without this it is gone.
    private var lastDiscarded: (draft: Draft, index: Int)?

    public var canUndoDiscard: Bool { lastDiscarded != nil }

    public func discardStash(_ id: UUID) {
        ui.clearMessage()
        guard let index = session.stashes.firstIndex(where: { $0.id == id }) else { return }
        let draft = session.stashes[index]

        try? session.discardStash(id)
        lastDiscarded = (draft, index)
        ui.inform("「\(draft.displayTitle)」を破棄しました")
    }

    public func undoDiscardStash() {
        guard let (draft, index) = lastDiscarded else { return }
        lastDiscarded = nil
        try? session.restoreStash(draft, at: index)
        ui.inform("破棄を取り消しました")
    }

    public func discardCurrent() {
        beginAction()
        try? session.discardCurrent()
        ui.focusRequest = .body
    }

    /// Menu "新規メモ": park anything in progress rather than dropping it, then
    /// open a clean editor.
    public func newNote() {
        let hadWorkInProgress = !session.isCurrentEmpty
        if hadWorkInProgress {
            try? session.stash()
        }
        showCaptureWindow()
        // After showing: showCaptureWindow() clears stale feedback.
        if hadWorkInProgress {
            ui.inform("編集中のメモは退避しました")
        }
    }
}
