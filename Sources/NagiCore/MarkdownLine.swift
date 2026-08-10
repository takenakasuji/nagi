import Foundation

/// The ASCII code units the Markdown scanners compare against.
///
/// Comparing UTF-16 code units directly is what keeps the scan correct for
/// Japanese text and emoji: a multi-unit character can never collide with an
/// ASCII marker, and no `String.Index` arithmetic is involved.
enum ASCII {
    static let tab: UInt16 = 0x09
    static let space: UInt16 = 0x20
    static let hash: UInt16 = 0x23
    static let openParen: UInt16 = 0x28
    static let closeParen: UInt16 = 0x29
    static let asterisk: UInt16 = 0x2A
    static let plus: UInt16 = 0x2B
    static let hyphen: UInt16 = 0x2D
    static let dot: UInt16 = 0x2E
    static let zero: UInt16 = 0x30
    static let nine: UInt16 = 0x39
    static let greaterThan: UInt16 = 0x3E
    static let upperA: UInt16 = 0x41
    static let upperX: UInt16 = 0x58
    static let upperZ: UInt16 = 0x5A
    static let openBracket: UInt16 = 0x5B
    static let closeBracket: UInt16 = 0x5D
    static let underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60
    static let lowerA: UInt16 = 0x61
    static let lowerX: UInt16 = 0x78
    static let lowerZ: UInt16 = 0x7A
}

/// One line of the document, positioned in UTF-16 code units.
struct MarkdownLine: Equatable {
    /// The line's text, without its terminating newline.
    let text: String
    /// Offset of the line's first character within the document.
    let start: Int

    var length: Int { text.utf16.count }
    /// Offset just past the last character — where the newline sits.
    var end: Int { start + length }

    func contains(caret: Int) -> Bool { caret >= start && caret <= end }
}

enum MarkdownLines {
    /// Splits on "\n", keeping the trailing empty line: a caret parked after a
    /// final newline still needs a line to sit on.
    static func split(_ text: String) -> [MarkdownLine] {
        var lines: [MarkdownLine] = []
        var start = 0
        for piece in text.components(separatedBy: "\n") {
            lines.append(MarkdownLine(text: piece, start: start))
            start += piece.utf16.count + 1
        }
        return lines
    }

    /// The line the caret sits on. A caret exactly on a boundary belongs to the
    /// line that ends there, which is where a text view draws the insertion point.
    static func indexOfLine(at caret: Int, in lines: [MarkdownLine]) -> Int? {
        lines.firstIndex { $0.contains(caret: caret) }
    }
}

/// What sits at the head of a line: the indent plus the marker that makes the
/// line a list item, a task or a quote.
struct BlockPrefix: Equatable {
    enum Kind: Equatable {
        case bullet(Character)
        case ordered(number: Int)
        case task(bullet: Character, done: Bool)
        case quote
    }

    let kind: Kind
    /// Length of the leading whitespace.
    let indent: Int
    /// Length of the whole prefix from the line start, trailing space included.
    /// `  - [x] ` is 8.
    let length: Int
    /// The column a nested child indents to. Only the *list* marker counts, so
    /// `  - [x] ` nests at 4 — CommonMark treats `[x]` as content.
    let nestingColumn: Int

    var isList: Bool {
        if case .quote = kind { return false }
        return true
    }

    /// The marker the next line gets when Return continues this one.
    var continuation: Kind {
        switch kind {
        case .bullet, .quote:      return kind
        case .ordered(let n):      return .ordered(number: n + 1)
        case .task(let bullet, _): return .task(bullet: bullet, done: false)
        }
    }

    /// True when the line carries a marker and nothing else — the state Return
    /// reads as "leave the list".
    func hasEmptyContent(in line: String) -> Bool {
        let u = Array(line.utf16)
        guard length < u.count else { return true }
        return u[length...].allSatisfy { $0 == ASCII.space || $0 == ASCII.tab }
    }

    static func parse(_ line: String) -> BlockPrefix? {
        let u = Array(line.utf16)
        var i = 0
        while i < u.count, u[i] == ASCII.space || u[i] == ASCII.tab { i += 1 }
        let indent = i
        guard i < u.count else { return nil }

        if u[i] == ASCII.greaterThan {
            // Both "> " and a bare ">" open a quote.
            let length = (i + 1 < u.count && u[i + 1] == ASCII.space) ? i + 2 : i + 1
            return BlockPrefix(kind: .quote, indent: indent, length: length, nestingColumn: length)
        }

        if u[i] == ASCII.hyphen || u[i] == ASCII.asterisk || u[i] == ASCII.plus {
            // The space is required, which is also what keeps "---" from being
            // read as an empty list item.
            guard i + 1 < u.count, u[i + 1] == ASCII.space else { return nil }
            guard let scalar = UnicodeScalar(u[i]) else { return nil }
            let bullet = Character(scalar)
            let nesting = i + 2
            if let done = taskBox(u, at: nesting) {
                return BlockPrefix(kind: .task(bullet: bullet, done: done),
                                   indent: indent, length: nesting + 4, nestingColumn: nesting)
            }
            return BlockPrefix(kind: .bullet(bullet), indent: indent, length: nesting, nestingColumn: nesting)
        }

        if u[i] >= ASCII.zero, u[i] <= ASCII.nine {
            var j = i
            var number = 0
            // Nine digits is far past any real list and keeps the multiply from
            // overflowing on a pasted wall of numbers.
            while j < u.count, u[j] >= ASCII.zero, u[j] <= ASCII.nine, j - i < 9 {
                number = number * 10 + Int(u[j] - ASCII.zero)
                j += 1
            }
            guard j + 1 < u.count, u[j] == ASCII.dot, u[j + 1] == ASCII.space else { return nil }
            let length = j + 2
            return BlockPrefix(kind: .ordered(number: number), indent: indent, length: length, nestingColumn: length)
        }

        return nil
    }

    /// The literal prefix text for a marker at a given indent.
    static func text(kind: Kind, indent: Int) -> String {
        let pad = String(repeating: " ", count: indent)
        switch kind {
        case .bullet(let bullet):
            return "\(pad)\(bullet) "
        case .ordered(let number):
            return "\(pad)\(number). "
        case .task(let bullet, let done):
            return "\(pad)\(bullet) [\(done ? "x" : " ")] "
        case .quote:
            return "\(pad)> "
        }
    }

    /// "[ ] " / "[x] " / "[X] " straight after a bullet. Returns whether it is ticked.
    private static func taskBox(_ u: [UInt16], at i: Int) -> Bool? {
        guard i + 3 < u.count,
              u[i] == ASCII.openBracket,
              u[i + 2] == ASCII.closeBracket,
              u[i + 3] == ASCII.space
        else { return nil }

        switch u[i + 1] {
        case ASCII.space: return false
        case ASCII.lowerX, ASCII.upperX: return true
        default: return nil
        }
    }
}
