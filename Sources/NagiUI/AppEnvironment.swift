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
    @ObservationIgnored private var window: CaptureWindowPresenting?
    @ObservationIgnored private var hotkeyRegistrar: GlobalHotkeyRegistering?
    @ObservationIgnored private var settingsWindow: SettingsWindowPresenting?

    /// Bumped when preferences change so `@Observable` views re-read the derived
    /// display values below (`Preferences` is plain storage, not observable).
    private var preferencesRevision = 0

    public init(
        preferences: Preferences,
        store: StashStore,
        directoryPicker: @escaping DirectoryPicker
    ) {
        self.preferences = preferences
        self.directoryPicker = directoryPicker
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

    // MARK: - window

    public func showCaptureWindow() {
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

    /// ⌘Enter. Guides rather than failing silently: no folder → picker,
    /// no filename → focus the name field, and the text is never lost.
    public func save() {
        ui.clearMessage()

        guard hasNotesDirectory else {
            ui.warn("先に保存先フォルダを選んでください")
            chooseNotesDirectory()
            return
        }
        guard !session.isCurrentEmpty else {
            ui.warn("メモが空です")
            return
        }

        do {
            let url = try session.save()
            ui.isStashListVisible = false
            hideCaptureWindow()
            ui.inform("保存しました: \(url.lastPathComponent)")
        } catch NoteWriterError.emptyFilename {
            ui.warn("ファイル名を入れてください")
            ui.focusRequest = .filename
        } catch {
            ui.warn("保存できませんでした: \(error.localizedDescription)")
        }
    }

    /// ⌘⇧S. Keeps the window open so the user can start the next note.
    public func stash() {
        ui.clearMessage()
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

    public func openStash(_ id: UUID) {
        ui.clearMessage()
        try? session.openStash(id)
        ui.isStashListVisible = false
        ui.focusRequest = .body
    }

    public func discardStash(_ id: UUID) {
        try? session.discardStash(id)
    }

    public func discardCurrent() {
        try? session.discardCurrent()
        ui.clearMessage()
        ui.focusRequest = .body
    }

    /// Menu "新規メモ": park anything in progress rather than dropping it, then
    /// open a clean editor.
    public func newNote() {
        if !session.isCurrentEmpty {
            try? session.stash()
        }
        showCaptureWindow()
    }
}
