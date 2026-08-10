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

    // MARK: - inline level

    /// Scans one line's inline constructs left to right in a single pass.
    ///
    /// One pass is what keeps the spans from overlapping, and it is also why
    /// code wins over emphasis without a rule saying so: the opening backtick is
    /// simply reached first, and the scan resumes past the closing one.
    private static func inlineSpans(_ u: [UInt16], from: Int, lineStart: Int) -> [MarkdownSpan] {
        var spans: [MarkdownSpan] = []
        var i = from

        while i < u.count {
            switch u[i] {
            case ASCII.backtick:
                if let close = index(of: ASCII.backtick, in: u, after: i) {
                    append(&spans, lineStart + i, lineStart + i + 1, .marker)
                    append(&spans, lineStart + i + 1, lineStart + close, .code)
                    append(&spans, lineStart + close, lineStart + close + 1, .marker)
                    i = close + 1
                    continue
                }
            case ASCII.openBracket:
                if let link = linkSpans(u, at: i, lineStart: lineStart) {
                    spans += link.spans
                    i = link.end
                    continue
                }
            case ASCII.asterisk, ASCII.underscore:
                if let emphasis = emphasisSpans(u, at: i, lineStart: lineStart) {
                    spans += emphasis.spans
                    i = emphasis.end
                    continue
                }
            default:
                break
            }
            i += 1
        }

        return spans
    }

    /// `[label](url)` — all three pieces must be present on the line.
    private static func linkSpans(
        _ u: [UInt16],
        at open: Int,
        lineStart: Int
    ) -> (spans: [MarkdownSpan], end: Int)? {
        guard let closeBracket = index(of: ASCII.closeBracket, in: u, after: open),
              closeBracket + 1 < u.count,
              u[closeBracket + 1] == ASCII.openParen,
              let closeParen = index(of: ASCII.closeParen, in: u, after: closeBracket + 1)
        else { return nil }

        var spans: [MarkdownSpan] = []
        append(&spans, lineStart + open, lineStart + open + 1, .marker)
        append(&spans, lineStart + open + 1, lineStart + closeBracket, .linkText)
        append(&spans, lineStart + closeBracket, lineStart + closeBracket + 2, .marker)
        append(&spans, lineStart + closeBracket + 2, lineStart + closeParen, .linkURL)
        append(&spans, lineStart + closeParen, lineStart + closeParen + 1, .marker)
        return (spans, closeParen + 1)
    }

    /// `**bold**` / `*italic*` / `__…__` / `_…_`.
    ///
    /// Only the delimiters get a span. The text between them keeps the body
    /// colour, because the editor never changes weight — a bold run would be the
    /// one place where a line's height moves as you type.
    private static func emphasisSpans(
        _ u: [UInt16],
        at open: Int,
        lineStart: Int
    ) -> (spans: [MarkdownSpan], end: Int)? {
        let delimiter = u[open]
        // CommonMark forbids intraword `_`, and it is right to: without this,
        // `snake_case_name` and half the URLs anyone pastes come out with their
        // underscores greyed down to punctuation. `*` keeps working mid-word.
        //
        // This is only half of it — the closing run has to be checked too, or
        // `_private_name` still greys `_private_`: its opening `_` starts a word
        // and passes here. `closingRun` does that half.
        if delimiter == ASCII.underscore, open > 0, isASCIIAlphanumeric(u[open - 1]) {
            return nil
        }
        let width = (open + 1 < u.count && u[open + 1] == delimiter) ? 2 : 1
        let contentStart = open + width
        guard contentStart < u.count,
              let close = closingRun(of: delimiter, width: width, in: u, from: contentStart),
              close > contentStart
        else { return nil }

        var spans: [MarkdownSpan] = []
        append(&spans, lineStart + open, lineStart + contentStart, .marker)
        append(&spans, lineStart + close, lineStart + close + width, .marker)
        return (spans, close + width)
    }

    /// The delimiter run that closes the span, or `nil` if the line has none.
    ///
    /// A run of `_` that sits inside a word cannot close, for the same reason one
    /// cannot open: in `_private_name` the closing `_` is followed by more of the
    /// word, and treating it as a delimiter greys `_private_` down to punctuation.
    /// Rejected runs are skipped rather than given up on, so `_a_b_` still closes
    /// on its last `_` — which is also what CommonMark does with it.
    private static func closingRun(
        of delimiter: UInt16,
        width: Int,
        in u: [UInt16],
        from: Int
    ) -> Int? {
        var i = from
        while i < u.count {
            if u[i] == delimiter, width == 1 || (i + 1 < u.count && u[i + 1] == delimiter) {
                let after = i + width
                let isIntraword = delimiter == ASCII.underscore
                    && after < u.count
                    && isASCIIAlphanumeric(u[after])
                if !isIntraword { return i }
            }
            i += 1
        }
        return nil
    }

    /// ASCII only, deliberately. The identifiers and URLs this protects are
    /// ASCII, and widening it to every Unicode letter would mean decoding
    /// surrogate pairs on the hot path of a repaint that runs on every keystroke.
    private static func isASCIIAlphanumeric(_ unit: UInt16) -> Bool {
        (unit >= ASCII.zero && unit <= ASCII.nine)
            || (unit >= ASCII.upperA && unit <= ASCII.upperZ)
            || (unit >= ASCII.lowerA && unit <= ASCII.lowerZ)
    }

    private static func index(of unit: UInt16, in u: [UInt16], after i: Int) -> Int? {
        var j = i + 1
        while j < u.count {
            if u[j] == unit { return j }
            j += 1
        }
        return nil
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
