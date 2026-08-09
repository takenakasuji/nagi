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
