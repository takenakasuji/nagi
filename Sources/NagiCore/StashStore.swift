import Foundation

/// Everything Nagi persists between launches.
///
/// Note bodies that the user saved are plain `.md` files in their own folder —
/// this state is only the *unsaved* material, so the notes folder stays clean.
public struct NagiState: Codable, Equatable, Sendable {
    /// The buffer currently open in the editor. Kept when the window is hidden
    /// with Esc so the next launch resumes mid-sentence.
    public var activeDraft: Draft?
    /// Explicitly stashed drafts, newest first.
    public var stashes: [Draft]

    public init(activeDraft: Draft? = nil, stashes: [Draft] = []) {
        self.activeDraft = activeDraft
        self.stashes = stashes
    }

    public static let empty = NagiState()
}

/// Reads and writes ``NagiState`` as JSON on disk.
///
/// The file location is injected so tests can point it at a scratch directory.
public struct StashStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The default location: `~/Library/Application Support/Nagi/state.json`.
    public static func defaultStore() -> StashStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support")
        return StashStore(fileURL: base.appendingPathComponent("Nagi/state.json"))
    }

    /// Loads persisted state.
    ///
    /// A missing or unreadable file yields ``NagiState/empty`` — losing an
    /// unsaved draft is bad, but refusing to launch is worse, and the state file
    /// is a cache of convenience rather than the user's saved notes.
    public func load() -> NagiState {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NagiState.self, from: data)) ?? .empty
    }

    /// Writes state, creating the containing directory if needed.
    public func save(_ state: NagiState) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
