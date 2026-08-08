import Foundation
import Observation

/// The editor's behaviour, independent of any UI framework.
///
/// Owns the single source of truth for "what is in the editor right now" and
/// "what has been stashed", and defines every transition between them:
/// save, stash, suspend (Esc), open a stash, discard. The views call these and
/// render the results; they contain no rules of their own.
///
/// A class rather than a struct because the window, the menu-bar menu and the
/// stash list all act on one shared session. `@Observable` lets SwiftUI bind
/// directly to these properties, so there is no second copy of the state to
/// keep in sync — `Observation` is a plain system framework, so this file stays
/// UI-framework-free.
@Observable
public final class DraftSession {
    /// Where persisted (unsaved) state lives.
    public let store: StashStore
    /// Where saved `.md` notes are written.
    public var notesDirectory: URL

    /// Editor fields. Mutated directly by the views' bindings.
    public var filename: String = ""
    public var body: String = ""

    /// Stashed drafts, newest first.
    public private(set) var stashes: [Draft] = []

    /// Identity of the buffer in the editor, preserved across suspend/restore so
    /// a resumed draft keeps its original creation time.
    private var currentID: UUID
    private var currentCreatedAt: Date

    public init(store: StashStore, notesDirectory: URL) {
        self.store = store
        self.notesDirectory = notesDirectory

        let state = store.load()
        stashes = state.stashes
        if let active = state.activeDraft {
            filename = active.filename
            body = active.body
            currentID = active.id
            currentCreatedAt = active.createdAt
        } else {
            currentID = UUID()
            currentCreatedAt = Date()
        }
    }

    // MARK: - current buffer

    /// The editor contents as a `Draft`.
    private var currentDraft: Draft {
        Draft(
            id: currentID,
            filename: filename,
            body: body,
            createdAt: currentCreatedAt,
            updatedAt: Date()
        )
    }

    /// True when there is nothing in the editor worth keeping.
    public var isCurrentEmpty: Bool { currentDraft.isEmpty }

    /// Empties the editor and starts a fresh buffer identity.
    private func resetBuffer() {
        filename = ""
        body = ""
        currentID = UUID()
        currentCreatedAt = Date()
    }

    private func persist(activeDraft: Draft?) throws {
        try store.save(NagiState(activeDraft: activeDraft, stashes: stashes))
    }

    // MARK: - transitions

    /// ⌘Enter — write the note to disk, then clear the editor.
    ///
    /// Throws ``NoteWriterError/emptyFilename`` without touching the editor when
    /// no name was given, so the user never loses text to a refused save.
    @discardableResult
    public func save() throws -> URL {
        let url = try NoteWriter.write(body: body, filename: filename, to: notesDirectory)
        resetBuffer()
        try persist(activeDraft: nil)
        return url
    }

    /// ⌘⇧S — move the editor contents to the stash list and clear the editor.
    /// Does nothing when the editor is empty.
    public func stash() throws {
        guard !isCurrentEmpty else { return }
        stashes.insert(currentDraft, at: 0)
        resetBuffer()
        try persist(activeDraft: nil)
    }

    /// Esc — the window is hiding. Keep the buffer as the active draft so the
    /// next launch resumes exactly where the user left off. Never discards.
    public func suspend() throws {
        try persist(activeDraft: isCurrentEmpty ? nil : currentDraft)
    }

    /// Load a stashed draft into the editor and remove it from the list.
    ///
    /// Anything already in the editor is stashed rather than dropped.
    public func openStash(_ id: UUID) throws {
        guard let index = stashes.firstIndex(where: { $0.id == id }) else { return }
        let target = stashes.remove(at: index)

        if !isCurrentEmpty {
            stashes.insert(currentDraft, at: 0)
        }

        filename = target.filename
        body = target.body
        currentID = target.id
        currentCreatedAt = target.createdAt

        try persist(activeDraft: currentDraft)
    }

    /// Permanently remove a stashed draft.
    public func discardStash(_ id: UUID) throws {
        stashes.removeAll { $0.id == id }
        try persist(activeDraft: isCurrentEmpty ? nil : currentDraft)
    }

    /// Throw away whatever is in the editor.
    public func discardCurrent() throws {
        resetBuffer()
        try persist(activeDraft: nil)
    }
}
