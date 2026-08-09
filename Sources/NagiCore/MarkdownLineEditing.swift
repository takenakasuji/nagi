import Foundation

/// A replacement to apply to the editor's text.
///
/// The Markdown layer never touches a text view — it says what to swap and where
/// to leave the caret, and the AppKit adapter performs it. That is what keeps
/// these rules testable without an event loop.
public struct TextEdit: Equatable, Sendable {
    /// UTF-16 range into the *original* text.
    public let range: Range<Int>
    public let replacement: String
    /// UTF-16 offset into the *resulting* text.
    public let caret: Int

    public init(range: Range<Int>, replacement: String, caret: Int) {
        self.range = range
        self.replacement = replacement
        self.caret = caret
    }
}

public enum MarkdownLineEditing {
    /// Tab (`outdent: false`) or ⇧Tab (`outdent: true`) on a list line.
    ///
    /// Returns nil when the line is not a list item, or when there is nowhere to
    /// move — the caller then lets the text view do whatever it normally does.
    public static func indent(in text: String, caret: Int, outdent: Bool) -> TextEdit? {
        let lines = MarkdownLines.split(text)
        guard let index = MarkdownLines.indexOfLine(at: caret, in: lines) else { return nil }
        let line = lines[index]
        guard let prefix = BlockPrefix.parse(line.text), prefix.isList else { return nil }

        guard let column = outdent
            ? outdentColumn(of: index, in: lines, prefix: prefix)
            : indentColumn(of: index, in: lines, prefix: prefix)
        else { return nil }

        return rewritePrefix(of: line, prefix: prefix, to: column, at: index, in: lines, caret: caret)
    }

    // MARK: - shared with Return

    /// Replaces a line's prefix with the same marker at a new indent, keeping the
    /// caret the same distance into the content.
    static func rewritePrefix(
        of line: MarkdownLine,
        prefix: BlockPrefix,
        to column: Int,
        at index: Int,
        in lines: [MarkdownLine],
        caret: Int
    ) -> TextEdit {
        let kind = renumbered(prefix.kind, at: column, before: index, in: lines)
        let replacement = BlockPrefix.text(kind: kind, indent: column)
        let newLength = replacement.utf16.count
        return TextEdit(
            range: line.start..<(line.start + prefix.length),
            replacement: replacement,
            caret: max(line.start + newLength, caret + newLength - prefix.length)
        )
    }

    /// The indent this line falls back to when stepped out one level: its
    /// parent's indent. Nil at the outermost level, where there is nothing to
    /// step out of.
    static func outdentColumn(of index: Int, in lines: [MarkdownLine], prefix: BlockPrefix) -> Int? {
        guard prefix.indent > 0 else { return nil }
        for i in stride(from: index - 1, through: 0, by: -1) {
            guard let candidate = BlockPrefix.parse(lines[i].text), candidate.isList else { break }
            if candidate.indent < prefix.indent { return candidate.indent }
        }
        return 0
    }

    /// After a level change, an ordered item takes the number after the last item
    /// at its new level. Only this line is rewritten — renumbering the rest of the
    /// list would move text the user is not looking at.
    static func renumbered(
        _ kind: BlockPrefix.Kind,
        at column: Int,
        before index: Int,
        in lines: [MarkdownLine]
    ) -> BlockPrefix.Kind {
        guard case .ordered = kind else { return kind }
        for i in stride(from: index - 1, through: 0, by: -1) {
            guard let candidate = BlockPrefix.parse(lines[i].text), candidate.isList else { break }
            if candidate.indent < column { break }
            guard candidate.indent == column else { continue }
            if case .ordered(let number) = candidate.kind { return .ordered(number: number + 1) }
            break
        }
        return .ordered(number: 1)
    }

    // MARK: - Tab only

    /// The column this line moves to when nested one level deeper: the content
    /// column of the nearest preceding item at the same level. Nil when there is
    /// no such sibling — the first item of a list has nothing to nest under.
    private static func indentColumn(
        of index: Int,
        in lines: [MarkdownLine],
        prefix: BlockPrefix
    ) -> Int? {
        for i in stride(from: index - 1, through: 0, by: -1) {
            guard let candidate = BlockPrefix.parse(lines[i].text), candidate.isList else { return nil }
            if candidate.indent == prefix.indent { return candidate.nestingColumn }
            if candidate.indent < prefix.indent { return nil }
        }
        return nil
    }
}
