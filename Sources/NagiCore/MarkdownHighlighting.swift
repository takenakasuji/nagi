import Foundation

/// What a stretch of text is, as far as the editor's colouring is concerned.
///
/// Deliberately coarser than Markdown itself: the editor shows three colours
/// plus a dimmed grey for punctuation, so a token exists only where it changes
/// the colour. Anything not covered by a span is drawn in the body colour.
public enum MarkdownToken: Equatable, Sendable {
    /// The whole heading line, hashes included.
    case heading
    /// Punctuation that should recede: `- * + 1. [ ] > ** ` [ ]( )`.
    case marker
    /// Inside backticks or a fenced block.
    case code
    /// The text after a `>`.
    case quoteText
    /// The label between `[` and `]`.
    case linkText
    /// The destination between `(` and `)`.
    case linkURL
}

public struct MarkdownSpan: Equatable, Sendable {
    /// UTF-16 offsets into the document.
    public let range: Range<Int>
    public let token: MarkdownToken

    public init(range: Range<Int>, token: MarkdownToken) {
        self.range = range
        self.token = token
    }
}

public enum MarkdownHighlighting {
    /// Scans the document once, line by line. The only state carried between
    /// lines is whether a ``` fence is open.
    public static func spans(in text: String) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var isFenced = false

        for line in MarkdownLines.split(text) {
            let u = Array(line.text.utf16)

            if isFenceLine(u) {
                append(&spans, line.start, line.end, .marker)
                isFenced.toggle()
                continue
            }
            if isFenced {
                append(&spans, line.start, line.end, .code)
                continue
            }
            if isHeadingLine(u) {
                append(&spans, line.start, line.end, .heading)
                continue
            }
            guard let prefix = BlockPrefix.parse(line.text) else {
                spans += inlineSpans(u, from: 0, lineStart: line.start)
                continue
            }

            append(&spans, line.start + prefix.indent, line.start + prefix.length, .marker)
            if case .quote = prefix.kind {
                append(&spans, line.start + prefix.length, line.end, .quoteText)
            } else {
                spans += inlineSpans(u, from: prefix.length, lineStart: line.start)
            }
        }

        return spans
    }

    // MARK: - block level

    private static func isFenceLine(_ u: [UInt16]) -> Bool {
        var i = 0
        while i < u.count, u[i] == ASCII.space { i += 1 }
        guard u.count - i >= 3 else { return false }
        return u[i] == ASCII.backtick && u[i + 1] == ASCII.backtick && u[i + 2] == ASCII.backtick
    }

    /// One to six hashes at the very start of the line, followed by a space.
    /// The space matters: `#見出し` is a word, not a heading.
    private static func isHeadingLine(_ u: [UInt16]) -> Bool {
        var i = 0
        while i < u.count, u[i] == ASCII.hash { i += 1 }
        guard i >= 1, i <= 6, i < u.count else { return false }
        return u[i] == ASCII.space
    }

    // MARK: - inline level (Task 3 で埋める)

    private static func inlineSpans(_ u: [UInt16], from: Int, lineStart: Int) -> [MarkdownSpan] {
        []
    }

    private static func append(
        _ spans: inout [MarkdownSpan],
        _ lower: Int,
        _ upper: Int,
        _ token: MarkdownToken
    ) {
        guard lower < upper else { return }
        spans.append(MarkdownSpan(range: lower..<upper, token: token))
    }
}
