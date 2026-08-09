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
