# 本文エディタの Markdown 対応 実装計画

> **エージェント向け:** この計画はタスク単位で実装すること。`superpowers:subagent-driven-development`（推奨）または `superpowers:executing-plans` を使う。手順は `- [ ]` のチェックボックスで追跡する。

**ゴール:** 本文エディタで Markdown が色分けされ、Return でリストが継続し、Tab で階層が動くようにする。

**設計書:** [`specs/2026-08-09-markdown-input-design.md`](2026-08-09-markdown-input-design.md)

**方針:** SwiftUI の `TextEditor` を、`NSTextView` を包んだ `MarkdownTextView`（`NSViewRepresentable`）に置き換える。「どこが何か」「Return / Tab で何を差し替えるか」の判定はすべて `NagiCore` の純粋関数に置き、AppKit 側はそれを呼んで `NSTextStorage` に反映するだけの薄いアダプタにする。既存の `CaptureKeyBinding` と同じ分担。

**技術:** Swift 6 / SwiftPM（Xcode プロジェクトなし）/ AppKit / SwiftUI / swift-testing

## 全体制約

すべてのタスクの要件に、暗黙にこの節が含まれる。

- **デプロイターゲットは macOS 14。** `Package.swift` の `platforms: [.macOS(.v14)]` は変更しない。macOS 15 / 26 でしか使えない API は使わない
- **`NagiCore` は AppKit も SwiftUI も import してはいけない。** `Foundation` と `Observation` のみ
- **オフセットはすべて UTF-16 コード単位。** `String.Index` を層をまたいで持ち回らない
- **テストは `./scripts/test.sh` で走らせる。`swift test` を直接使わない**（Testing.framework の探索パスと cross-import overlay の無効化がスクリプト側にある）
- **`--filter` / `--skip` は型名にマッチする**（`@Suite` の表示名ではない）
- **UI の言語は日本語。テスト名も日本語で書く**
- **⌘Return / ⌘⇧S / ⌘, を SwiftUI 側にも二重に束縛しない。** これらは `CapturePanel.performKeyEquivalent` の担当
- 各タスクの最後に必ずコミットする

---

## ファイル構成

| ファイル | 責任 |
|---|---|
| `Sources/NagiCore/MarkdownLine.swift` | 行の分割と、行頭の前置き（`- ` `1. ` `- [ ] ` `> `）の解析。`internal` |
| `Sources/NagiCore/MarkdownHighlighting.swift` | 文字列 → スパン列。色は知らない |
| `Sources/NagiCore/MarkdownLineEditing.swift` | Return / Tab の文字列編集を計算する。キーは知らない |
| `Sources/NagiUI/MarkdownTheme.swift` | スパン種別 → `NSColor` と本文の書式 |
| `Sources/NagiUI/MarkdownTextView.swift` | `NSViewRepresentable` + `NagiTextView` + `Coordinator` |
| `Sources/NagiUI/CaptureView.swift` | 差し替え（既存を変更） |

---

## Task 0: 現状の Tab の挙動を確かめる

設計で「リスト行以外の Tab は今までどおり」と決めた。「今まで」が何なのかを、置き換える前に確認しておく。置き換えたあとでは確かめられない。

**Files:**
- Modify: `specs/2026-08-09-markdown-input-plan.md`（この節に結果を書き込む）

**Interfaces:**
- Consumes: なし
- Produces: Task 7 が読む「既定の Tab 挙動」の確定値

- [x] **Step 1: 現在の main の状態でアプリをビルドして起動する**

```bash
pkill -f "Nagi.app/Contents/MacOS/Nagi"; ./scripts/build-app.sh && open build/Nagi.app
```

- [x] **Step 2: ホットキー（⌥Space）で窓を出し、本文に文字を打ってから Tab を押す**

観察するのは 1 点だけ。

- **(A)** 本文にタブ文字（または空白）が入る
- **(B)** フォーカスがファイル名欄（または他のコントロール）へ移る

手動観察ではなく、実 AppKit を組み立てるテストで確認した（`CaptureWindowController` + `AppEnvironment` を実パネル上に構築し、本文の `NSTextView` に Tab の `NSEvent` を `keyDown(with:)` で送る）。

- [x] **Step 3: 結果をこの節に書き込む**

下の行を実際の結果で置き換える。

```
確認結果: A／確認日: 2026-08-09
本文の NSTextView に "hello" と入れて Tab を送ったところ string が "hello\t" に変わり（env.session.body も同じく "hello\t" に同期）、panel.firstResponder は Tab の前後で SwiftUI.PlatformTextView のまま変化しなかった。つまり Tab は本文にタブ文字を挿入するだけで、フォーカス移動は起きない。
```

- [x] **Step 4: アプリを終了してコミット**

```bash
pkill -f "Nagi.app/Contents/MacOS/Nagi"
git add specs/2026-08-09-markdown-input-plan.md
git commit -m "Tab の既定挙動を確認して実装計画に記録"
```

---

## Task 1: 行と前置きの解析

**Files:**
- Create: `Sources/NagiCore/MarkdownLine.swift`
- Test: `Tests/NagiCoreTests/MarkdownLineTests.swift`

**Interfaces:**
- Consumes: なし
- Produces（すべて `internal`、`NagiCore` 内から見える）:
  - `enum ASCII` — `tab space hash openParen closeParen asterisk plus hyphen dot zero nine greaterThan upperX openBracket closeBracket underscore backtick lowerX`（すべて `static let ...: UInt16`）
  - `struct MarkdownLine: Equatable` — `let text: String`, `let start: Int`, `var length: Int`, `var end: Int`, `func contains(caret: Int) -> Bool`
  - `enum MarkdownLines` — `static func split(_ text: String) -> [MarkdownLine]`, `static func indexOfLine(at caret: Int, in lines: [MarkdownLine]) -> Int?`
  - `struct BlockPrefix: Equatable` — `enum Kind: Equatable { case bullet(Character); case ordered(number: Int); case task(bullet: Character, done: Bool); case quote }`, `let kind: Kind`, `let indent: Int`, `let length: Int`, `let nestingColumn: Int`, `var isList: Bool`, `var continuation: Kind`, `func hasEmptyContent(in line: String) -> Bool`, `static func parse(_ line: String) -> BlockPrefix?`, `static func text(kind: Kind, indent: Int) -> String`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiCoreTests/MarkdownLineTests.swift`:

```swift
import Foundation
import Testing
@testable import NagiCore

@Suite("Markdown の行解析")
struct MarkdownLineTests {
    @Test("行は UTF-16 オフセット付きで分割される")
    func splitsLinesWithUTF16Offsets() {
        let lines = MarkdownLines.split("あい\nうえお\n")
        #expect(lines.count == 3)
        #expect(lines[0].start == 0)
        #expect(lines[1].start == 3)   // "あい" は 2 コード単位 + 改行
        #expect(lines[2].start == 7)   // + "うえお" の 3 + 改行
        #expect(lines[2].text == "")   // 末尾の空行も残す（キャレットが座れる場所なので）
    }

    @Test("行末のキャレットは手前の行に属する")
    func caretAtLineEndBelongsToPrecedingLine() {
        let lines = MarkdownLines.split("abc\ndef")
        #expect(MarkdownLines.indexOfLine(at: 3, in: lines) == 0)
        #expect(MarkdownLines.indexOfLine(at: 4, in: lines) == 1)
    }

    @Test("箇条書きの前置きを読む")
    func parsesBulletPrefix() {
        let prefix = BlockPrefix.parse("- リリースは来週")
        #expect(prefix?.kind == .bullet("-"))
        #expect(prefix?.indent == 0)
        #expect(prefix?.length == 2)
        #expect(prefix?.nestingColumn == 2)
    }

    @Test("チェックボックスは前置きの長さと入れ子の基準列が食い違う")
    func parsesTaskPrefix() {
        let prefix = BlockPrefix.parse("  - [x] 会場を押さえた")
        #expect(prefix?.kind == .task(bullet: "-", done: true))
        #expect(prefix?.indent == 2)
        #expect(prefix?.length == 8)         // "  - [x] "
        // "[x]" は CommonMark では本文側。入れ子の基準は "  - " の 4 桁
        #expect(prefix?.nestingColumn == 4)
    }

    @Test("番号付きは数字を読む")
    func parsesOrderedPrefix() {
        #expect(BlockPrefix.parse("12. 項目")?.kind == .ordered(number: 12))
        #expect(BlockPrefix.parse("12. 項目")?.length == 4)
        #expect(BlockPrefix.parse("12. 項目")?.nestingColumn == 4)
    }

    @Test("空白のない記号は前置きではない")
    func rejectsMarkersWithoutSpace() {
        #expect(BlockPrefix.parse("-リスト風") == nil)
        #expect(BlockPrefix.parse("---") == nil)      // 水平線を食わない
        #expect(BlockPrefix.parse("1.項目") == nil)
        #expect(BlockPrefix.parse("ただの本文") == nil)
        #expect(BlockPrefix.parse("") == nil)
    }

    @Test("引用は入れ子操作の対象ではない")
    func quoteIsNotAList() {
        let prefix = BlockPrefix.parse("> 次回に持ち越し")
        #expect(prefix?.kind == .quote)
        #expect(prefix?.length == 2)
        #expect(prefix?.isList == false)
    }

    @Test("継続用の前置きは番号を進めチェックを外す")
    func continuationAdvancesNumberAndClearsCheck() {
        #expect(BlockPrefix.text(kind: BlockPrefix.parse("3. 三つ目")!.continuation, indent: 0) == "4. ")
        #expect(BlockPrefix.text(kind: BlockPrefix.parse("- [x] 済み")!.continuation, indent: 2) == "  - [ ] ")
        #expect(BlockPrefix.text(kind: BlockPrefix.parse("* 項目")!.continuation, indent: 0) == "* ")
        #expect(BlockPrefix.text(kind: BlockPrefix.parse("> 引用")!.continuation, indent: 0) == "> ")
    }

    @Test("記号だけの行は中身が空")
    func detectsEmptyContent() {
        #expect(BlockPrefix.parse("- ")!.hasEmptyContent(in: "- "))
        #expect(BlockPrefix.parse("- [ ] ")!.hasEmptyContent(in: "- [ ] "))
        #expect(BlockPrefix.parse("- a")!.hasEmptyContent(in: "- a") == false)
    }
}
```

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "MarkdownLineTests"
```

`cannot find 'MarkdownLines' in scope` などで **コンパイルエラー**になるのが期待値。

- [ ] **Step 3: 実装する**

`Sources/NagiCore/MarkdownLine.swift`:

```swift
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
    static let upperX: UInt16 = 0x58
    static let openBracket: UInt16 = 0x5B
    static let closeBracket: UInt16 = 0x5D
    static let underscore: UInt16 = 0x5F
    static let backtick: UInt16 = 0x60
    static let lowerX: UInt16 = 0x78
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
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
./scripts/test.sh --filter "MarkdownLineTests"
```

期待: 9 テストすべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Sources/NagiCore/MarkdownLine.swift Tests/NagiCoreTests/MarkdownLineTests.swift
git commit -m "Markdown の行と行頭前置きの解析を追加"
```

---

## Task 2: 色付け — ブロック要素

見出し、リスト記号、引用、コードフェンス。インライン（コード・リンク・強調）は Task 3。

**Files:**
- Create: `Sources/NagiCore/MarkdownHighlighting.swift`
- Test: `Tests/NagiCoreTests/MarkdownHighlightingTests.swift`

**Interfaces:**
- Consumes: `MarkdownLines.split`, `BlockPrefix.parse`, `ASCII`（Task 1）
- Produces（`public`）:
  - `enum MarkdownToken: Equatable, Sendable { case heading, marker, code, quoteText, linkText, linkURL }`
  - `struct MarkdownSpan: Equatable, Sendable { public let range: Range<Int>; public let token: MarkdownToken; public init(range: Range<Int>, token: MarkdownToken) }`
  - `enum MarkdownHighlighting { public static func spans(in text: String) -> [MarkdownSpan] }`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiCoreTests/MarkdownHighlightingTests.swift`:

```swift
import Foundation
import Testing
@testable import NagiCore

@Suite("Markdown の色付け（ブロック）")
struct MarkdownHighlightingTests {
    @Test("見出しは行全体が見出し色")
    func highlightsHeadingLine() {
        #expect(MarkdownHighlighting.spans(in: "## 決まったこと")
                == [MarkdownSpan(range: 0..<9, token: .heading)])
    }

    @Test("空白のない # と 7 段以上は見出しではない")
    func hashWithoutSpaceIsNotHeading() {
        #expect(MarkdownHighlighting.spans(in: "#見出し").isEmpty)
        #expect(MarkdownHighlighting.spans(in: "####### 七段").isEmpty)
    }

    @Test("リストは記号だけが記号色で、中身は地の色のまま")
    func highlightsListMarkerOnly() {
        #expect(MarkdownHighlighting.spans(in: "- リリースは来週")
                == [MarkdownSpan(range: 0..<2, token: .marker)])
    }

    @Test("チェックボックスは箱まで記号色")
    func highlightsTaskBox() {
        #expect(MarkdownHighlighting.spans(in: "  - [x] 会場")
                == [MarkdownSpan(range: 2..<8, token: .marker)])
    }

    @Test("引用は記号と本文で色が分かれる")
    func highlightsQuote() {
        #expect(MarkdownHighlighting.spans(in: "> 次回に持ち越し") == [
            MarkdownSpan(range: 0..<2, token: .marker),
            MarkdownSpan(range: 2..<9, token: .quoteText),
        ])
    }

    @Test("閉じていないコードフェンスは末尾までコード扱い")
    func unclosedFenceRunsToTheEnd() {
        // 書いている途中は必ずこの状態を通るので、ここが崩れると打鍵中ずっと崩れる
        #expect(MarkdownHighlighting.spans(in: "```swift\nlet a = 1\nlet b = 2") == [
            MarkdownSpan(range: 0..<8, token: .marker),
            MarkdownSpan(range: 9..<18, token: .code),
            MarkdownSpan(range: 19..<28, token: .code),
        ])
    }

    @Test("閉じたフェンスの外は通常どおり")
    func closedFenceStopsAtTheClosingLine() {
        #expect(MarkdownHighlighting.spans(in: "```\nx\n```\n- 続き") == [
            MarkdownSpan(range: 0..<3, token: .marker),
            MarkdownSpan(range: 4..<5, token: .code),
            MarkdownSpan(range: 6..<9, token: .marker),
            MarkdownSpan(range: 10..<12, token: .marker),
        ])
    }

    @Test("日本語が混ざってもオフセットがずれない")
    func offsetsSurviveJapaneseText() {
        #expect(MarkdownHighlighting.spans(in: "メモ\n## 決まったこと")
                == [MarkdownSpan(range: 3..<12, token: .heading)])
    }

    @Test("空行はスパンを生まない")
    func blankLinesProduceNothing() {
        #expect(MarkdownHighlighting.spans(in: "\n\n").isEmpty)
    }
}
```

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "MarkdownHighlightingTests"
```

`cannot find 'MarkdownHighlighting' in scope` で **コンパイルエラー**が期待値。

- [ ] **Step 3: 実装する**

`Sources/NagiCore/MarkdownHighlighting.swift`:

```swift
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
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
./scripts/test.sh --filter "MarkdownHighlightingTests"
```

期待: 9 テストすべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Sources/NagiCore/MarkdownHighlighting.swift Tests/NagiCoreTests/MarkdownHighlightingTests.swift
git commit -m "Markdown の色付け（見出し・リスト記号・引用・コードフェンス）を追加"
```

---

## Task 3: 色付け — インライン要素

インラインコード、リンク、強調。Task 2 で空の `[]` を返していた `inlineSpans` を実装する。

**Files:**
- Modify: `Sources/NagiCore/MarkdownHighlighting.swift`（`inlineSpans` と補助関数）
- Test: `Tests/NagiCoreTests/MarkdownHighlightingTests.swift`（新しい `@Suite` を追加）

**Interfaces:**
- Consumes: Task 2 の `MarkdownHighlighting.spans`, `append`, `ASCII`
- Produces: 追加の公開 API はなし。`spans(in:)` の戻り値が増えるだけ

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiCoreTests/MarkdownHighlightingTests.swift` の末尾に追記:

```swift
@Suite("Markdown の色付け（インライン）")
struct MarkdownInlineHighlightingTests {
    @Test("インラインコードは記号と中身に分かれる")
    func highlightsInlineCode() {
        #expect(MarkdownHighlighting.spans(in: "`ls` を実行") == [
            MarkdownSpan(range: 0..<1, token: .marker),
            MarkdownSpan(range: 1..<3, token: .code),
            MarkdownSpan(range: 3..<4, token: .marker),
        ])
    }

    @Test("閉じていないバッククォートは無視する")
    func ignoresUnclosedBacktick() {
        #expect(MarkdownHighlighting.spans(in: "`まだ閉じてない").isEmpty)
    }

    @Test("リンクはラベルと URL で色が分かれる")
    func highlightsLink() {
        #expect(MarkdownHighlighting.spans(in: "[設計](https://a.example)") == [
            MarkdownSpan(range: 0..<1, token: .marker),     // [
            MarkdownSpan(range: 1..<3, token: .linkText),   // 設計
            MarkdownSpan(range: 3..<5, token: .marker),     // ](
            MarkdownSpan(range: 5..<22, token: .linkURL),   // https://a.example
            MarkdownSpan(range: 22..<23, token: .marker),   // )
        ])
    }

    @Test("() が続かない [] はリンクではない")
    func bracketsWithoutParensAreNotALink() {
        #expect(MarkdownHighlighting.spans(in: "[ただの角括弧]").isEmpty)
    }

    @Test("強調は記号だけを弱め、中身は地の色のまま")
    func highlightsEmphasisMarkersOnly() {
        #expect(MarkdownHighlighting.spans(in: "名前は **Nagi** で確定") == [
            MarkdownSpan(range: 4..<6, token: .marker),
            MarkdownSpan(range: 10..<12, token: .marker),
        ])
    }

    @Test("閉じていない強調は無視する")
    func ignoresUnclosedEmphasis() {
        #expect(MarkdownHighlighting.spans(in: "**書きかけ").isEmpty)
    }

    @Test("リスト記号のアスタリスクは強調と誤認しない")
    func bulletAsteriskIsNotEmphasis() {
        #expect(MarkdownHighlighting.spans(in: "* 項目 * 続き")
                == [MarkdownSpan(range: 0..<2, token: .marker)])
    }

    @Test("コードの中の記号は強調にならない")
    func codeWinsOverEmphasis() {
        #expect(MarkdownHighlighting.spans(in: "`a * b * c`") == [
            MarkdownSpan(range: 0..<1, token: .marker),
            MarkdownSpan(range: 1..<10, token: .code),
            MarkdownSpan(range: 10..<11, token: .marker),
        ])
    }

    @Test("リスト項目の中身もインライン走査される")
    func scansInsideListItems() {
        #expect(MarkdownHighlighting.spans(in: "- `x` を確認") == [
            MarkdownSpan(range: 0..<2, token: .marker),
            MarkdownSpan(range: 2..<3, token: .marker),
            MarkdownSpan(range: 3..<4, token: .code),
            MarkdownSpan(range: 4..<5, token: .marker),
        ])
    }
}
```

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "MarkdownInlineHighlightingTests"
```

期待: `highlightsInlineCode` ほか 7 件が FAIL（`inlineSpans` が `[]` を返すので、実際の値は空配列）。`ignoresUnclosedBacktick` と `bracketsWithoutParensAreNotALink` は偶然 PASS してよい。

- [ ] **Step 3: `inlineSpans` を実装する**

`Sources/NagiCore/MarkdownHighlighting.swift` の `// MARK: - inline level` 以下を、次で置き換える:

```swift
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

    private static func closingRun(
        of delimiter: UInt16,
        width: Int,
        in u: [UInt16],
        from: Int
    ) -> Int? {
        var i = from
        while i < u.count {
            if u[i] == delimiter {
                if width == 1 { return i }
                if i + 1 < u.count, u[i + 1] == delimiter { return i }
            }
            i += 1
        }
        return nil
    }

    private static func index(of unit: UInt16, in u: [UInt16], after i: Int) -> Int? {
        var j = i + 1
        while j < u.count {
            if u[j] == unit { return j }
            j += 1
        }
        return nil
    }
```

- [ ] **Step 4: 両方のスイートが通ることを確認する**

```bash
./scripts/test.sh --filter "MarkdownHighlighting|MarkdownInlineHighlighting"
```

期待: 18 テストすべて PASS（Task 2 の 9 + Task 3 の 9）。

- [ ] **Step 5: コミット**

```bash
git add Sources/NagiCore/MarkdownHighlighting.swift Tests/NagiCoreTests/MarkdownHighlightingTests.swift
git commit -m "Markdown の色付けにインラインコード・リンク・強調を追加"
```

---

## Task 4: Tab / ⇧Tab のインデント

Return より先にこちらを作る。Return の「空項目で 1 段戻る」がここの階層計算を使うため。

**Files:**
- Create: `Sources/NagiCore/MarkdownLineEditing.swift`
- Test: `Tests/NagiCoreTests/MarkdownLineEditingTests.swift`

**Interfaces:**
- Consumes: `MarkdownLines`, `BlockPrefix`（Task 1）
- Produces（`public`）:
  - `struct TextEdit: Equatable, Sendable { public let range: Range<Int>; public let replacement: String; public let caret: Int; public init(range: Range<Int>, replacement: String, caret: Int) }`
  - `enum MarkdownLineEditing { public static func indent(in text: String, caret: Int, outdent: Bool) -> TextEdit? }`
  - `internal`（Task 5 が使う）: `MarkdownLineEditing.rewritePrefix(of:prefix:to:at:in:caret:) -> TextEdit`, `MarkdownLineEditing.outdentColumn(of:in:prefix:) -> Int?`, `MarkdownLineEditing.renumbered(_:at:before:in:) -> BlockPrefix.Kind`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiCoreTests/MarkdownLineEditingTests.swift`:

```swift
import Foundation
import Testing
@testable import NagiCore

@Suite("Tab によるリストの階層操作")
struct MarkdownIndentTests {
    @Test("Tab は直前の同階層項目の本文開始位置に揃える")
    func indentAlignsToPrecedingSibling() {
        // "- 親" は 3 コード単位、2 行目は 4 から始まる
        #expect(MarkdownLineEditing.indent(in: "- 親\n- 子にする", caret: 6, outdent: false)
                == TextEdit(range: 4..<6, replacement: "  - ", caret: 8))
    }

    @Test("番号付きの親には 3 桁で揃える")
    func indentAlignsToOrderedParent() {
        // "1. 親" の本文は 3 桁目から始まるので、子も 3 桁
        #expect(MarkdownLineEditing.indent(in: "1. 親\n- 子にする", caret: 7, outdent: false)
                == TextEdit(range: 5..<7, replacement: "   - ", caret: 10))
    }

    @Test("リストの 1 行目は入れ子にできない")
    func firstItemCannotIndent() {
        #expect(MarkdownLineEditing.indent(in: "- 最初", caret: 4, outdent: false) == nil)
    }

    @Test("⇧Tab は親の位置まで戻す")
    func outdentReturnsToParentColumn() {
        #expect(MarkdownLineEditing.indent(in: "- 親\n  - 子", caret: 8, outdent: true)
                == TextEdit(range: 4..<8, replacement: "- ", caret: 6))
    }

    @Test("最上位では ⇧Tab は何もしない")
    func outdentAtTopLevelDoesNothing() {
        #expect(MarkdownLineEditing.indent(in: "- 最上位", caret: 5, outdent: true) == nil)
    }

    @Test("引用とただの本文は Tab の対象外")
    func onlyListLinesRespondToTab() {
        #expect(MarkdownLineEditing.indent(in: "> 引用\n> 続き", caret: 8, outdent: false) == nil)
        #expect(MarkdownLineEditing.indent(in: "ただの本文", caret: 5, outdent: false) == nil)
    }

    @Test("階層が変わった番号付き項目は、その行だけ番号を直す")
    func renumbersOnlyTheMovedLine() {
        // 2 行目を 1 段下げると、新しい階層では最初の項目なので "1."
        #expect(MarkdownLineEditing.indent(in: "1. 一つ目\n2. 二つ目\n3. 三つ目", caret: 13, outdent: false)
                == TextEdit(range: 7..<10, replacement: "   1. ", caret: 16))
    }

    @Test("チェック済みの状態は階層を変えても保たれる")
    func indentKeepsTheTickedState() {
        #expect(MarkdownLineEditing.indent(in: "- 親\n- [x] 済み", caret: 10, outdent: false)
                == TextEdit(range: 4..<10, replacement: "  - [x] ", caret: 12))
    }
}
```

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "MarkdownIndentTests"
```

`cannot find 'MarkdownLineEditing' in scope` で **コンパイルエラー**が期待値。

- [ ] **Step 3: 実装する**

`Sources/NagiCore/MarkdownLineEditing.swift`:

```swift
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
```

- [ ] **Step 4: テストが通ることを確認する**

```bash
./scripts/test.sh --filter "MarkdownIndentTests"
```

期待: 8 テストすべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Sources/NagiCore/MarkdownLineEditing.swift Tests/NagiCoreTests/MarkdownLineEditingTests.swift
git commit -m "Tab / ⇧Tab によるリストの階層操作を追加"
```

---

## Task 5: Return によるリストの継続

**Files:**
- Modify: `Sources/NagiCore/MarkdownLineEditing.swift`（`newline` を追加）
- Test: `Tests/NagiCoreTests/MarkdownLineEditingTests.swift`（新しい `@Suite` を追加）

**Interfaces:**
- Consumes: Task 4 の `rewritePrefix`, `outdentColumn`, `renumbered`、Task 1 の `BlockPrefix.continuation` / `hasEmptyContent`
- Produces: `MarkdownLineEditing.newline(in:caret:) -> TextEdit?`（`public`）

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiCoreTests/MarkdownLineEditingTests.swift` の末尾に追記:

```swift
@Suite("Return によるリストの継続")
struct MarkdownNewlineTests {
    @Test("箇条書きは記号を引き継ぐ")
    func continuesBullet() {
        #expect(MarkdownLineEditing.newline(in: "- 来週リリース", caret: 8)
                == TextEdit(range: 8..<8, replacement: "\n- ", caret: 11))
    }

    @Test("番号は進み、チェックは外れる")
    func advancesNumberAndClearsCheck() {
        #expect(MarkdownLineEditing.newline(in: "3. 三つ目", caret: 6)
                == TextEdit(range: 6..<6, replacement: "\n4. ", caret: 10))
        #expect(MarkdownLineEditing.newline(in: "- [x] 済み", caret: 8)
                == TextEdit(range: 8..<8, replacement: "\n- [ ] ", caret: 15))
    }

    @Test("引用も引き継ぐ")
    func continuesQuote() {
        #expect(MarkdownLineEditing.newline(in: "> 持ち越し", caret: 6)
                == TextEdit(range: 6..<6, replacement: "\n> ", caret: 9))
    }

    @Test("インデントは引き継がれる")
    func keepsIndent() {
        #expect(MarkdownLineEditing.newline(in: "  - 子", caret: 5)
                == TextEdit(range: 5..<5, replacement: "\n  - ", caret: 10))
    }

    @Test("空の項目で改行するとリストを抜ける")
    func emptyItemLeavesTheList() {
        #expect(MarkdownLineEditing.newline(in: "- 親\n- ", caret: 6)
                == TextEdit(range: 4..<6, replacement: "", caret: 4))
    }

    @Test("入れ子の空項目はまず 1 段戻る")
    func emptyNestedItemStepsOutFirst() {
        #expect(MarkdownLineEditing.newline(in: "- 親\n  - ", caret: 8)
                == TextEdit(range: 4..<8, replacement: "- ", caret: 6))
    }

    @Test("記号より手前では普通に改行する")
    func caretInsideMarkerFallsThrough() {
        #expect(MarkdownLineEditing.newline(in: "- 項目", caret: 1) == nil)
    }

    @Test("リストでない行は何もしない")
    func plainLineFallsThrough() {
        #expect(MarkdownLineEditing.newline(in: "ただのメモ", caret: 5) == nil)
        #expect(MarkdownLineEditing.newline(in: "", caret: 0) == nil)
    }

    @Test("行の途中で改行すると、後ろの文字が新しい項目になる")
    func splittingAnItemCarriesTheMarker() {
        #expect(MarkdownLineEditing.newline(in: "- 前半後半", caret: 4)
                == TextEdit(range: 4..<4, replacement: "\n- ", caret: 7))
    }
}
```

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "MarkdownNewlineTests"
```

`value of type 'MarkdownLineEditing' has no member 'newline'` で **コンパイルエラー**が期待値。

- [ ] **Step 3: 実装する**

`Sources/NagiCore/MarkdownLineEditing.swift` の `public static func indent` の**直前**に追加:

```swift
    /// Return on a line that carries a list, task or quote marker.
    ///
    /// Returns nil whenever the ordinary newline is the right answer, so the
    /// caller can simply fall through.
    public static func newline(in text: String, caret: Int) -> TextEdit? {
        let lines = MarkdownLines.split(text)
        guard let index = MarkdownLines.indexOfLine(at: caret, in: lines) else { return nil }
        let line = lines[index]
        guard let prefix = BlockPrefix.parse(line.text) else { return nil }

        // Caret still inside the marker: an ordinary newline just pushes the line
        // down, which is what the user is asking for.
        guard caret >= line.start + prefix.length else { return nil }

        if prefix.hasEmptyContent(in: line.text) {
            guard let column = outdentColumn(of: index, in: lines, prefix: prefix) else {
                // Outermost level — Return here means "I am done with this list".
                return TextEdit(range: line.start..<line.end, replacement: "", caret: line.start)
            }
            return rewritePrefix(of: line, prefix: prefix, to: column,
                                 at: index, in: lines, caret: caret)
        }

        let continuation = BlockPrefix.text(kind: prefix.continuation, indent: prefix.indent)
        return TextEdit(
            range: caret..<caret,
            replacement: "\n" + continuation,
            caret: caret + 1 + continuation.utf16.count
        )
    }
```

- [ ] **Step 4: Core のテストがすべて通ることを確認する**

```bash
./scripts/test.sh --filter "NagiCoreTests"
```

期待: 既存の Core テストと、Task 1〜5 で足した 44 テストがすべて PASS。

- [ ] **Step 5: コミット**

```bash
git add Sources/NagiCore/MarkdownLineEditing.swift Tests/NagiCoreTests/MarkdownLineEditingTests.swift
git commit -m "Return によるリストの自動継続を追加"
```

---

> **注記（Task 8 で判明）:** 以下に書かれた Escape の経路（`cancelOperation:` が responder chain で受ける、という前提）は実装中に誤りと判明し、Task 8 で修正した。現行の記述は `CLAUDE.md`「Escape is taken by the SwiftUI `.cancelAction` button in `CaptureView`」の節を参照。この計画書はそのときの記録として書き換えない。

## Task 6: `MarkdownTextView` に差し替える

ここで初めて画面が変わる。色は出るが、Return / Tab はまだ既定のまま（Task 7）。

**Files:**
- Create: `Sources/NagiUI/MarkdownTheme.swift`
- Create: `Sources/NagiUI/MarkdownTextView.swift`
- Modify: `Sources/NagiUI/CaptureView.swift`
- Modify: `CLAUDE.md`（load-bearing なルールに Escape の項を足す）
- Test: `Tests/NagiUITests/RealAppKitIntegrationTests.swift`

**Interfaces:**
- Consumes: `MarkdownHighlighting.spans`, `MarkdownToken`, `MarkdownSpan`（Task 2/3）
- Produces:
  - `@MainActor enum MarkdownTheme` — `static let font: NSFont`, `static let bodyColor: NSColor`, `static var bodyAttributes: [NSAttributedString.Key: Any]`, `static func color(for: MarkdownToken) -> NSColor`, `static func attributes(for: MarkdownToken) -> [NSAttributedString.Key: Any]`
  - `final class NagiTextView: NSTextView` — `var onCancel: (() -> Void)?`
  - `@MainActor enum MarkdownTextViewHighlighting` — `static func apply(to textView: NSTextView)`
  - `struct MarkdownTextView: NSViewRepresentable` — メンバワイズの `init(text: Binding<String>, focusToken: UUID?, onCancel: @escaping () -> Void)`、入れ子の `@MainActor final class Coordinator: NSObject, NSTextViewDelegate` に `var parent: MarkdownTextView`, `var honouredFocusToken: UUID?`

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiUITests/RealAppKitIntegrationTests.swift` の `savingThroughRealWindowWritesFile` の**後ろ**、`keyEvent` ヘルパーは既存のものを使う位置に追加:

```swift
    @Test("本文の Escape はキーイベントから hide 要求に変換される")
    func escapeInBodyReachesCancel() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        var cancelled = false
        textView.onCancel = { cancelled = true }
        panel.contentView?.addSubview(textView)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }

        #expect(panel.makeFirstResponder(textView))

        // Esc は修飾なしなので key equivalent にはならない。標準のキーバインドで
        // cancelOperation: に落ち、responder chain を上がってくる経路を実際に通す。
        textView.keyDown(with: keyEvent(characters: "\u{1B}", keyCode: 53, modifiers: []))
        #expect(cancelled)
    }

    @Test("本文にフォーカスがあっても ⌘Return はパネルが先に受け取る")
    func commandReturnWinsAgainstTheTextView() {
        bootstrapAppKit()

        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        panel.contentView?.addSubview(textView)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        #expect(panel.makeFirstResponder(textView))

        var received: [CaptureCommand] = []
        panel.onCommand = { received.append($0) }

        #expect(panel.performKeyEquivalent(with: keyEvent(characters: "\r", keyCode: 36, modifiers: [.command])))
        #expect(received == [.save])
    }

    @Test("色付けは本文全体を塗り直し、記号と地の色を塗り分ける")
    func highlightingPaintsMarkersAndBody() {
        bootstrapAppKit()

        let textView = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = "## 見出し\n- 項目"
        MarkdownTextViewHighlighting.apply(to: textView)

        guard let storage = textView.textStorage else {
            Issue.record("text storage が無い")
            return
        }
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .heading))
        #expect(storage.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? NSColor
                == MarkdownTheme.color(for: .marker))
        // 記号のうしろは地の色に戻る
        #expect(storage.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? NSColor
                == MarkdownTheme.bodyColor)
    }
```

> `MarkdownTextViewHighlighting.apply(to:)` と `MarkdownTheme.color(for:)` は、テストから塗りだけを呼べるようにするための入口。次のステップで実装する。

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "RealAppKitIntegrationTests"
```

`cannot find 'NagiTextView' in scope` で **コンパイルエラー**が期待値。

- [ ] **Step 3: `MarkdownTheme` を書く**

`Sources/NagiUI/MarkdownTheme.swift`:

```swift
import AppKit
import NagiCore

/// Colours for the body editor.
///
/// Light and dark live inside a single `NSColor` each, so nothing downstream has
/// to know which appearance it is drawing in — including the text storage, which
/// is written once and re-resolved by AppKit when the system theme flips.
///
/// `@MainActor` because these are stored `NSColor` / `NSFont` values, which are
/// not `Sendable`; the editor only ever touches them from the main actor anyway.
@MainActor
enum MarkdownTheme {
    static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static let bodyColor = dynamic(light: 0x1C1C1E, dark: 0xE4E4E6)

    /// Punctuation is deliberately low-contrast: its job is to recede. The body
    /// text is what has to stay readable.
    private static let markerColor = dynamic(light: 0x8A8F98, dark: 0x8D939C)
    private static let headingColor = dynamic(light: 0x0A58CA, dark: 0x6FA8FF)
    private static let codeColor = dynamic(light: 0x1F7A3D, dark: 0x7FCE8F)
    private static let linkColor = dynamic(light: 0x7A34C4, dark: 0xC08CF0)
    private static let quoteColor = dynamic(light: 0x6C7178, dark: 0x9AA0A8)

    static var bodyAttributes: [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: bodyColor]
    }

    static func color(for token: MarkdownToken) -> NSColor {
        switch token {
        case .heading:              return headingColor
        case .marker:               return markerColor
        case .code:                 return codeColor
        case .quoteText:            return quoteColor
        case .linkText, .linkURL:   return linkColor
        }
    }

    static func attributes(for token: MarkdownToken) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: color(for: token)]
        if token == .linkText {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private static func dynamic(light: Int, dark: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(rgb: isDark ? dark : light)
        }
    }
}

private extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
```

- [ ] **Step 4: `MarkdownTextView` を書く**

`Sources/NagiUI/MarkdownTextView.swift`:

```swift
import AppKit
import NagiCore
import SwiftUI

/// The capture window's text view.
///
/// Escape has to reach `AppEnvironment.hideCaptureWindow()`. The standard key
/// bindings send a bare Escape to `cancelOperation(_:)` and `NSTextView` does not
/// implement it, so it would travel up the responder chain on its own — but that
/// is an unwritten guarantee, and the draft the user is holding depends on it.
/// Claiming the selector here makes the route ours.
final class NagiTextView: NSTextView {
    /// Escape, outside an IME conversion.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        // While Japanese text is being converted, Escape belongs to the input
        // method — it cancels the conversion, not the note. The input context
        // normally swallows the key long before it reaches here; this makes that
        // guarantee ours rather than the system's.
        guard !hasMarkedText() else { return }
        onCancel?()
    }
}

/// Applies Markdown colouring to a text view's storage.
///
/// Split out from the coordinator so the colouring can be exercised without
/// building a SwiftUI binding.
@MainActor
enum MarkdownTextViewHighlighting {
    /// Repaints the whole document.
    ///
    /// A capture note is short, and patching only the edited paragraph gets ```
    /// fences wrong the moment one is opened or closed — that state runs past the
    /// edit in both directions. If this ever shows up in a profile, narrow it
    /// then.
    static func apply(to textView: NSTextView) {
        // Overwriting the attributes of marked text cancels the conversion on
        // screen, so an IME in flight is left alone; the commit repaints.
        guard !textView.hasMarkedText(), let storage = textView.textStorage else { return }

        storage.beginEditing()
        storage.setAttributes(MarkdownTheme.bodyAttributes,
                              range: NSRange(location: 0, length: storage.length))
        for span in MarkdownHighlighting.spans(in: textView.string) {
            let range = NSRange(location: span.range.lowerBound, length: span.range.count)
            guard NSMaxRange(range) <= storage.length else { continue }
            storage.addAttributes(MarkdownTheme.attributes(for: span.token), range: range)
        }
        storage.endEditing()

        // Otherwise a character typed straight after a code span inherits green.
        textView.typingAttributes = MarkdownTheme.bodyAttributes
    }
}

/// The body editor.
///
/// `TextEditor` cannot colour text on macOS 14 and cannot intercept Return or
/// Tab at all, and reaching into SwiftUI's own text view to add either breaks the
/// binding it owns. Owning the view outright is the only supported path.
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    /// Set by `CaptureView` when the body should take focus. The coordinator acts
    /// only on a token it has not honoured yet, so asking twice for the same
    /// field still works.
    var focusToken: UUID?
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NagiTextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.onCancel = onCancel

        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = MarkdownTheme.font
        textView.textColor = MarkdownTheme.bodyColor
        textView.typingAttributes = MarkdownTheme.bodyAttributes

        // Every one of these rewrites what the user typed, and this is a file
        // format where "--" and a curly quote are not the same as what was typed.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false

        textView.textContainerInset = NSSize(width: 10, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: .greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.maxSize = NSSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.string = text
        MarkdownTextViewHighlighting.apply(to: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NagiTextView else { return }
        context.coordinator.parent = self
        textView.onCancel = onCancel

        // Only write back when the model changed underneath us — saving,
        // stashing, discarding, or restoring a stash. Assigning on every
        // keystroke would throw the caret to the front of the document.
        if textView.string != text {
            textView.string = text
            MarkdownTextViewHighlighting.apply(to: textView)
        }

        if let focusToken, context.coordinator.honouredFocusToken != focusToken {
            context.coordinator.honouredFocusToken = focusToken
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownTextView
        var honouredFocusToken: UUID?

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            MarkdownTextViewHighlighting.apply(to: textView)
        }
    }
}
```

- [ ] **Step 5: `CaptureView` を差し替える**

`Sources/NagiUI/CaptureView.swift` の `@FocusState` の下に状態を足す:

```swift
    @FocusState private var focusedField: CaptureUIState.Field?

    /// The body is an `NSViewRepresentable`, which `@FocusState` does not reach.
    /// It gets the request's token instead and makes itself first responder.
    @State private var bodyFocusToken: UUID?
```

`bodyEditor` を差し替える:

```swift
    private var bodyEditor: some View {
        ZStack(alignment: .topLeading) {
            MarkdownTextView(
                text: $session.body,
                focusToken: bodyFocusToken,
                onCancel: onRequestHide
            )

            if session.body.isEmpty {
                Text("雑に書く。整理はあとで Claude に任せる。")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    // textContainerInset と揃える。lineFragmentPadding は 0 にしてある
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 120)
    }
```

`body` の `onChange` を差し替える:

```swift
        .onChange(of: ui.focusRequest) { _, request in
            guard let request else { return }
            switch request.field {
            case .filename:
                focusedField = .filename
            case .body:
                focusedField = nil
                bodyFocusToken = request.token
            }
            ui.focusRequest = nil
        }
```

`keyboardShortcuts` のコメントに 1 段落足す:

```swift
    /// Escape only — and only while focus is *not* in the body.
    ///
    /// ⌘Return / ⌘⇧S / ⌘, are handled by `CapturePanel.performKeyEquivalent`,
    /// because a hidden zero-sized button does not reliably win the shortcut
    /// against the focused text view. They must NOT also be bound here, or each
    /// press would fire twice — ⌘Return would write two files.
    ///
    /// Escape is bound here for the filename field. When the body has focus,
    /// `NagiTextView.cancelOperation` claims it first and does not call `super`,
    /// so the two never both fire.
    private var keyboardShortcuts: some View {
```

- [ ] **Step 6: テストが通ることを確認する**

```bash
./scripts/test.sh
```

期待: 全テスト PASS。

`escapeInBodyReachesCancel` が落ちたら、Escape が `cancelOperation:` 以外のセレクタに落ちている。`NagiTextView` に一時的に次を足して実際のセレクタ名を出し、`cancelOperation` の override をそのセレクタ用の override に置き換える（`onCancel?()` を呼んで `super` を呼ばない、という中身は同じ）。確認できたらこの override は消す。

```swift
    override func doCommandBySelector(_ selector: Selector) {
        print("doCommandBySelector: \(selector)")
        super.doCommandBySelector(selector)
    }
```

- [ ] **Step 7: 実機で見て確かめ、背景色を採取する**

```bash
pkill -f "Nagi.app/Contents/MacOS/Nagi"; ./scripts/build-app.sh && open build/Nagi.app
```

確認すること:

1. `## 見出し` が青、`` `コード` `` が緑、`[a](b)` が紫（下線つき）、`- ` と `**` が薄いグレー
2. プレースホルダの位置が、実際に打った 1 文字目と重なる
3. 日本語変換中（`かんじ` を打って変換中の状態）に色が飛ばない、Esc で変換だけ取り消せる
4. 変換を確定してから Esc を押すと窓が閉じ、もう一度出すと本文が残っている
5. ⌘Return で保存、⌘⇧S で退避、⌘, で設定が開く
6. システム設定でライト/ダークを切り替えると色が追随する

そのまま、ライト・ダークそれぞれで本文の余白部分の実効背景色を採る。次のステップで使う。

```bash
screencapture -x /tmp/nagi-light.png
```

```bash
python3 -c "
from PIL import Image; print('%02X%02X%02X' % Image.open('/tmp/nagi-light.png').convert('RGB').getpixel((900, 500)))
" 2>/dev/null || sips -g pixelWidth /tmp/nagi-light.png
```

`PIL` が無ければ macOS の「デジタルカラーメーター」（`open -a "Digital Color Meter"`）で本文の余白を指して sRGB の 16 進を読む。座標は窓の位置で変わるので、文字に当たらない余白を選ぶこと。

- [ ] **Step 8: 採った背景でコントラストを検証する**

設計書の色は透過のない背景で選んだもの。実際の背景は `.regularMaterial` なので、採った実効背景で測り直す。

`specs/contrast.py` の `CHECKS = [...]` の定義の直後（`REJECTED` の手前）に足す。サイト側は `over()` で合成しているが、こちらは実画面から採った値なので合成済み — そのまま定数に置く。

```python
# 実機のキャプチャから採った、本文領域の実効背景（.regularMaterial 合成後）。
EDITOR_LIGHT_BG = "#ECECEE"   # Step 7 で採った値に置き換える
EDITOR_DARK_BG = "#2E2E30"    # 同上

CHECKS += [
    ("エディタ 本文 (light)",   "#1C1C1E", EDITOR_LIGHT_BG, 4.5),
    ("エディタ 見出し (light)", "#0A58CA", EDITOR_LIGHT_BG, 4.5),
    ("エディタ コード (light)", "#1F7A3D", EDITOR_LIGHT_BG, 4.5),
    ("エディタ リンク (light)", "#7A34C4", EDITOR_LIGHT_BG, 4.5),
    ("エディタ 引用 (light)",   "#6C7178", EDITOR_LIGHT_BG, 4.5),
    ("エディタ 本文 (dark)",    "#E4E4E6", EDITOR_DARK_BG, 4.5),
    ("エディタ 見出し (dark)",  "#6FA8FF", EDITOR_DARK_BG, 4.5),
    ("エディタ コード (dark)",  "#7FCE8F", EDITOR_DARK_BG, 4.5),
    ("エディタ リンク (dark)",  "#C08CF0", EDITOR_DARK_BG, 4.5),
    ("エディタ 引用 (dark)",    "#9AA0A8", EDITOR_DARK_BG, 4.5),
]
```

記号（`markerColor`）は句読点として意図的にコントラストを落としているので、この検証の対象にしない。

```bash
python3 specs/contrast.py
```

期待: 追加した 10 行がすべて `OK`、終了コード 0。落ちた色は `MarkdownTheme` を調整し、設計書の配色表と `contrast.py` の値も同じに直す。

- [ ] **Step 9: `CLAUDE.md` にルールを足す**

「Rules that are load-bearing」の最後に追加:

```markdown
**Escape is claimed by `NagiTextView.cancelOperation`, and by the SwiftUI
`.cancelAction` button — never by both at once.** A bare Escape is not a key
equivalent, so it travels the responder chain: the text view sees it first when
the body has focus, the hidden button catches it when the filename field does.
`cancelOperation` deliberately does not call `super`, which is what keeps the
two from both firing. It also returns early on `hasMarkedText()`, because during
Japanese conversion Escape belongs to the input method.

**The body editor is `NSTextView`, not `TextEditor`.** Colouring and Return/Tab
handling are both impossible through `TextEditor` on macOS 14, and reaching into
SwiftUI's own text view breaks the binding it owns. The decisions live in
`NagiCore` (`MarkdownHighlighting`, `MarkdownLineEditing`) as pure functions over
UTF-16 offsets; `MarkdownTextView` only applies what they return. Keep new rules
on the Core side.
```

- [ ] **Step 10: コミット**

```bash
git add Sources/NagiUI/MarkdownTheme.swift Sources/NagiUI/MarkdownTextView.swift \
        Sources/NagiUI/CaptureView.swift Tests/NagiUITests/RealAppKitIntegrationTests.swift \
        specs/contrast.py specs/2026-08-09-markdown-input-design.md CLAUDE.md
git commit -m "本文エディタを NSTextView に置き換えて Markdown を色分けする"
```

---

## Task 7: Return / Tab を繋ぐ

**Files:**
- Modify: `Sources/NagiUI/MarkdownTextView.swift`（`Coordinator` に `textView(_:doCommandBy:)`）
- Modify: `CLAUDE.md`（テスト本数）
- Test: `Tests/NagiUITests/RealAppKitIntegrationTests.swift`

**Interfaces:**
- Consumes: `MarkdownLineEditing.newline` / `.indent`（Task 4/5）、Task 0 の確認結果
- Produces: 追加の公開 API はなし

- [ ] **Step 1: 失敗するテストを書く**

`Tests/NagiUITests/RealAppKitIntegrationTests.swift` に追加:

```swift
    /// 実際の text view に delegate を繋いで、キー由来のコマンドを流し込む。
    ///
    /// ウインドウに載せるのは undo のため。`NSResponder.undoManager` は responder
    /// chain を辿って `NSWindow` から取るので、宙に浮いた view では nil になり
    /// ⌘Z が検証できない。
    private func makeBodyEditor(text: String, caret: Int)
        -> (panel: CapturePanel, view: NagiTextView, coordinator: MarkdownTextView.Coordinator) {
        let panel = CapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 本文の書き戻し先はこれらのテストでは見ない（判定はすべて view.string）ので、
        // 束縛は定数で足りる。
        let representable = MarkdownTextView(text: .constant(""), focusToken: nil, onCancel: {})
        let coordinator = representable.makeCoordinator()

        let view = NagiTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.delegate = coordinator
        view.allowsUndo = true
        panel.contentView?.addSubview(view)
        view.string = text
        view.setSelectedRange(NSRange(location: caret, length: 0))
        return (panel, view, coordinator)
    }

    @Test("本文で Return を押すと箇条書きが引き継がれる")
    func returnContinuesBullet() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 来週リリース", caret: 8)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(editor.view.string == "- 来週リリース\n- ")
        #expect(editor.view.selectedRange().location == 11)
    }

    @Test("空の項目で Return を押すとリストを抜ける")
    func returnOnEmptyItemLeavesTheList() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 親\n- ", caret: 6)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(editor.view.string == "- 親\n")
    }

    @Test("リスト行の Tab は階層を下げ、⇧Tab は戻す")
    func tabMovesListLevels() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 親\n- 子", caret: 7)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertTab(_:))))
        #expect(editor.view.string == "- 親\n  - 子")

        editor.view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertBacktab(_:))))
        #expect(editor.view.string == "- 親\n- 子")
    }

    @Test("リストでない行の Return と Tab は横取りしない")
    func plainLinesAreLeftAlone() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "ただのメモ", caret: 5)

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)
        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertTab(_:))) == false)
        #expect(editor.view.string == "ただのメモ")
    }

    @Test("選択範囲があるときは横取りしない")
    func selectionsAreLeftAlone() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 項目", caret: 0)
        editor.view.setSelectedRange(NSRange(location: 0, length: 4))

        #expect(editor.coordinator.textView(editor.view,
                                            doCommandBy: #selector(NSResponder.insertNewline(_:))) == false)
    }

    @Test("リスト継続は ⌘Z で 1 手で取り消せる")
    func listContinuationIsOneUndoStep() {
        bootstrapAppKit()
        let editor = makeBodyEditor(text: "- 来週リリース", caret: 8)

        _ = editor.coordinator.textView(editor.view,
                                        doCommandBy: #selector(NSResponder.insertNewline(_:)))
        #expect(editor.view.string == "- 来週リリース\n- ")

        editor.view.undoManager?.undo()
        #expect(editor.view.string == "- 来週リリース")
    }
```

同ファイルの `import` に SwiftUI を足す（`.constant` を使うため）。

```swift
import SwiftUI
```

- [ ] **Step 2: 失敗を確認する**

```bash
./scripts/test.sh --filter "RealAppKitIntegrationTests"
```

期待: 新しい 6 件が FAIL。`textView(_:doCommandBy:)` が未実装なので、`NSTextViewDelegate` の既定（`false`）が返り、文字列も変わらない。

- [ ] **Step 3: `Coordinator` にキー処理を足す**

`Sources/NagiUI/MarkdownTextView.swift` の `Coordinator` に追加:

```swift
        /// Return / Tab / ⇧Tab を Core のルールに投げ、`TextEdit` が返れば適用する。
        ///
        /// `false` を返すと `NSTextView` の既定に落ちる。「リスト行以外は今までどおり」
        /// を保つのがこの分岐の役目。
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            // 変換中のキーは入力メソッドのもの。Return は変換の確定に使われる。
            guard !textView.hasMarkedText() else { return false }

            // 選択範囲があるときの Return / Tab は「置き換え」であって
            // リストの操作ではない。既定に任せる。
            let selection = textView.selectedRange()
            guard selection.length == 0 else { return false }

            let edit: TextEdit?
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                edit = MarkdownLineEditing.newline(in: textView.string, caret: selection.location)
            case #selector(NSResponder.insertTab(_:)):
                edit = MarkdownLineEditing.indent(in: textView.string,
                                                  caret: selection.location, outdent: false)
            case #selector(NSResponder.insertBacktab(_:)):
                edit = MarkdownLineEditing.indent(in: textView.string,
                                                  caret: selection.location, outdent: true)
            default:
                return false
            }

            guard let edit else { return false }
            return apply(edit, to: textView)
        }

        /// `shouldChangeText` / `didChangeText` を通す。
        ///
        /// 通さないと編集が undo スタックに乗らず、リストの継続が ⌘Z で取り消せない
        /// ——「勝手に入った記号を消せない」という、いちばん苛立つ壊れ方になる。
        private func apply(_ edit: TextEdit, to textView: NSTextView) -> Bool {
            let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
            guard textView.shouldChangeText(in: range, replacementString: edit.replacement) else {
                return false
            }
            textView.textStorage?.replaceCharacters(in: range, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: edit.caret, length: 0))
            return true
        }
```

- [ ] **Step 4: Task 0 の結果に応じて、リスト行以外の Tab を合わせる**

Task 0 の記録を読む。

- **(A) タブ文字が入っていた場合** — `NSTextView` の既定と同じなので、追加の作業はない。このステップは何もせず次へ進む
- **(B) フォーカスが移っていた場合** — `default:` の手前に次を足して、既定の「タブ文字を挿入」ではなくフォーカス移動に戻す

```swift
            case #selector(NSResponder.insertTab(_:)) where
                MarkdownLineEditing.indent(in: textView.string,
                                           caret: selection.location, outdent: false) == nil:
                // リスト行以外の Tab は、置き換え前と同じくフォーカス移動のまま。
                textView.window?.selectNextKeyView(nil)
                return true
```

- [ ] **Step 5: テストが通ることを確認する**

```bash
./scripts/test.sh
```

期待: 全テスト PASS。

- [ ] **Step 6: 実機で確かめる**

```bash
pkill -f "Nagi.app/Contents/MacOS/Nagi"; ./scripts/build-app.sh && open build/Nagi.app
```

確認すること:

1. `- あ` で Return → 次の行が `- ` で始まる。もう一度 Return → 記号が消える
2. `1. あ` で Return → `2. ` になる
3. `- [x] 済み` で Return → `- [ ] ` になる
4. 2 つ目の項目で Tab → 2 桁下がる。⇧Tab → 戻る
5. リストの中で日本語を変換中に Return を押しても、変換の確定になるだけで記号は増えない
6. リストが増えたところで ⌘Z → 1 手で元に戻る
7. Task 0 の結果どおりに、リストでない行の Tab が振る舞う

- [ ] **Step 7: `CLAUDE.md` のテスト本数を更新する**

「Testing」の節の `All 88 tests run in under a second` と `(5 of the 88)` を、実際の本数に直す。本数は次で数える。

```bash
./scripts/test.sh 2>&1 | tail -5
```

- [ ] **Step 8: コミット**

```bash
git add Sources/NagiUI/MarkdownTextView.swift Tests/NagiUITests/RealAppKitIntegrationTests.swift CLAUDE.md
git commit -m "Return でリストを継続し、Tab で階層を動かせるようにする"
```

---

## 完了条件

- [ ] `./scripts/test.sh` が全件 PASS
- [ ] `./scripts/test.sh --skip "RealAppKit"` も全件 PASS（ウィンドウサーバなしで通る）
- [ ] 実機で Task 6 Step 7 と Task 7 Step 6 の確認項目がすべて通る
- [ ] 保存された `.md` に色や装飾が混ざっていない（プレーンテキストのまま）
