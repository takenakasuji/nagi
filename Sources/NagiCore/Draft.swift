import Foundation

/// A single note buffer. Used both for the currently-open editor content
/// (the "active draft") and for entries in the stash list.
///
/// `filename` may be empty — a stash does not require a decided name; the name
/// is only mandatory at save time (enforced by ``NoteWriter``).
public struct Draft: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var filename: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        filename: String = "",
        body: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.filename = filename
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// True when there is nothing worth keeping in either field.
    public var isEmpty: Bool {
        filename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A short label for lists: the first non-blank body line, falling back to
    /// the filename, then to a placeholder.
    public var displayTitle: String {
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })

        if let firstLine { return firstLine }

        let name = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "(空のメモ)" : name
    }
}
