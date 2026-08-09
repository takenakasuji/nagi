# Nagi 配布サイト 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Nagi の配布ページを 1 枚もののランディングページとして作り、GitHub Pages（`https://takenakasuji.github.io/nagi/`）で公開する。

**Architecture:** ビルド工程を持たない静的サイト。`docs/` に `index.html`・`style.css`・SVG 2 枚を置き、GitHub Pages の「Deploy from a branch → `main` / `/docs`」でそのまま配信する。CSS はセマンティックなカスタムプロパティ 1 層をルートに定義し、`prefers-color-scheme` でライト／ダークを切り替える。JavaScript は使わない。

**Tech Stack:** HTML5 / CSS（カスタムプロパティ、`clamp()`、CSS Grid、`backdrop-filter`、`animation-timeline: view()`）/ SVG。検証は Python 標準ライブラリのみ（`http.server`、`specs/contrast.py`）。

**設計書:** [`specs/2026-08-09-nagi-website-design.md`](2026-08-09-nagi-website-design.md)

## Global Constraints

すべてのタスクの要件に、以下が暗黙に含まれる。

- **言語は日本語のみ。** `<html lang="ja">`。英語版は作らない。
- **JavaScript を書かない。** 動きが必要なら CSS で表現し、非対応環境では静止して劣化する。
- **ビルド工程を作らない。** Node、npm、GitHub Actions、静的サイトジェネレータを導入しない。
- **外部リソースを読み込まない。** Web フォント、CDN、アナリティクス、埋め込みスクリプトを使わない。
- **`docs/` 配下は丸ごと公開される。** 設計書・計画・検証スクリプトは `specs/` に置き、`docs/` に入れない。
- **フォントウェイトは 400 / 500 / 600 / 700 のみ。** 300 以下を書かない。
- **本文 17px、最小 14px。** サイズはすべて `rem` で表現し、`html` に `font-size` を指定しない。
- **色は必ずカスタムプロパティ経由。** セレクタに 16 進数を直書きしない（定義は `:root` と `@media (prefers-color-scheme: dark)` の 2 箇所のみ）。
- **`--accent` を `--material` の上に文字色として使わない**（ダークで 3.58:1 と不足するため）。塗り（`--accent-fill`）＋白文字は可。
- **クリック対象は 44×44px 以上**（`.btn`、`summary`）。本文中のインラインリンクは対象外。
- **見出しは h1 → h2 → h3 の順。** 段を飛ばさない。h1 はページに 1 つ。
- リポジトリ: `https://github.com/takenakasuji/nagi`（未作成。Task 10 で作る）
- 対応 OS 表記: **macOS 14 Sonoma 以降**（`Package.swift` の `platforms: [.macOS(.v14)]` に一致させる）

## ファイル構成

| ファイル | 責務 |
|---|---|
| `LICENSE` | MIT ライセンス本文 |
| `docs/.nojekyll` | 空ファイル。GitHub Pages の Jekyll ビルドを止める |
| `docs/favicon.svg` | favicon。ページの色を継承できないため、色を内蔵し `prefers-color-scheme` で切り替える |
| `docs/index.html` | 7 セクションのマークアップ。構造と文言のすべて |
| `docs/style.css` | 全スタイル。7 層に区切ってコメントで見出しを打つ |

**なぜ CSS を 1 ファイルにするか:** ビルド工程がないため、ファイルを割るとそのまま HTTP リクエスト数になる。1 ページ・数百行の規模では層をコメントで区切るほうが読みやすく、`@import` の直列読み込みも避けられる。

## 検証環境の前提

- **設計書の「実装の順序」1（`git init` → `.gitignore` → 初回コミット）は完了済み。** ローカルの
  `main` に 3 コミットあり、`user.email` は `takenakasuji@users.noreply.github.com` を
  リポジトリローカルに設定済み。本計画は設計書の順序 2（LICENSE）から始まる。
- `gh` コマンドは**この環境に入っていない**。GitHub 上のリポジトリ作成は Web UI で行う（Task 10）。
- ブラウザ確認は `python3 -m http.server` + ブラウザツールで行う。`file://` では開かない（`prefers-color-scheme` の切り替えや相対パスの確認が実環境と揃わないため）。

---

### Task 1: リポジトリの土台

**Files:**
- Create: `LICENSE`
- Create: `docs/.nojekyll`

**Interfaces:**
- Consumes: なし
- Produces: `docs/` ディレクトリの存在。以降のタスクはすべてこの中にファイルを追加する。

- [ ] **Step 1: `LICENSE` を作る**

`LICENSE`:

```
MIT License

Copyright (c) 2026 takenakasuji

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 2: `docs/.nojekyll` を空ファイルとして作る**

```bash
mkdir -p docs && touch docs/.nojekyll
```

- [ ] **Step 3: 確認**

Run:

```bash
ls -la docs/.nojekyll && head -3 LICENSE
```

Expected: `docs/.nojekyll` がサイズ 0 で存在し、`LICENSE` の 3 行目に `Copyright (c) 2026 takenakasuji` が出る。

- [ ] **Step 4: コミット**

```bash
git add LICENSE docs/.nojekyll
git commit -m "MIT ライセンスと docs/ の土台を追加"
```

---

### Task 2: 風マーク SVG

SF Symbols の `wind` は Apple プラットフォーム外に再配布できないため、Web 用に自分で描く。凪いだ水面を渡る風＝長さの違う 3 本の流線、うち 2 本の端を巻く。

**Files:**
- Create: `docs/favicon.svg`

**Interfaces:**
- Consumes: `docs/` の存在（Task 1）
- Produces: 3 本のパス定義。`d` 属性は `favicon.svg` と `index.html` のインライン SVG（Task 3）で
  **完全に同一**に保つ:
  - `M4 16h24a6 6 0 1 0-6-6`
  - `M4 24h30a6 6 0 1 1-6 6`
  - `M4 32h18`

  `viewBox` と `stroke-width` だけは用途で変える（ロゴ `0 0 48 48` / `3.5`、favicon `2 6 44 34` / `5`）。

**ロゴ単体の SVG ファイルは作らない。** ページのロゴは `index.html` にインライン展開する
（外部 SVG を `<img>` で読むと `currentColor` を継承できず、色をトークンの外に直書きすることに
なるため）。単体ファイルを置いてもサイトからは一度も読まれず、パスを同期する箇所が増えるだけになる。
ロゴ単体が必要になったらそのとき作る。

- [ ] **Step 1: `docs/favicon.svg` を作る**

favicon はページの `color` を継承できないため、色を内蔵する。SVG 内の `<style>` で `prefers-color-scheme` を見れば、ブラウザのタブが暗いときに白く出る。

**パスはロゴと同一だが、`viewBox` と `stroke-width` だけ変える。** ロゴと同じ
`viewBox="0 0 48 48"` / `stroke-width="4"` のままだと、実寸 16px で線が細く余白が広すぎて潰れる
（3 サイズを並べて実測済み）。余白を切り詰めた `viewBox="2 6 44 34"` と `stroke-width="5"` にすると、
16px でも 3 本の線と巻きが判別できる。

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="2 6 44 34">
  <style>
    path { stroke: #1D1D1F; }
    @media (prefers-color-scheme: dark) { path { stroke: #F5F5F7; } }
  </style>
  <g fill="none" stroke-width="5" stroke-linecap="round">
    <path d="M4 16h24a6 6 0 1 0-6-6"/>
    <path d="M4 24h30a6 6 0 1 1-6 6"/>
    <path d="M4 32h18"/>
  </g>
</svg>
```

- [ ] **Step 2: 目視で確認する**

Run:

```bash
python3 -m http.server 8000 --directory docs
```

ブラウザで `http://localhost:8000/favicon.svg` を開く。

Expected: 3 本の横線が見え、**1 本目は右端が上向きに巻き、2 本目は右端が下向きに巻き、3 本目は短い直線**。全体が左から右への「流れ」に見える。

**崩れている場合:** 巻きの向きが逆なら円弧のフラグ（`a6 6 0 1 0` / `a6 6 0 1 1`）の最後の
sweep-flag が入れ替わっている。巻きが円にならず直線に近いなら large-arc-flag が `0` になっている
（正しくは `1`。270 度の巻きを描かせている）。

16px での判別は、`index.html` が出来たあと（Task 3 以降）にブラウザのタブアイコンで確認する。

- [ ] **Step 3: コミット**

```bash
git add docs/favicon.svg
git commit -m "風マークの favicon を追加（SF Symbols は Web に使えないため自作）"
```

---

### Task 3: index.html のマークアップ

スタイルを当てずに構造と文言だけを作る。この時点で意味の階層が正しいことを確かめてから CSS に入る。

**Files:**
- Create: `docs/index.html`

**Interfaces:**
- Consumes: `docs/favicon.svg`（`<link rel="icon">` と、同一に保つべきパス定義）
- Produces: 以降の CSS が参照するクラス名。
  - レイアウト: `.wrap` `.band` `.section__head` `.section__lead`
  - ヒーロー: `.hero` `.hero__mark` `.hero__ruby` `.hero__lead` `.hero__sub` `.hero__actions` `.hero__meta`
  - ボタン: `.btn` `.btn--primary` `.btn--secondary`
  - モック: `.mock` `.mock__win` `.mock__name` `.mock__rule` `.mock__body` `.mock__bar` `.mock__chip` `.mock__chip--primary` `.mock__spacer`
  - その他: `.cards` `.card` `.keys__scroll` `.steps` `.build` `.brew` `.footer` `.reveal`
  - セクション識別用: `.showcase`（Task 7 で背景の帯を当てる） `.limits`（スタイルなし）

**設計書からの変更点:** 設計書は「窓の脇に `⌥Space` のキーキャップを添える」としていたが、
独立した要素にせずセクションのリード文（`.section__lead`）に埋め込む。文として読めるほうが
意味が伝わり、375px 幅でモックの脇に置き場所を作らずに済む。<kbd> 要素は使うので
「キーを見せる」目的は満たしている。

- [ ] **Step 1: `docs/index.html` を書く**

```html
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nagi（凪）— AI 時代のメモ帳</title>
<meta name="description" content="macOS のメニューバーに常駐するクイックキャプチャアプリ。ホットキーで窓を出し、思考を止めずに書き、指定フォルダに .md を吐く。">
<meta name="color-scheme" content="light dark">
<link rel="icon" href="favicon.svg" type="image/svg+xml">
<link rel="stylesheet" href="style.css">
<meta property="og:type" content="website">
<meta property="og:url" content="https://takenakasuji.github.io/nagi/">
<meta property="og:title" content="Nagi（凪）— AI 時代のメモ帳">
<meta property="og:description" content="雑に書いて、速く貯める。macOS のメニューバー常駐クイックキャプチャ。">
</head>
<body>

<header class="hero">
  <div class="wrap">
    <svg class="hero__mark" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48" role="img"
         aria-labelledby="nagi-mark-title" fill="none" stroke="currentColor"
         stroke-width="3.5" stroke-linecap="round">
      <title id="nagi-mark-title">Nagi のロゴ — 凪いだ水面を渡る風</title>
      <path d="M4 16h24a6 6 0 1 0-6-6"/>
      <path d="M4 24h30a6 6 0 1 1-6 6"/>
      <path d="M4 32h18"/>
    </svg>

    <h1>Nagi<span class="hero__ruby">（凪）</span></h1>
    <p class="hero__lead">AI 時代のメモ帳。雑に書いて、速く貯める。</p>
    <p class="hero__sub">ホットキーで窓を出し、思考を止めずに書き、指定フォルダに <code>.md</code> を吐く。整理・リネーム・構造化は、あとから Claude Code や Obsidian に任せる。</p>

    <div class="hero__actions">
      <a class="btn btn--primary" href="https://github.com/takenakasuji/nagi/releases/latest">ダウンロード</a>
      <a class="btn btn--secondary" href="https://github.com/takenakasuji/nagi">GitHub で見る</a>
    </div>

    <p class="hero__meta">macOS 14 Sonoma 以降 · 無料 · MIT ライセンス</p>
  </div>
</header>

<main>

<section class="showcase" aria-labelledby="showcase-h">
  <div class="wrap">
    <div class="section__head reveal">
      <h2 id="showcase-h">押すと、出る</h2>
      <p class="section__lead">どのアプリの上にいても <kbd>⌥</kbd><kbd>Space</kbd>。画面の中央に窓が開いて、カーソルはもう本文にある。</p>
    </div>

    <figure class="mock reveal">
      <div class="mock__win">
        <div class="mock__name">
          <svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor"
               stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
            <path d="M9.5 1.5H4a1.5 1.5 0 0 0-1.5 1.5v10A1.5 1.5 0 0 0 4 14.5h8a1.5 1.5 0 0 0 1.5-1.5V5.5z"/>
            <path d="M9.5 1.5v4h4M5.5 8.5h5M5.5 11h5"/>
          </svg>
          <span>ファイル名（.md は自動）</span>
        </div>
        <div class="mock__rule"></div>
        <div class="mock__body">雑に書く。整理はあとで Claude に任せる。</div>
        <div class="mock__rule"></div>
        <div class="mock__bar">
          <span class="mock__chip">退避</span>
          <span class="mock__chip">設定</span>
          <span class="mock__spacer"></span>
          <span class="mock__chip">退避 ⌘⇧S</span>
          <span class="mock__chip mock__chip--primary">保存 ⌘↩</span>
        </div>
      </div>
      <figcaption>入力窓は 660 × 440。ファイル名、本文、下のツールバーだけ。</figcaption>
    </figure>
  </div>
</section>

<section class="band" aria-labelledby="principles-h">
  <div class="wrap">
    <div class="section__head reveal">
      <h2 id="principles-h">しないことが、3 つある</h2>
      <p class="section__lead">機能を足さないことで速さを守っている。</p>
    </div>

    <ul class="cards" role="list">
      <li class="card reveal">
        <h3>アプリに AI は入っていない</h3>
        <p>要約も分類もタグ付けもしない。責務は「捕まえて、置く」だけ。整理はあとから Claude Code や Obsidian に任せる。だから待ち時間がなく、オフラインでも書ける。</p>
      </li>
      <li class="card reveal">
        <h3>既存のファイルを上書きしない</h3>
        <p>同じ名前のファイルがあれば <code>名前-2.md</code> のように連番を付けて別ファイルにする。うっかり同じ名前で保存しても、前に書いたものは残る。</p>
      </li>
      <li class="card reveal">
        <h3>書きかけが消えない</h3>
        <p><kbd>Esc</kbd> で閉じても内容は残り、次に開くと続きから書ける。保存しないメモは何件でも退避でき、一覧から再開も破棄もできる。</p>
      </li>
    </ul>
  </div>
</section>

<section aria-labelledby="keys-h">
  <div class="wrap">
    <div class="section__head reveal">
      <h2 id="keys-h">キーボードだけで完結する</h2>
      <p class="section__lead">マウスに手を伸ばす場面がない。ホットキーは設定で変えられる。</p>
    </div>

    <div class="keys__scroll reveal">
      <table>
        <caption>Nagi のキー操作一覧</caption>
        <thead>
          <tr><th scope="col">キー</th><th scope="col">動作</th></tr>
        </thead>
        <tbody>
          <tr><td><kbd>⌥</kbd><kbd>Space</kbd></td><td>メモ入力ウインドウを開く／閉じる（設定で変更可）</td></tr>
          <tr><td><kbd>⌘</kbd><kbd>Enter</kbd></td><td>指定フォルダに <code>ファイル名.md</code> として保存し、ウインドウを閉じる</td></tr>
          <tr><td><kbd>⌘</kbd><kbd>⇧</kbd><kbd>S</kbd></td><td>書きかけを退避し、エディタを空にする</td></tr>
          <tr><td><kbd>Esc</kbd></td><td>ウインドウを隠す。内容は消えず、次に開くと続きから</td></tr>
          <tr><td><kbd>Enter</kbd></td><td>ファイル名欄では本文へ移動する（誤って保存しないため）</td></tr>
          <tr><td><kbd>⌘</kbd><kbd>,</kbd></td><td>設定を開く</td></tr>
        </tbody>
      </table>
    </div>
  </div>
</section>

<section class="band" aria-labelledby="install-h">
  <div class="wrap">
    <div class="section__head reveal">
      <h2 id="install-h">インストール</h2>
    </div>

    <ol class="steps reveal" role="list">
      <li>
        <div>
          <h3>ダウンロードして解凍する</h3>
          <p>zip を展開すると <code>Nagi.app</code> が出てきます。</p>
        </div>
      </li>
      <li>
        <div>
          <h3><code>Nagi.app</code> を <code>/Applications</code> に入れる</h3>
          <p>「ログイン時に起動」は、ここに置いてあるときに安定して動きます。</p>
        </div>
      </li>
      <li>
        <div>
          <h3>初回だけ、右クリック →「開く」</h3>
          <p>Nagi は ad-hoc 署名です。Apple の Developer ID による署名と公証をしていないため、ダブルクリックでは macOS が起動を止めます。一度「開く」を選べば、次からは普通に起動します。</p>
        </div>
      </li>
      <li>
        <div>
          <h3>保存先フォルダを選ぶ</h3>
          <p>初回起動時に訊かれます。Obsidian の Vault や Claude Code の作業フォルダを指定してください。あとから設定（<kbd>⌘</kbd><kbd>,</kbd>）で変更できます。</p>
        </div>
      </li>
    </ol>

    <details class="build">
      <summary>ソースからビルドする</summary>
      <p>フル Xcode は不要で、Command Line Tools だけでビルドできます。</p>
      <pre><code>git clone https://github.com/takenakasuji/nagi.git
cd nagi
./scripts/build-app.sh
cp -R build/Nagi.app /Applications/</code></pre>
    </details>

    <p class="brew">Homebrew — <strong>準備中</strong>。<code>brew install --cask nagi</code> は将来対応します。</p>
  </div>
</section>

<section class="limits" aria-labelledby="limits-h">
  <div class="wrap">
    <div class="section__head reveal">
      <h2 id="limits-h">正直な制限</h2>
      <p class="section__lead">先に知っておいてもらったほうがいいことです。</p>
    </div>

    <ul class="cards" role="list">
      <li class="card reveal">
        <h3>ホットキーの衝突は検出できないことがある</h3>
        <p>macOS は、他のアプリが同じ組み合わせを握っていても登録を成功として返すことがあります。Alfred や Raycast と重なって反応しないときは、設定で別のキーに変えてください。</p>
      </li>
      <li class="card reveal">
        <h3>ad-hoc 署名</h3>
        <p>初回だけ右クリック →「開く」が必要です。Developer ID による署名と公証はしていません。</p>
      </li>
      <li class="card reveal">
        <h3>非サンドボックス</h3>
        <p>保存先はパスとして保持しています。App Store では配布していません。</p>
      </li>
      <li class="card reveal">
        <h3>メニューバーのアイコンが見えないことがある</h3>
        <p>ノッチ付きの MacBook でメニューバーが埋まっていると、後から起動したアプリのアイコンはノッチに押し出されて見えなくなります。macOS はそこに何も描かず、あふれた印も出しません。アイコンは存在していて、機能もしています（<kbd>⌥</kbd><kbd>Space</kbd> は効きます）。</p>
      </li>
    </ul>
  </div>
</section>

</main>

<footer class="footer">
  <div class="wrap">
    <a href="https://github.com/takenakasuji/nagi">GitHub</a>
    <a href="https://github.com/takenakasuji/nagi/blob/main/LICENSE">MIT License</a>
    <span>takenakasuji</span>
  </div>
</footer>

</body>
</html>
```

- [ ] **Step 2: 構造を検証する**

サーバを立てる（以降のタスクでも使う）:

```bash
python3 -m http.server 8000 --directory docs
```

ブラウザで `http://localhost:8000/` を開き、コンソールで次を評価する:

```js
JSON.stringify({
  lang: document.documentElement.lang,
  h1: document.querySelectorAll('h1').length,
  order: [...document.querySelectorAll('h1,h2,h3')].map(e => e.tagName).join(' '),
  caption: !!document.querySelector('table > caption'),
  svgTitle: !!document.querySelector('.hero__mark > title'),
  ariaHidden: document.querySelectorAll('svg[aria-hidden="true"]').length,
  labelled: document.querySelectorAll('section[aria-labelledby]').length,
  roleList: document.querySelectorAll('ul[role="list"], ol[role="list"]').length
}, null, 1)
```

Expected:
- `lang` が `"ja"`
- `h1` が `1`
- `order` が `H1 H2 H2 H3 H3 H3 H2 H2 H3 H3 H3 H3 H2 H3 H3 H3 H3`
  （h1 が 1 個、h2 が 5 個、h3 が 11 個。段が飛んでいない）
- `caption` が `true`
- `svgTitle` が `true`
- `ariaHidden` が `1`（モックの書類アイコン）
- `labelled` が `5`
- `roleList` が `3`

`role="list"` を明示しているのは、CSS の `list-style: none` を当てると Safari の VoiceOver が
リストとして読み上げなくなるため。3 箇所（原則のカード、インストール手順、制限のカード）に付ける。

- [ ] **Step 3: リンク先を確認する**

```js
[...document.querySelectorAll('a[href]')].map(a => a.href)
```

Expected: 4 本すべてが `https://github.com/takenakasuji/nagi` で始まる。`releases/latest` は Task 10 まで 404 のままでよい。

- [ ] **Step 4: コミット**

```bash
git add docs/index.html
git commit -m "配布サイトのマークアップを追加"
```

---

### Task 4: CSS — トークン、リセット、タイポグラフィ

**Files:**
- Create: `docs/style.css`

**Interfaces:**
- Consumes: Task 3 のクラス名
- Produces: 以降のタスクが使うカスタムプロパティ。**この名前で固定する:**
  - 色: `--bg` `--bg-subtle` `--label` `--label-secondary` `--separator` `--accent` `--accent-fill` `--accent-on-fill` `--material` `--material-edge` `--hero-from` `--hero-to` `--shadow`
  - 書体: `--font-ui` `--font-mono`
  - 寸法: `--step--1` `--step-0` `--step-1` `--step-2` `--step-3` `--wrap`

- [ ] **Step 1: `docs/style.css` を書く**

値は `specs/2026-08-09-nagi-website-design.md` の表と `specs/contrast.py` に一致させること。**勝手に色を足したり変えたりしない。**

```css
/* ==========================================================================
   Nagi 配布サイト
   1. トークン  2. リセット  3. タイポグラフィ  4. レイアウト
   5. ヒーローと CTA  6. 入力窓のモック  7. フォーカスとモーション
   ========================================================================== */

/* 1. トークン ------------------------------------------------------------ */

:root {
  color-scheme: light dark;

  --bg:              #FFFFFF;
  --bg-subtle:       #F5F5F7;
  --label:           #1D1D1F;
  --label-secondary: #68686D;
  --separator:       rgba(0, 0, 0, .10);
  --accent:          #0060DF;
  --accent-fill:     #0060DF;
  --accent-on-fill:  #FFFFFF;
  --material:        rgba(255, 255, 255, .72);
  --material-edge:   rgba(0, 0, 0, .10);
  --hero-from:       #EAF1F8;
  --hero-to:         #FFFFFF;
  --shadow:          0 1.125rem 3rem rgba(0, 0, 0, .13);

  --font-ui:   -apple-system, BlinkMacSystemFont, "Hiragino Sans",
               "Hiragino Kaku Gothic ProN", "Noto Sans JP", "Yu Gothic UI", sans-serif;
  --font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace;

  --step--1: .875rem;   /* 14px 補足 */
  --step-0:  1.0625rem; /* 17px 本文 */
  --step-1:  1.375rem;  /* 22px h3 */
  --step-2:  2rem;      /* 32px h2 */
  --step-3:  3rem;      /* 48px h1 */

  --wrap: 60rem;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg:              #1C1C1E;
    --bg-subtle:       #000000;
    --label:           #F5F5F7;
    --label-secondary: #A1A1A6;
    --separator:       rgba(255, 255, 255, .14);
    --accent:          #0A84FF;
    --accent-fill:     #0A6ADF;
    --material:        rgba(58, 58, 60, .66);
    --material-edge:   rgba(255, 255, 255, .14);
    --hero-from:       #16202B;
    --hero-to:         #1C1C1E;
    --shadow:          0 1.125rem 3rem rgba(0, 0, 0, .55);
  }
}

/* 2. リセット ------------------------------------------------------------ */

*, *::before, *::after { box-sizing: border-box; }
* { margin: 0; }

body {
  font-family: var(--font-ui);
  font-size: var(--step-0);
  font-weight: 400;
  line-height: 1.75;
  color: var(--label);
  background: var(--bg);
  -webkit-font-smoothing: antialiased;
}

svg { display: block; max-width: 100%; }
ul, ol { list-style: none; padding: 0; }

a {
  color: var(--accent);
  text-underline-offset: .2em;
}

/* 3. タイポグラフィ ------------------------------------------------------ */

h1, h2, h3 {
  line-height: 1.35;
  font-weight: 600;
  letter-spacing: .01em;
  text-wrap: balance;
}

h1 { font-size: clamp(2.25rem, 1.5rem + 3.2vw, var(--step-3)); font-weight: 700; }
h2 { font-size: clamp(1.625rem, 1.2rem + 1.9vw, var(--step-2)); }
h3 { font-size: var(--step-1); }

p { text-wrap: pretty; }

code, kbd, pre { font-family: var(--font-mono); }

/* 本文（17px）の中では少し小さく見せたいが、既に 14px の面（pre、.brew）の中に
   入ると em が掛かって 13.1px まで落ちる。max() で 14px を床にする。 */
code { font-size: max(var(--step--1), .9375em); }

kbd {
  display: inline-block;
  min-width: 1.75em;
  margin-inline: .0625em;
  padding: .1em .45em;
  border: 1px solid var(--separator);
  border-bottom-width: 2px;
  border-radius: .375em;
  background: var(--bg);
  font-size: var(--step--1);
  font-weight: 500;
  line-height: 1.7;
  text-align: center;
  white-space: nowrap;
}
```

`kbd` のサイズを `em` でなく `--step--1`（14px）で固定しているのは、`em` にすると本文 17px から
計算されて 13.8px になり、Global Constraints の「最小 14px」を割るため。`kbd` はキー名という
読ませる内容なので、装飾扱いにはできない。

- [ ] **Step 2: トークンが両テーマで解決されることを確認する**

ブラウザで `http://localhost:8000/` を開き、コンソールで:

```js
(() => {
  const s = getComputedStyle(document.documentElement);
  const names = ['--bg','--bg-subtle','--label','--label-secondary','--separator',
                 '--accent','--accent-fill','--accent-on-fill','--material',
                 '--material-edge','--hero-from','--hero-to','--shadow',
                 '--font-ui','--font-mono','--step--1','--step-0','--step-1',
                 '--step-2','--step-3','--wrap'];
  const missing = names.filter(n => !s.getPropertyValue(n).trim());
  return JSON.stringify({ missing, label: s.getPropertyValue('--label').trim() });
})()
```

Expected: `missing` が `[]`。ライト表示なら `label` が `#1D1D1F`。

ブラウザをダークに切り替えて同じ式を評価する。

Expected: `label` が `#F5F5F7`。

- [ ] **Step 3: 禁止したウェイトが入っていないことを確認する**

```bash
grep -nE 'font-weight:\s*(100|200|300|lighter)' docs/style.css
```

Expected: 何も出ない（終了コード 1）。

- [ ] **Step 4: 色の直書きがトークン定義の外に無いことを確認する**

```bash
grep -nE '#[0-9A-Fa-f]{3,8}|rgba?\(' docs/style.css | grep -vE '^\s*[0-9]+:\s*--'
```

Expected: 何も出ない。16 進数と `rgba()` は `--*` の定義行にしか現れない。

- [ ] **Step 5: コミット**

```bash
git add docs/style.css
git commit -m "サイトのカラートークン、リセット、タイポグラフィを追加"
```

---

### Task 5: CSS — レイアウト

**Files:**
- Modify: `docs/style.css`（末尾に追記）

**Interfaces:**
- Consumes: Task 4 のトークン
- Produces: `.wrap` の横幅規則。Task 6・7 はこの中に収まる前提で書く。

- [ ] **Step 1: レイアウト層を `docs/style.css` の末尾に追記する**

```css
/* 4. レイアウト ---------------------------------------------------------- */

.wrap {
  width: min(100% - 2.5rem, var(--wrap));
  margin-inline: auto;
}

section { padding-block: clamp(3.5rem, 9vw, 6.5rem); }
.band   { background: var(--bg-subtle); }

.section__head { max-width: 44rem; margin-bottom: clamp(2rem, 4vw, 3rem); }
.section__lead { margin-top: .75rem; color: var(--label-secondary); }

/* カード（原則・制限） */

.cards {
  display: grid;
  gap: 1.25rem;
  grid-template-columns: repeat(auto-fit, minmax(17rem, 1fr));
}

.card {
  padding: 1.75rem;
  border: 1px solid var(--separator);
  border-radius: 1rem;
  background: var(--bg);
}

.card h3 { margin-bottom: .625rem; }
.card p  { color: var(--label-secondary); }

/* キー操作の表 */

.keys__scroll { overflow-x: auto; }

table { width: 100%; border-collapse: collapse; }

caption {
  padding-bottom: .875rem;
  color: var(--label-secondary);
  font-size: var(--step--1);
  text-align: left;
}

th, td {
  padding: .875rem 1rem;
  border-bottom: 1px solid var(--separator);
  text-align: left;
  vertical-align: baseline;
}

th {
  font-size: var(--step--1);
  font-weight: 600;
  color: var(--label-secondary);
}

td:first-child { white-space: nowrap; }

/* インストール手順 */

.steps { counter-reset: step; display: grid; gap: 1.75rem; }

.steps > li {
  counter-increment: step;
  display: grid;
  grid-template-columns: 2.25rem 1fr;
  gap: 1rem;
}

.steps > li::before {
  content: counter(step);
  display: grid;
  place-items: center;
  width: 2.25rem;
  height: 2.25rem;
  border-radius: 50%;
  background: var(--accent-fill);
  color: var(--accent-on-fill);
  font-size: var(--step--1);
  font-weight: 600;
  line-height: 1;
}

.steps h3 { font-size: var(--step-0); font-weight: 600; }
.steps p  { margin-top: .375rem; color: var(--label-secondary); }

/* ソースからビルド */

.build {
  margin-top: 2.5rem;
  padding: .5rem 1.25rem 1.25rem;
  border: 1px solid var(--separator);
  border-radius: .75rem;
}

summary {
  display: flex;
  align-items: center;
  min-height: 2.75rem;
  font-weight: 600;
  cursor: pointer;
}

.build p { margin-bottom: .875rem; color: var(--label-secondary); }

pre {
  overflow-x: auto;
  padding: 1rem 1.25rem;
  border-radius: .625rem;
  background: var(--bg-subtle);
  font-size: var(--step--1);
  line-height: 1.8;
}

.band pre { background: var(--bg); }

.brew {
  margin-top: 1.5rem;
  color: var(--label-secondary);
  font-size: var(--step--1);
}

/* footer */

.footer {
  padding-block: 2.5rem;
  border-top: 1px solid var(--separator);
  color: var(--label-secondary);
  font-size: var(--step--1);
}

.footer .wrap {
  display: flex;
  flex-wrap: wrap;
  gap: .5rem 1.25rem;
  justify-content: center;
}
```

`.band pre` を上書きしているのは、`.band` セクション（インストール）の中で `pre` の背景が `--bg-subtle` と同色になり、コードブロックの枠が消えるため。

- [ ] **Step 2: 横スクロールが出ないことを確認する**

ブラウザの幅を 375 → 768 → 1280 に変えながら、各幅で:

```js
JSON.stringify({
  w: window.innerWidth,
  scrollW: document.documentElement.scrollWidth,
  overflow: document.documentElement.scrollWidth > window.innerWidth
})
```

Expected: 3 つの幅すべてで `overflow` が `false`。

**`true` になった場合:** 表がはみ出している可能性が高い。`.keys__scroll` が `overflow-x: auto` になっているか、`<div class="keys__scroll">` が `<table>` を包んでいるかを確認する。

- [ ] **Step 3: 手順の丸数字が出ていることを確認する**

```js
JSON.stringify([...document.querySelectorAll('.steps > li')].map(li =>
  getComputedStyle(li, '::before').content))
```

Expected: `["counter(step)","counter(step)","counter(step)","counter(step)"]` または `["1","2","3","4"]`（ブラウザによって表現が異なる）。空文字や `none` なら失敗。

- [ ] **Step 4: コミット**

```bash
git add docs/style.css
git commit -m "サイトのレイアウト（セクション、カード、表、手順、footer）を追加"
```

---

### Task 6: CSS — ヒーローと CTA ボタン

**Files:**
- Modify: `docs/style.css`（末尾に追記）

**Interfaces:**
- Consumes: Task 4 のトークン、Task 5 の `.wrap`
- Produces: `.btn` の最小寸法 44×44px。Task 9 の検証がこれを測る。

- [ ] **Step 1: ヒーロー層を追記する**

```css
/* 5. ヒーローと CTA ------------------------------------------------------ */

.hero {
  padding-block: clamp(4rem, 10vw, 7rem) clamp(3rem, 8vw, 5rem);
  background: linear-gradient(180deg, var(--hero-from), var(--hero-to));
  text-align: center;
}

.hero__mark {
  width: 4rem;
  height: 4rem;
  margin-inline: auto;
  color: var(--accent);
}

.hero h1 { margin-top: 1.25rem; }

.hero__ruby {
  font-size: .5em;
  font-weight: 500;
  color: var(--label-secondary);
}

.hero__lead {
  margin-top: .75rem;
  font-size: clamp(1.125rem, 1rem + .6vw, 1.375rem);
  font-weight: 500;
}

.hero__sub {
  max-width: 38rem;
  margin: 1.25rem auto 0;
  color: var(--label-secondary);
}

.hero__actions {
  display: flex;
  flex-wrap: wrap;
  gap: .75rem;
  justify-content: center;
  margin-top: 2.25rem;
}

.hero__meta {
  margin-top: 1.125rem;
  color: var(--label-secondary);
  font-size: var(--step--1);
}

.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 2.75rem;
  min-height: 2.75rem;
  padding: 0 1.5rem;
  border-radius: 999px;
  font-size: var(--step-0);
  font-weight: 600;
  text-decoration: none;
}

.btn--primary {
  background: var(--accent-fill);
  color: var(--accent-on-fill);
}

.btn--secondary {
  color: var(--accent);
  box-shadow: inset 0 0 0 1px currentColor;
}

@media (hover: hover) {
  .btn--primary:hover { background: color-mix(in srgb, var(--accent-fill) 88%, black); }

  /* secondary の hover は --bg を敷いて枠を太くする。却下した案が 2 つある:
     (1) accent を 8% ティント — ダークの安静時が 4.51:1 しかなく、同じ色相を
         重ねるだけで 4.11:1 まで落ちる。
     (2) accent-fill の塗りに変える — コントラストは通るが、隣の primary の
         安静時と画素単位で同一になり、主従の区別が消える。
     --bg なら文字色のコントラストは安静時より上がり（グラデ上の 4.93 / 4.51 →
     5.62 / 4.66）、primary とも見分けがつく。 */
  .btn--secondary:hover {
    background: var(--bg);
    box-shadow: inset 0 0 0 2px currentColor;
  }
}
```

`:hover` を `@media (hover: hover)` で囲むのは、タッチ環境でタップ後に hover 状態が貼り付くのを避けるため。

- [ ] **Step 2: ボタンの寸法を測る**

```js
JSON.stringify([...document.querySelectorAll('.btn, summary')].map(e => {
  const r = e.getBoundingClientRect();
  return { t: e.textContent.trim().slice(0, 12), w: Math.round(r.width), h: Math.round(r.height) };
}))
```

Expected: すべての `h` が 44 以上、`w` が 44 以上。

- [ ] **Step 3: グラデーションが両テーマで出ていることを確認する**

ライトとダークの両方で:

```js
getComputedStyle(document.querySelector('.hero')).backgroundImage
```

Expected: ライトで `linear-gradient(... rgb(234, 241, 248), rgb(255, 255, 255))`、ダークで `... rgb(22, 32, 43), rgb(28, 28, 30)`。

- [ ] **Step 4: コミット**

```bash
git add docs/style.css
git commit -m "ヒーローと CTA ボタンのスタイルを追加"
```

---

### Task 7: CSS — 入力窓のモックとマテリアル

`Sources/NagiUI/CaptureView.swift` の見た目に寄せる。実装との対応は設計書の表を参照。

**Files:**
- Modify: `docs/style.css`（末尾に追記）

**Interfaces:**
- Consumes: Task 4 の `--material` `--material-edge` `--shadow`
- Produces: なし（このタスクが最後の見た目の層）

- [ ] **Step 1: モック層を追記する**

```css
/* 6. 入力窓のモック ------------------------------------------------------ */

.mock { margin: 0; }

.mock__win {
  max-width: 41.25rem; /* 660px */
  margin-inline: auto;
  overflow: hidden;
  border: 1px solid var(--material-edge);
  border-radius: .75rem;
  background: var(--material);
  box-shadow: var(--shadow);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
  text-align: left;
}

/* backdrop-filter が無い環境では、半透明のままだと文字のコントラストが
   保証できない。不透明の --bg に落とす（--material の素の色ではない）。 */
@supports not ((backdrop-filter: blur(1px)) or (-webkit-backdrop-filter: blur(1px))) {
  .mock__win { background: var(--bg); }
}

.mock__name {
  display: flex;
  align-items: center;
  gap: .5rem;
  padding: .75rem .875rem .625rem;
  color: var(--label-secondary);
  font-size: var(--step--1);
  font-weight: 500;
}

.mock__rule { height: 1px; background: var(--separator); }

.mock__body {
  min-height: 9rem;
  padding: .625rem .75rem;
  color: var(--label-secondary);
  font-family: var(--font-mono);
  font-size: var(--step--1);
}

.mock__bar {
  display: flex;
  align-items: center;
  gap: .5rem;
  padding: .5rem .75rem;
}

.mock__chip {
  padding: .25rem .5rem;
  border-radius: .3125rem;
  color: var(--label-secondary);
  font-size: .75rem;
  white-space: nowrap;
}

.mock__chip--primary {
  background: var(--accent-fill);
  color: var(--accent-on-fill);
  font-weight: 500;
}

.mock__spacer { flex: 1; }

figcaption {
  margin-top: 1rem;
  color: var(--label-secondary);
  font-size: var(--step--1);
  text-align: center;
}
```

`.mock__chip` の `.75rem`（12px）は本文最小の 14px を下回るが、これは**アプリのスクリーンショットの代替**であり読ませる文言ではない。同じ内容はキー操作の表に 17px で載っている（色だけ・サイズだけに依存しない）。

- [ ] **Step 2: マテリアルが効いていることを確認する**

```js
(() => {
  const w = getComputedStyle(document.querySelector('.mock__win'));
  return JSON.stringify({
    backdrop: w.backdropFilter || w.webkitBackdropFilter,
    bg: w.backgroundColor,
    radius: w.borderRadius
  });
})()
```

Expected: `backdrop` が `blur(20px) saturate(1.8)`、`bg` が `rgba(255, 255, 255, 0.72)`（ライト）。

- [ ] **Step 3: 375px 幅でモックが崩れないことを確認する**

幅 375px にして:

```js
(() => {
  const r = document.querySelector('.mock__win').getBoundingClientRect();
  const bar = document.querySelector('.mock__bar').getBoundingClientRect();
  return JSON.stringify({
    winW: Math.round(r.width),
    fitsViewport: r.width <= window.innerWidth,
    barFits: bar.width <= r.width
  });
})()
```

Expected: `fitsViewport` と `barFits` がどちらも `true`。

**`barFits` が `false` の場合:** ツールバーのチップが折り返せずに溢れている。`.mock__bar` に `flex-wrap: wrap` を足すのではなく、`.mock__chip` の `padding` を `.25rem .375rem` に詰めて収める（実アプリのツールバーは 1 行なので、折り返すと見た目が実物から離れる）。

- [ ] **Step 4: コミット**

```bash
git add docs/style.css
git commit -m "入力窓のモックとマテリアルのスタイルを追加"
```

---

### Task 8: CSS — フォーカスとモーション

**Files:**
- Modify: `docs/style.css`（末尾に追記）

**Interfaces:**
- Consumes: Task 4 の `--accent`、Task 3 の `.reveal`
- Produces: なし

- [ ] **Step 1: フォーカスとモーション層を追記する**

```css
/* 7. フォーカスとモーション ---------------------------------------------- */

:focus-visible {
  outline: 3px solid var(--accent);
  outline-offset: 3px;
  border-radius: .25rem;
}

/* リングは outline-offset で要素の外に出す。塗りの CTA の上に同色で描くと
   見えなくなるため。 */

@media (prefers-reduced-motion: no-preference) {
  .hero > .wrap > * {
    animation: rise .7s cubic-bezier(.2, .7, .3, 1) backwards;
  }

  .hero__mark    { animation-delay: 0s; }
  .hero h1       { animation-delay: .06s; }
  .hero__lead    { animation-delay: .12s; }
  .hero__sub     { animation-delay: .18s; }
  .hero__actions { animation-delay: .24s; }
  .hero__meta    { animation-delay: .30s; }

  /* スクロール駆動。非対応ブラウザではこのブロックごと無視され、
     .reveal は最初から見えている状態になる。 */
  @supports (animation-timeline: view()) {
    .reveal {
      animation: rise linear both;
      animation-timeline: view();
      animation-range: entry 10% cover 28%;
    }
  }
}

@keyframes rise {
  from { opacity: 0; transform: translateY(.75rem); }
  to   { opacity: 1; transform: none; }
}
```

- [ ] **Step 2: フォーカスリングが見えることを確認する**

ページを読み込み、`Tab` を 1 回押してから:

```js
(() => {
  const a = document.activeElement;
  const s = getComputedStyle(a);
  return JSON.stringify({
    tag: a.tagName, text: a.textContent.trim().slice(0, 12),
    outlineWidth: s.outlineWidth, outlineColor: s.outlineColor, offset: s.outlineOffset
  });
})()
```

Expected: 最初のフォーカスが「ダウンロード」に当たり、`outlineWidth` が `3px`、`offset` が `3px`。

続けて `Tab` を押し、「GitHub で見る」→「ソースからビルドする」（`summary`）→ footer の 2 本のリンク、の順に到達できること。

- [ ] **Step 3: reduced-motion で止まることを確認する**

ブラウザの「動きを減らす」を有効にして再読み込みし:

```js
JSON.stringify({
  reduced: matchMedia('(prefers-reduced-motion: reduce)').matches,
  heroAnim: getComputedStyle(document.querySelector('.hero h1')).animationName,
  revealAnim: getComputedStyle(document.querySelector('.reveal')).animationName
})
```

Expected: `reduced` が `true` のとき `heroAnim` と `revealAnim` がどちらも `"none"`。

- [ ] **Step 4: コミット**

```bash
git add docs/style.css
git commit -m "フォーカスリングとモーション（reduced-motion 対応）を追加"
```

---

### Task 9: 最終検証

設計書「検証方法」の 6 項目をまとめて通す。落ちたら直してから Task 10 に進む。

**Files:**
- Modify: `docs/style.css` または `docs/index.html`（不合格が出た場合のみ）

**Interfaces:**
- Consumes: Task 1〜8 のすべて
- Produces: なし

- [ ] **Step 1: コントラストを検証する**

```bash
python3 specs/contrast.py
```

Expected: 全行 `OK`、最後に「すべて期待どおり」、終了コード 0。

- [ ] **Step 2: `style.css` の色がスクリプトの値と一致することを確認する**

```bash
grep -oE '#[0-9A-Fa-f]{6}' docs/style.css | tr 'a-f' 'A-F' | sort -u
```

Expected: 出力が次の 12 色ちょうど（順不同）:
`#000000` `#0060DF` `#0A6ADF` `#0A84FF` `#16202B` `#1C1C1E` `#1D1D1F` `#68686D` `#A1A1A6` `#EAF1F8` `#F5F5F7` `#FFFFFF`

**別の色が出た場合:** `specs/contrast.py` で測っていない色が混入している。トークンに戻すか、`contrast.py` の `CHECKS` に追加して測り直す。

- [ ] **Step 3: 6 通りの表示を確認する**

ライト / ダーク × 幅 375 / 768 / 1280 の 6 通りで、それぞれ:

```js
JSON.stringify({
  w: window.innerWidth,
  overflow: document.documentElement.scrollWidth > window.innerWidth,
  clipped: [...document.querySelectorAll('.wrap, .card, .mock__win, .keys__scroll, pre')]
    .filter(e => e.scrollWidth > e.clientWidth + 1)
    .map(e => e.className || e.tagName)
})
```

Expected: `overflow` が `false`。`clipped` に出てよいのは `keys__scroll`（クラス名に `reveal` が付くので `"keys__scroll reveal"`）と `PRE` だけ。どちらも意図的に横スクロールさせている要素。`wrap` `card` `mock__win` が出たら不合格。

- [ ] **Step 4: 200% ズームを確認する**

ブラウザのページズームを 200% にして 1280px 幅で:

```js
JSON.stringify({
  overflow: document.documentElement.scrollWidth > window.innerWidth,
  overlaps: (() => {
    const h = document.querySelector('.hero h1').getBoundingClientRect();
    const l = document.querySelector('.hero__lead').getBoundingClientRect();
    return h.bottom > l.top + 1;
  })()
})
```

Expected: どちらも `false`。

- [ ] **Step 5: キーボードだけで巡回できることを確認する**

`Tab` を押し続けて到達順を記録する。

Expected: ダウンロード → GitHub で見る → ソースからビルドする（`summary`）→ GitHub → MIT License。途中でフォーカスが見えなくなる箇所がないこと。

- [ ] **Step 6: 外部リンクを確認する**

```bash
for u in https://github.com/takenakasuji/nagi \
         https://github.com/takenakasuji/nagi/releases/latest \
         https://github.com/takenakasuji/nagi/blob/main/LICENSE; do
  printf '%s -> ' "$u"; curl -s -o /dev/null -w '%{http_code}\n' -L "$u"
done
```

Expected: Task 10 の**前**はすべて 404（リポジトリが存在しないため）。Task 10 の後に再実行し、`releases/latest` 以外が 200 になること。`releases/latest` は最初のリリースを作るまで 404 のまま。

- [ ] **Step 7: 不合格があれば直してコミット**

```bash
git add docs/
git commit -m "最終検証で見つかった表示の不具合を修正"
```

不合格が無かった場合、このステップは飛ばす（空コミットを作らない）。

---

### Task 10: GitHub に公開する

`gh` コマンドはこの環境に無いため、リポジトリ作成は Web UI で行う。**push は外向きの操作なので、実行前に必ず確認を取る。**

**Files:**
- なし（リポジトリ設定の操作のみ）

**Interfaces:**
- Consumes: Task 1〜9 の成果すべて
- Produces: 公開 URL `https://takenakasuji.github.io/nagi/`

- [ ] **Step 1: GitHub でリポジトリを作る**

https://github.com/new を開き:

- Owner: `takenakasuji`
- Repository name: `nagi`
- Public
- **「Add a README file」「Add .gitignore」「Choose a license」はすべてオフ**（ローカルに既にあり、初回 push が衝突するため）

- [ ] **Step 2: リモートを追加して push する**

```bash
git remote add origin https://github.com/takenakasuji/nagi.git
git push -u origin main
```

Expected: `main -> main` が作られる。

- [ ] **Step 3: Pages を有効にする**

`https://github.com/takenakasuji/nagi/settings/pages` を開き:

- Source: **Deploy from a branch**
- Branch: **`main`** / フォルダ **`/docs`**
- Save

- [ ] **Step 4: 公開を確認する**

1〜2 分待ってから:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://takenakasuji.github.io/nagi/
```

Expected: `200`。

ブラウザで開き、ライト／ダークの両方で Task 9 Step 3 の式を再実行する。

Expected: `overflow` が `false`、`clipped` が許容範囲内。

- [ ] **Step 5: 最初のリリースを作り、ダウンロードリンクを実在させる**

```bash
./scripts/build-app.sh
cd build && zip -r -y Nagi.zip Nagi.app && cd ..
```

`-y` はシンボリックリンクをそのまま保持する。付け忘れると `.app` の内部構造が壊れて起動しなくなる。

`https://github.com/takenakasuji/nagi/releases/new` を開き:

- Tag: `v0.1.0`（`Create new tag on publish`）
- Title: `v0.1.0`
- 本文に、初回起動は右クリック →「開く」が必要であることを書く
- `build/Nagi.zip` を添付
- Publish

- [ ] **Step 6: ダウンロードリンクを確認する**

```bash
curl -s -o /dev/null -w '%{http_code}\n' -L https://github.com/takenakasuji/nagi/releases/latest
```

Expected: `200`。

- [ ] **Step 7: 別のマシン（または `/Applications` から削除した状態）で導通を確認する**

サイトからダウンロード → 解凍 → `/Applications` に移動 → 右クリック →「開く」→ 保存先を選ぶ → <kbd>⌥</kbd><kbd>Space</kbd> で窓が出る、までを実際に通す。

Expected: サイトに書いた 4 ステップだけで動く。詰まった箇所があれば、その手順をサイトに書き足してから完了とする。

---

## 未解決事項

- **Task 10 Step 5 を終えるまで、ダウンロード CTA は 404 を返す。** リンク先は
  `https://github.com/takenakasuji/nagi/releases/latest` で固定し、リリース作成で解消する。
- **OGP 画像を用意していない。** `og:image` は指定していないため、SNS 共有時はテキストのみのカードになる。
  必要になったら別途作る（本計画の範囲外）。
- **Homebrew cask は将来対応。** サイトには枠と「準備中」の表示のみを置く。
