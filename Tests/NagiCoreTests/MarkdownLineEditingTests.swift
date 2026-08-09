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
