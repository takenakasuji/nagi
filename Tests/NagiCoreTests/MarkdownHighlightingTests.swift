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

    @Test("見出しは 1 段から 6 段まで")
    func headingLevelsOneThroughSix() {
        // "# 一段" は 1 + 1 + 2 = 4 コード単位
        #expect(MarkdownHighlighting.spans(in: "# 一段")
                == [MarkdownSpan(range: 0..<4, token: .heading)])
        // "###### 六段" は 6 + 1 + 2 = 9
        #expect(MarkdownHighlighting.spans(in: "###### 六段")
                == [MarkdownSpan(range: 0..<9, token: .heading)])
    }

    @Test("空白のない # と 7 段以上は見出しではない")
    func hashWithoutSpaceIsNotHeading() {
        #expect(MarkdownHighlighting.spans(in: "#見出し").isEmpty)
        #expect(MarkdownHighlighting.spans(in: "####### 七段").isEmpty)
    }

    @Test("番号付きリストは記号だけが記号色")
    func highlightsOrderedMarker() {
        #expect(MarkdownHighlighting.spans(in: "1. 最初の項目")
                == [MarkdownSpan(range: 0..<3, token: .marker)])
        // 2 桁でも記号の幅がついてくる
        #expect(MarkdownHighlighting.spans(in: "12. 十二番目")
                == [MarkdownSpan(range: 0..<4, token: .marker)])
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

    @Test("アンダースコアの強調も記号だけを弱める")
    func highlightsUnderscoreEmphasis() {
        #expect(MarkdownHighlighting.spans(in: "__太字__") == [
            MarkdownSpan(range: 0..<2, token: .marker),
            MarkdownSpan(range: 4..<6, token: .marker),
        ])
        #expect(MarkdownHighlighting.spans(in: "_斜体_") == [
            MarkdownSpan(range: 0..<1, token: .marker),
            MarkdownSpan(range: 3..<4, token: .marker),
        ])
    }

    /// CommonMark は語中の `_` を強調にしない。しないと `snake_case_name` や
    /// URL のアンダースコアが句読点色に落ちて、識別子が読みにくくなる。
    @Test("語中のアンダースコアは強調にならない")
    func intrawordUnderscoreIsNotEmphasis() {
        #expect(MarkdownHighlighting.spans(in: "snake_case_name").isEmpty)
        #expect(MarkdownHighlighting.spans(in: "https://a.example/a_b_c").isEmpty)
        // 直前が英数字でなければ従来どおり効く（行頭以外でも）
        #expect(MarkdownHighlighting.spans(in: "これは _強調_ です") == [
            MarkdownSpan(range: 4..<5, token: .marker),
            MarkdownSpan(range: 7..<8, token: .marker),
        ])
    }

    /// `*` は語中でも効く。CommonMark が禁じているのは `_` だけで、ここを一緒に
    /// 締めると `a*b*c` のような書き方が黙って死ぬ。
    @Test("語中のアスタリスクは強調のまま")
    func intrawordAsteriskStaysEmphasis() {
        #expect(MarkdownHighlighting.spans(in: "a*b*c") == [
            MarkdownSpan(range: 1..<2, token: .marker),
            MarkdownSpan(range: 3..<4, token: .marker),
        ])
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
