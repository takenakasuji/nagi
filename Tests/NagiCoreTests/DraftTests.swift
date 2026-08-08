import Foundation
import Testing
@testable import NagiCore

@Suite("Draft")
struct DraftTests {
    @Test("表示名は本文の最初の非空行")
    func displayTitleUsesFirstBodyLine() {
        let draft = Draft(filename: "ignored", body: "# 会議メモ\n本文が続く")
        #expect(draft.displayTitle == "# 会議メモ")
    }

    @Test("表示名は先頭の空行を飛ばす")
    func displayTitleSkipsBlankLines() {
        let draft = Draft(body: "\n\n   \n実質の1行目")
        #expect(draft.displayTitle == "実質の1行目")
    }

    @Test("本文が空ならファイル名にフォールバック")
    func displayTitleFallsBackToFilename() {
        let draft = Draft(filename: "名前だけ", body: "   \n  ")
        #expect(draft.displayTitle == "名前だけ")
    }

    @Test("どちらも空ならプレースホルダ")
    func displayTitleFallsBackToPlaceholder() {
        #expect(Draft(filename: "", body: "").displayTitle == "(空のメモ)")
    }

    @Test("isEmpty は両フィールドの空白を無視する")
    func isEmptyIgnoresWhitespace() {
        #expect(Draft(filename: " ", body: " \n\t").isEmpty)
        #expect(!Draft(filename: "", body: "a").isEmpty)
        #expect(!Draft(filename: "a", body: "").isEmpty)
    }
}
