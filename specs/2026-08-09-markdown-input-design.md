# 本文エディタを Markdown フレンドリーにする — 設計

2026-08-09

## 目的

本文の入力体験を Markdown 寄りにする。狙いは 2 つ。

1. 書いている最中に構造が見える（`## ` と打てば見出しの色になる）
2. リストが手で書き足す作業にならない（Return で記号が引き継がれ、Tab で階層が動く）

**プレビューは作らない。** 保存される `.md` の中身は今までと 1 バイトも変わらず、色は表示だけの話。整理は後段の Claude Code / Obsidian に任せるという方針も変えない。

## 決めたこと

| 項目 | 決定 |
|---|---|
| 見出しの強調 | **色だけ**。太さもサイズも本文と同じ 13pt 等幅 |
| 配色 | **3 色** — 見出し＝青、コード＝緑、リンク＝紫。記号類は薄グレー |
| 色を付ける記法 | 見出し / リスト記号 / コード / 引用 / 強調 / リンク |
| Return で継続 | `- * +` / `1.` / `- [ ]` / `>` |
| Tab | リスト行のときだけ階層操作。それ以外の行では従来どおり |

見出しのサイズを変えないのは、`#` を打った瞬間に行が育って以降の行が下にずれるのを避けるため。速く書くための窓なので、打鍵に対して画面が動かないことを優先する。

配色を 3 色に絞ったのは、日本語のメモに 6 色は賑やかすぎる一方、「構造（見出し）」と「そのまま貼りたいもの（コード・URL）」の区別は実利があるため。

## 実装アプローチ

`TextEditor` を `NSTextView` を包んだ自前ビューに置き換える。

デプロイターゲットは macOS 14 で、`TextEditor` が `AttributedString` を受けられるのは macOS 26 から。配布サイトの計画がある中で対応 OS を 14 → 26 に切り上げる代償は、色付けの実装が楽になる分より遥かに大きい。また仮に上げたとしても Return / Tab の横取りは `TextEditor` ではできない。

`TextEditor` の内部の `NSTextView` をビュー階層から探して delegate を差し込む手も検討したが、SwiftUI が自分の delegate を設定しているため奪うと binding が壊れる。OS 更新で無言で壊れる類なので採らない。

## 構成

新規ファイルは 4 つ。既存の分担（Core は純粋、UI は薄いアダプタ）をそのまま踏襲する。

| ファイル | 役割 |
|---|---|
| `NagiCore/MarkdownHighlighting.swift` | 文字列 → 「どこが何か」のスパン列。色は知らない |
| `NagiCore/MarkdownLineEditing.swift` | Return / Tab を押したときの文字列編集を計算する。キーは知らない |
| `NagiUI/MarkdownTextView.swift` | `NSViewRepresentable` + `NSTextView` サブクラス。上の 2 つを呼ぶだけ |
| `NagiUI/MarkdownTheme.swift` | スパン種別 → `NSColor` |

`CaptureView.bodyEditor` の `TextEditor` がこの `MarkdownTextView` に差し替わる。プレースホルダの `ZStack` オーバーレイは今のまま流用する。ただし出す条件は `session.body.isEmpty` だけでは足りない: 変換中は `textDidChange` が飛ばないので `body` は `""` のままで、プレースホルダが打ちかけの日本語の**上に**重なる。`NagiTextView` が `setMarkedText` / `unmarkText` から変換状態を報せ、その間は出さない。

**オフセットは UTF-16 で統一する。** `NSTextStorage` が UTF-16 で動くので、Core も `Range<Int>`（UTF-16 単位）で返す。日本語や絵文字が入った瞬間に `String.Index` との往復でずれるのを、境界をひとつに決めて防ぐ。

## `MarkdownHighlighting`

```swift
public enum MarkdownToken {
    case heading     // "## 決まったこと" の行全体   → 青
    case marker      // - * + 1. [ ] > ** ` [ ]( )  → 薄グレー
    case code        // ` ` の中身、``` ブロックの中身 → 緑
    case quoteText   // > の後ろ                    → やや薄い地の色
    case linkText    // [ ] の中身                  → 紫 + 下線
    case linkURL     // ( ) の中身                  → 紫
}

public struct MarkdownSpan: Equatable {
    public let range: Range<Int>   // UTF-16 オフセット
    public let token: MarkdownToken
}

public enum MarkdownHighlighting {
    public static func spans(in text: String) -> [MarkdownSpan]
}
```

これに載らない範囲は地の色。UI 側は「全部を地の色にリセット → スパンを塗る」だけなので、消し忘れが起きない。

強調（`**` / `*` / `_`）に固有の色は与えない。記号を薄グレーにするだけで、囲まれた文字は地の色のまま残る。太字にもしない — 見出しでサイズも太さも変えないと決めた以上、強調だけ太くすると行の高さが動く場所ができてしまう。

行単位の 1 パス走査で、``` の内外だけを状態として持つ。閉じていない ``` は、そこから末尾までコード扱いにする（書いている途中は必ずこの状態を通るため）。

線引き:

- 見出しは行頭の `#` が 1〜6 個 + 空白の行のみ。`#見出し` は見出しではない
- `- [ ]` / `- [x]` は `-` の直後に限る。`[x]` の判定は大文字小文字を問わない
- `1.` は行頭の数字 + `.` + 空白に限る
- インラインコードは同一行で閉じているものだけ。行をまたいだ `` ` `` は無視する

### 配色

`NSColor(name:dynamicProvider:)` で 1 つの色にライト/ダーク両方を持たせる。背景は `.regularMaterial`（半透明）なので、後ろのウィンドウの明るさで実効背景が揺れる。数値は実効背景で測り直す（`specs/contrast.py` を使う）。

| 用途 | Light | Dark |
|---|---|---|
| 地の色 | `#1C1C1E` | `#E4E4E6` |
| 記号（marker） | `#8A8F98` | `#8D939C` |
| 見出し | `#0A58CA` | `#6FA8FF` |
| コード | `#1F7A3D` | `#7FCE8F` |
| リンク | `#7A34C4` | `#C08CF0` |
| 引用の本文 | `#666B72` | `#9AA0A8` |

記号のグレーは意図的にコントラストを落としている（句読点的な要素を弱めるため）。本文が読めるコントラストを持つことが要件で、記号がそこに達する必要はない。

背景は実装後に採り直した（ライト `#F4F4F4` / ダーク `#2F2F2F`）。ただしこれは**実効背景ではない**: オフスクリーンの `cacheDisplay(in:to:)` から読んだ値で、背後の合成が入らないため `.regularMaterial` の不透明フォールバックにあたる。実機の窓を明暗の下地の上で測り直す作業は未了（`specs/contrast.py` の注記を参照）。引用の本文のライト側は当初 `#6C7178` だったが、この背景で 4.47:1 と 4.5 に届かなかったため `#666B72` に落とした。合成後の背景がこれより暗くなる可能性があるぶんの余裕も見込んでいる。

## `MarkdownLineEditing`

戻り値は「どこを何に差し替えて、カーソルをどこに置くか」だけ。キーコードも `NSTextView` も出てこない。

```swift
public struct TextEdit: Equatable {
    public let range: Range<Int>      // 元テキストへの UTF-16 レンジ
    public let replacement: String
    public let caret: Int             // 置換後テキストでのカーソル位置
}

/// Tab / ⇧Tab の答え。「何も起きない」が 2 種類あるので `TextEdit?` では足りない
public enum ListIndent: Equatable, Sendable {
    case notAList        // リスト行ではない。呼び出し側は従来どおり（＝タブ文字）
    case nowhereToMove   // リスト行だが動かす先がない。キーは食う（タブ文字を入れない）
    case edit(TextEdit)
}

public enum MarkdownLineEditing {
    /// nil = 普通に改行させる
    public static func newline(in text: String, caret: Int) -> TextEdit?
    public static func indent(in text: String, caret: Int, outdent: Bool) -> ListIndent
}
```

`indent` が `ListIndent` を返すのは、「リストの 1 行目では何もしない」を UI 側が
再導出しなくて済むようにするため。両方を `nil` で返していたときは、`- 最初` で Tab を
押すと `NSTextView` の既定が走って目に見えないタブ文字が `.md` に書き込まれていた。

### Return

1. カーソルのある行の頭に `- ` / `* ` / `+ ` / `1. ` / `- [ ] ` / `> ` があるか見る。なければ `nil`
2. 記号の後ろが空（`- ` だけの行）→ 1 段アウトデントする（下の ⇧Tab と同じ計算）。最上位ならその行を空行にする（＝リスト解除）
3. それ以外 → 改行して同じ記号を置く。番号は +1、`- [x]` の次は `- [ ]`
4. カーソルが記号より手前にあるときは `nil`（行の上に空行が入るだけの素直な挙動）

番号の振り直しは「その場で足す」だけで、以降の行には触れない。Markdown は `1.` が並んでいても正しく採番されるので実害がなく、書いている最中に下の行が勝手に書き換わる方が怖い。

### Tab

- 行頭が `- ` / `* ` / `+ ` / `1. ` / `- [ ] ` のときだけ効く。それ以外は `nil` を返す
- Tab は**ひとつ上の項目の本文開始位置に揃える**。`- ` の下なら 2 桁、`1. ` の下なら 3 桁。CommonMark はここが揃っていないとネストと解釈しないので、固定幅ではなく親に合わせる
- 上に親がない（リストの 1 行目）ときは何もしない
- ⇧Tab は 1 段戻す
- 階層が変わった行が番号付きなら、その行の番号だけ新しい階層に合わせて直す。他の行は触らない

## `MarkdownTextView`

`NSScrollView` の中に `NagiTextView: NSTextView`。Coordinator が `NSTextViewDelegate`。

**テキストの同期。** `updateNSView` は `textView.string` と binding が食い違うときだけ書き戻す。毎回代入するとカーソルが先頭に飛ぶ。書き戻しが要るのは `DraftSession` が外から `body` を差し替えるとき、つまり保存・退避・破棄の後の `resetBuffer()` と、退避から戻す `openStash()` だけ。

**色の塗り直し。** 変更のたびに全体を「地の色にリセット → スパンを塗る」。メモ 1 枚分なので全走査で十分速く、部分更新は ``` の開閉で状態が前後に伝播する分だけ確実に間違える。速さが問題になってから狭める。`typingAttributes` も地の色に固定して、コードの直後に打った文字が緑を引き継がないようにする。

**Return / Tab。** `doCommandBy` で `insertNewline(_:)` / `insertTab(_:)` / `insertBacktab(_:)` を受け、Core に投げて `TextEdit` が返れば適用、`nil` なら `false` を返して既定に任せる。適用は `shouldChangeText(in:replacementString:)` → 置換 → `didChangeText()` の順で通す。これを通さないと ⌘Z が効かず、リスト継続が undo できない編集になる。

Tab は**先に現状の挙動を実機で確認する**。`TextEditor` が Tab をタブ文字として食っているのか、ファイル名欄へフォーカスを移しているのかで「今までどおり」の中身が変わる。実装前に確認して合わせる。

**フォーカス。** `@FocusState` は `NSViewRepresentable` に対しては当てにならない。`CaptureView` の `onChange(of: ui.focusRequest)` を行き先で振り分ける。

```swift
case .filename: focusedField = .filename
case .body:     bodyFocusToken = request.token   // @State、下に渡すだけ
```

representable は受け取ったトークンが前回と違えば `makeFirstResponder` する。ビュー更新中に observable を書き換えないので、状態変更の警告も出ない。

## 壊さないもの

**⌘Return / ⌘⇧S / ⌘,** — `CapturePanel.performKeyEquivalent` はウィンドウが first responder より先に見るので、中身が `NSTextView` に変わっても無関係。変更しない。

**Escape** — `.cancelAction` に届く、という見立ては当たったが、経路の見立ては外れた。実測: 素の Esc は key equivalent の段（responder chain より**先**）で受け付けられ、変換中でなければ `NSHostingView` の中の `.cancelAction` ボタンがそこで消費する。変換中は `CapturePanel.performKeyEquivalent` が `super` を呼ばずに `false` を返すため隠しボタンには届かず、通常の `keyDown` 配送 → `interpretKeyEvents` を経て入力メソッドに渡る——responder chain に届くのはこの変換中の経路だけで、その経路でも `hasMarkedText()` で即座に入力メソッドへ譲るほかない。したがって `NagiTextView` に `cancelOperation` の override は**置かない**（置いてもどちらの経路でも死にコード）。テストは `RealAppKitIntegrationTests` にある。

**IME** — marked text がある間は色を塗り直さず、Return / Tab も横取りしない。**Esc も渡す**: `.cancelAction` ボタンは変換中かどうかを見ないので、そのままだと変換中の Esc で窓が閉じ、**打ちかけの読みが黙って消える**。実測: `setMarkedText` は `textDidChange` を一度も飛ばさない（切り離した text view でも、キーパネルに載せて first responder にした text view でも同じ。同じ delegate が `insertText` と `string =` の通知は現に受け取っている）。つまり未確定の文字列は `session.body` に一度も届かず、`suspend()` にも残らない——残るのではなく、消える。`CapturePanel.performKeyEquivalent` が、素の Esc かつ first responder が `hasMarkedText()` のときだけ `super` を呼ばずに `false` を返す。`super` を呼ばないので隠しボタンはこの Esc を見ず、`false` を返すので通常の `keyDown` 配送に進み、`interpretKeyEvents` から入力メソッドへ渡って変換が取り消される。判定は `firstResponder as? NSTextInputClient` で、本文の `NagiTextView` とファイル名欄のフィールドエディタ（SwiftUI の `_SystemTextFieldFieldEditor`）の両方を拾う。

**下書きの永続化** — `AppEnvironment.hideCaptureWindow()` のまま。今回の変更は一切触れない。

## テスト

Core（ウィンドウ不要、既存 88 本と同じ速さ）:

- `MarkdownHighlightingTests` — 見出し 1〜6 段、`#見出し`（空白なし）は見出しではない、`- [ ]` / `- [x]`、`1.`、`>`、インラインコード、閉じていない ```、リンク、強調（`**` / `__` / `_`）、語中の `_` は強調にしない（`*` はする）、日本語混じりでオフセットがずれないこと
- `MarkdownLineEditingTests` — 継続、空項目でアウトデント→解除、番号 +1、`[x]` → `[ ]`、記号より手前で Return、Tab の親揃え、リスト 1 行目の Tab は `nowhereToMove`（`notAList` と区別できること）、⇧Tab、階層変更時の番号だけ直る

`RealAppKitIntegrationTests`（要ウィンドウサーバ）:

- Esc が `onRequestHide`（テストではログ用スタブ）に届く。本番配線（`CaptureWindowController` が `env.hideCaptureWindow()` に接続）と、その先の永続化（`hideCaptureWindow()` → `session.suspend()` → `window?.hide()`）は `AppEnvironmentTests` の「ウインドウを隠すと書きかけが永続化される」が別途担保する
- 変換中の Esc は key equivalent の段で降り、窓が閉じない（本文・ファイル名欄の両方）
- ⌘Return がまだ `save()` に届く
- リスト行で Tab がインデントする
- リストの 1 行目で Tab を押してもタブ文字が入らない。リストでない行では入る（`doCommand(by:)` で既定まで通して測る）
- 最上位の ⇧Tab は本文もフォーカスも動かさない
- ファイル名欄の Return が本文へのフォーカス要求になる
- 変換中は `textDidChange` が飛ばない（`insertText` の対照つき）。その報せが `NagiTextView` から出ること、本文エディタが受け取っていること、そして受け取って走る更新が変換を消さないこと

テストは日本語で命名する（既存に合わせる）。

## やらないこと

- プレビュー
- ⌘B / ⌘I などの装飾ショートカット
- 見出しのサイズ変更・太字
- 番号付きリスト全体の振り直し
- 本文フォントの変更（13pt 等幅のまま）
