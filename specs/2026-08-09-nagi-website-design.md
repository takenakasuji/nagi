# Nagi 配布サイト 設計書

- 日付: 2026-08-09
- 状態: 承認済み（実装計画待ち）
- 公開先: https://takenakasuji.github.io/nagi/

## 何を作るか

Nagi の配布ページ。1 枚もの・縦スクロールのランディングページを 1 つだけ作り、
GitHub Pages で公開する。訪問者のゴールは **Nagi を手に入れて動かすこと**。

日本語のみ。アプリの UI も README も日本語なので、サイトだけ英語にすると齟齬が出る。

### 作らないもの

- 複数ページのドキュメントサイト（README がその役目を持ち続ける）
- 英語版（将来必要になったら別途）
- 静的サイトジェネレータ、Node、GitHub Actions のビルド工程
- ブログ、更新履歴ページ、アナリティクス、フォーム

## 前提と制約

| 事項 | 現状 | サイトへの影響 |
|------|------|----------------|
| git | **未初期化**（`.git` なし） | `git init` → GitHub に push が最初の一歩 |
| 配布物 | ad-hoc 署名のみ。Developer ID 署名・公証なし | 初回起動の Gatekeeper 回避手順をサイトに明記する必要がある |
| 入手経路 | ソースビルドのみ。Releases なし | 「ダウンロード」は GitHub Releases の最新版を指す。Homebrew cask は将来対応、枠だけ確保 |
| 対応 OS | `Package.swift` の `platforms: [.macOS(.v14)]` | ヒーローに「macOS 14 Sonoma 以降」と明記 |
| ライセンス | **LICENSE ファイルなし** | MIT で追加する。footer に表示 |
| メニューバーアイコン | SF Symbol `wind`（`NagiApp.swift:15`） | **SF Symbols は Apple プラットフォーム外で再配布できない。** Web では使えないので自作 SVG を描く |

## 配置とデプロイ

```
nagi/
  docs/                 ← GitHub Pages の公開ルート
    index.html
    style.css
    nagi-mark.svg       ロゴ（自作の風マーク）
    favicon.svg
    .nojekyll
  specs/                ← 設計書。docs/ の外に置く（下記）
    2026-08-09-nagi-website-design.md
  .gitignore
  LICENSE
```

GitHub の Settings → Pages で **Deploy from a branch → `main` / `/docs`**。

- **なぜ `gh-pages` ブランチでなく `docs/` か**: サイトのソースが本体と同じブランチに同居し、
  ブランチ間の同期運用が要らない。ビルド工程がないので分ける利点がない。
- **なぜ `.nojekyll` か**: Jekyll のビルドを挟まないほうが速く、挙動が予測できる。
- **なぜ設計書を `docs/` の外に置くか**: `docs/` 配下は丸ごとサイトとして配信されるため、
  設計書を中に入れると `https://takenakasuji.github.io/nagi/specs/...` で読めてしまう。

## ページ構成

上から順に 7 セクション。

### 1. ヒーロー

- 風マーク（SVG）
- H1: **Nagi（凪）**
- リード: 「AI 時代のメモ帳。雑に書いて、速く貯める。」
- サブ: ホットキーで窓を出し、思考を止めずに書き、指定フォルダに `.md` を吐く。
  整理・リネーム・構造化はあとから Claude Code や Obsidian に任せる。
- 主 CTA: **ダウンロード** → GitHub Releases の最新版
- 副 CTA: **GitHub で見る** → リポジトリ
- 動作環境: 「macOS 14 Sonoma 以降 · 無料 · MIT ライセンス」

### 2. 入力窓のモック

`Sources/NagiUI/CaptureView.swift` の見た目を HTML/CSS で再現する。実スクリーンショットは撮らない。

再現する要素（実装と一致させる）:

| 部位 | 内容 | 実装の対応箇所 |
|------|------|----------------|
| ファイル名欄 | ドキュメントアイコン + プレースホルダ「ファイル名（.md は自動）」 | `CaptureView.swift:41-58` |
| 区切り線 | 上下 2 本 | `CaptureView.swift:23-29` |
| 本文 | モノスペース。プレースホルダ「雑に書く。整理はあとで Claude に任せる。」 | `CaptureView.swift:60-79` |
| ツールバー左 | 「退避」ボタン（トレイアイコン）、歯車ボタン | `CaptureView.swift:83-108` |
| ツールバー右 | 「退避 ⌘⇧S」、「保存 ⌘↩」（塗りつぶし＝主アクション） | `CaptureView.swift:120-127` |
| 窓の比率 | 660 × 440 | `CaptureWindowController.swift:67` |

窓の脇に `⌥Space` のキーキャップを添え、「押すと出る」ことを一目で伝える。

### 3. 3つの原則

Nagi が何をしないかを 3 つ。アイコン + 見出し + 2 行。

1. **アプリに AI は入っていない** — 責務は「捕まえて、置く」だけ。整理はあとで Claude Code や Obsidian に任せる。
2. **既存ファイルを上書きしない** — 同名があれば `名前-2.md` と連番を付ける。
3. **書きかけが消えない** — Esc で閉じても内容は残り、次に開くと続きから。保存しないメモは何件でも退避できる。

### 4. キーボード

README の操作表をそのまま `<table>` で。キーは `<kbd>` 要素。

| 操作 | 動作 |
|------|------|
| `⌥Space` | メモ入力ウインドウを開く／閉じる（設定で変更可） |
| `⌘Enter` | 指定フォルダに `<ファイル名>.md` として保存し、ウインドウを閉じる |
| `⌘⇧S` | 書きかけを退避し、エディタを空にする |
| `Esc` | ウインドウを隠す。内容は消えず、次に開くと続きから |
| `Enter`（ファイル名欄） | 本文へ移動（誤って保存しないため） |
| `⌘,` | 設定を開く |

### 5. インストール

番号付きの 4 ステップ:

1. ダウンロードして解凍
2. `Nagi.app` を `/Applications` に入れる
3. **初回だけ、右クリック →「開く」** — ad-hoc 署名のため、ダブルクリックでは開けない。
   なぜそうなるかを 1 行で説明する（隠さない）
4. 保存先フォルダを選ぶ — Obsidian の Vault や Claude Code の作業フォルダを指定する

その下に折りたたみで「ソースからビルドする」:

```bash
git clone https://github.com/takenakasuji/nagi.git
cd nagi && ./scripts/build-app.sh && cp -R build/Nagi.app /Applications/
```

Homebrew 用の枠を 1 ブロック確保し、現時点では「準備中」と明示する。
リンク先が未定のプレースホルダを本文に散らさず、ここ 1 箇所に閉じ込める。

### 6. 正直な制限

README の「既知の制限」をユーザー向けの言葉に直して載せる。隠さないことが Nagi の性格に合う。

- **ホットキーの衝突は検出できないことがある** — macOS は他アプリが同じ組み合わせを握っていても
  登録を成功として返す。反応しないときは設定で別のキーに変える
- **ad-hoc 署名** — 初回だけ右クリック →「開く」が要る
- **非サンドボックス** — 保存先はパスとして保持している。App Store 配布はしていない
- **メニューバーのアイコンが見えないことがある** — ノッチ付き MacBook でメニューバーが埋まっていると、
  後から起動したアプリのアイコンはノッチに押し出されて見えなくなる。アイコンは存在していて機能もしている

### 7. footer

GitHub リポジトリ · MIT License · 作者

## ビジュアル設計

### ロゴ

メニューバーは SF Symbol `wind` を使っているが、SF Symbols は Apple プラットフォーム外での
再配布ができないため Web には持ち込めない。`wind` に着想を得た**自作の SVG** を描く
（凪いだ水面を渡る 3 本の流線、`stroke-linecap: round`、`currentColor` で色を継承）。
ロゴと favicon で同一ファイルを共用する。

### カラー

セマンティックな CSS カスタムプロパティで定義し、`prefers-color-scheme` で切り替える。
生の 16 進数はセレクタに直書きしない（HIG のダイナミックカラーの考え方をそのまま CSS に落とす）。

| トークン | ライト | ダーク |
|----------|--------|--------|
| `--bg` | `#FFFFFF` | `#1C1C1E` |
| `--bg-subtle` | `#F5F5F7` | `#000000` |
| `--label` | `#1D1D1F` | `#F5F5F7` |
| `--label-secondary` | `#6E6E73` | `#A1A1A6` |
| `--separator` | `rgba(0,0,0,.10)` | `rgba(255,255,255,.14)` |
| `--accent`（リンク） | `#0060DF` | `#0A84FF` |
| `--accent-fill`（CTA の塗り） | `#0060DF` | `#0A6ADF` |
| `--accent-on-fill` | `#FFFFFF` | `#FFFFFF` |

ダークの `--bg-subtle` はライトと逆に `--bg` より暗い（`#000000`）。macOS のダーク外観と同じく、
セクションの交互背景を「沈める」方向で表現する。ダークのテキスト系トークンは
`#1C1C1E` と `#000000` の**両方**で 4.5:1 を満たす（`#000000` 上では
`#F5F5F7` 19.29:1 / `#A1A1A6` 8.16:1 / `#0A84FF` 5.76:1）。

実測したコントラスト比（WCAG 2.x、`specs/contrast.py` で算出。再実行して検証できる）:

| 組み合わせ | 比 | 判定 |
|-----------|-----|------|
| `#1D1D1F` on `#FFFFFF` | 16.83:1 | 合格 |
| `#6E6E73` on `#FFFFFF` | 5.07:1 | 合格 |
| `#6E6E73` on `#F5F5F7` | 4.66:1 | 合格 |
| `#0060DF` on `#FFFFFF` | 5.62:1 | 合格 |
| 白 on `#0060DF` | 5.62:1 | 合格 |
| `#F5F5F7` on `#1C1C1E` | 15.63:1 | 合格 |
| `#A1A1A6` on `#1C1C1E` | 6.61:1 | 合格 |
| `#0A84FF` on `#1C1C1E` | 4.66:1 | 合格 |
| 白 on `#0A6ADF` | 5.07:1 | 合格 |

**却下した値**: macOS の system blue `#007AFF` は白文字で 4.02:1、`#FFFFFF` 上でも 4.02:1 しかなく、
本文サイズの 4.5:1 を満たさない。`#0060DF` に落とした。
ダークの CTA も `#0A84FF` の塗り＋白文字は 3.65:1 で不足するため、塗りだけ `#0A6ADF` に落とす
（リンク色としての `#0A84FF` は 4.66:1 で合格なのでそのまま使う）。

**一貫性**: モック内の「保存 ⌘↩」ボタンとページの主 CTA に同じ `--accent-fill` を使い、
「この青＝主アクション」の意味を統一する。装飾目的でこの青を使わない。
（Design Guideline — Color > Best practices: "Avoid using the same color to mean different things."）

「3 段階目のラベル色（tertiary）」は本文には使わない。モックのプレースホルダ表現だけに限定する。

### タイポグラフィ

- 本文: `-apple-system, BlinkMacSystemFont, "Hiragino Sans", "Noto Sans JP", sans-serif`
- モックの本文とコード: `ui-monospace, SFMono-Regular, Menlo, monospace`
- 書体はこの 2 系統のみ
  （Design Guideline — Typography: "Minimize the number of typefaces you use."）
- スケール: 48 / 32 / 22 / 17 / 14 px の 5 段。すべて `rem` で表現
- **ウェイトは 400 / 500 / 600 / 700 のみ**。300 以下は使わない
  （Design Guideline — Typography: "avoid Ultralight, Thin, and Light font weights"）
- 本文 17px、最小 14px

### マテリアル

モック窓は `backdrop-filter: blur(20px)` + 半透明背景で `.regularMaterial` を模す
（実装は `CaptureView.swift:30` の `.background(.regularMaterial)`）。
単色背景の上では blur が視覚的に無意味なので、ヒーローに淡いグラデーション（凪いだ水面）を敷き、
その上に窓を重ねる。`@supports not (backdrop-filter: blur(1px))` で非対応ブラウザには
不透明の背景を返す。
（Design Guideline — Materials: "Test materials with different background content."）

### モーション

スクロールに応じた控えめなフェードインのみ。`prefers-reduced-motion: reduce` で全停止する。
（Design Guideline — Accessibility > Cognitive: "ensure your app responds by reducing automatic
and repetitive animations."）

## アクセシビリティ要件（実装の受け入れ条件）

これを満たさないものは未完成とみなす。

1. 本文 17px・最小 14px。`rem` ベースで **ブラウザのズーム 200% でレイアウトが壊れない**
   （Design Guideline — Accessibility > Vision: "give people the option to enlarge text by at
   least 200 percent."）
2. すべてのテキストが 4.5:1 以上。18px 以上または太字は 3:1 以上。**ライト・ダーク両方で確認**
3. 色だけで情報を伝えない。「正直な制限」の各項目は色でなくアイコンと見出しで区別する
4. クリック対象は 44×44px 以上。HIG のデスクトップ最小は 20×20 だが、Web にはタッチデバイスも
   来るため厳しいほうを採る
5. `prefers-reduced-motion: reduce` で全アニメーション停止
6. 見出し階層 h1 → h2 → h3 を飛ばさない
7. SVG に `role="img"` と `<title>`、表に `<caption>`、装飾 SVG は `aria-hidden`
8. `:focus-visible` のリングが両テーマで視認できる。キーボードだけで全 CTA に到達できる
9. 言語指定 `<html lang="ja">`

## 検証方法

静的サイトなのでテストコードは置かない。実装後に以下を実行して結果を残す。

```bash
python3 -m http.server 8000 --directory docs
```

1. **表示**: ライト / ダーク × 幅 375 / 768 / 1280 の 6 通りをブラウザで確認。
   いずれでも `document.documentElement.scrollWidth <= innerWidth`（横スクロールが出ない）
2. **ズーム**: 200% で本文が読め、要素が重ならないこと
3. **キーボード**: Tab だけで「ダウンロード」「GitHub で見る」「ソースからビルド」の展開に到達でき、
   フォーカスリングが見えること
4. **コントラスト**: `python3 specs/contrast.py` を実行し、上の表と一致することを確認。
   ヒーローのグラデーション上に載るテキストは、グラデーションの**最も明るい点と最も暗い点の
   両方**で測って 4.5:1 を満たすこと
5. **リンク**: 外部リンクが全て 200 を返すこと（Releases は初回リリース後）
6. **モーション**: OS の「視差効果を減らす」を有効にしてアニメーションが止まること

## 実装の順序

1. `git init` → `.gitignore`（`.build/`、`build/`、`.DS_Store`）→ 初回コミット
2. `LICENSE`（MIT）を追加
3. `docs/nagi-mark.svg` — 風マークを描く
4. `docs/index.html` — セクション 1〜7 のマークアップ（意味づけ優先、装飾は後）
5. `docs/style.css` — カラートークン → タイポグラフィ → レイアウト → モック → モーション の順
6. 検証（上記 6 項目）
7. GitHub にリポジトリ作成 → push → Settings → Pages で `main` / `/docs` を設定
8. `build-app.sh` の出力を zip にして最初の Release を作成し、ダウンロードリンクを実在させる

## 未解決事項

- **最初の Release を作るまで、ダウンロード CTA のリンク先は存在しない。**
  リンク先は `https://github.com/takenakasuji/nagi/releases/latest` とし、
  Release 作成までは 404 になる。手順 8 で解消する。
- Homebrew cask は将来対応。サイトには枠と「準備中」の表示のみ置く。
