# ビルド済み Nagi.app の配布 設計書

- 日付: 2026-08-10
- 状態: 実装済み
- 配布先: https://github.com/takenakasuji/nagi/releases

## 何を作るか

`v*` タグを push したら GitHub Actions が macOS runner で `Nagi.app` をビルドし、
zip にして Releases に添付する仕組み。加えて、既に切ってある v0.1.0 へ
アセットだけを後から足せる手動実行の口を用意する。

配布サイトの「ダウンロード」ボタン（`docs/index.html:34`）は
`releases/latest` を指しているが、リリースにアセットが 1 つも無いため、
現在このボタンは**空のリリースページに着地する**。これを塞ぐのが目的。

### 作らないもの

- **Developer ID 署名と公証**。Apple Developer Program（年 $99）に未加入で、
  このマシンに証明書もない（`security find-identity -p codesigning` が 0 件）。
  ad-hoc 署名のまま配る。Gatekeeper の回避手順は `docs/index.html:161-167` に既にある
- **リリース本文の自動生成**。手で書いたノートを上書きする事故のほうが高くつく
- **Homebrew cask**。サイトで「準備中」と告知済み（`docs/index.html:185`）
- **GUI テストの CI 実行**。runner のウインドウサーバは当てにならない
- **自動更新（Sparkle 等）**。公証なしでは意味を持たない

## 前提と制約

| 事項 | 現状 | 設計への影響 |
|------|------|--------------|
| 署名 | ad-hoc（`scripts/build-app.sh:55`） | zip 化に `ditto` を使う。`zip -r` は署名を壊しうる |
| リリース | v0.1.0 が存在。アセットなし・本文空 | タグ push だけを起点にすると v0.1.0 を救えない。`workflow_dispatch` が要る |
| Swift | `swift-tools-version:6.0` | Xcode 16 系が要る。macos-15 runner の既定で満たす |
| 対応 OS | `platforms: [.macOS(.v14)]` | macOS 15 でビルドしても deployment target は 14 のまま |
| バージョン | `Resources/Info.plist` の `CFBundleShortVersionString`（現在 `0.1.0`） | タグと二重管理。食い違いを CI で止める |
| テスト | 190 本中 30 本がウインドウサーバを要求 | `--skip "RealAppKit"` で 160 本だけ回す |

## ワークフロー

`.github/workflows/release.yml`。権限は `contents: write` のみ。
サードパーティ action は使わず、`actions/checkout` と `gh` CLI だけで完結させる。

### 起動条件

- `push` の `tags: ['v*']` — 通常のリリース経路
- `workflow_dispatch`（`tag` 入力・必須）— 既存タグへの後付け

`workflow_dispatch` ではワークフロー定義は起動したブランチ（main）から、
ソースツリーは `checkout` の `ref` で**指定タグから**取る。
新しいワークフローで古いソースをビルドできる、というのがこの分離の狙い。

### 手順

1. **タグ名を決める** — `inputs.tag || github.ref_name`。
   `workflow_dispatch` では `github.ref_name` が `main` になるため、入力を先に見る
2. **checkout** — 上で決めたタグを `ref` に指定
3. **バージョン照合** — タグの `v` を剥がした値と `Info.plist` の
   `CFBundleShortVersionString` を比較し、違えば fail。
   タグだけ上げて plist を忘れる事故は、配布物では気づきにくいので入口で止める
4. **テスト** — `./scripts/test.sh --skip "RealAppKit"`
5. **ビルド** — `./scripts/build-app.sh`
6. **zip 化** — `ditto -c -k --sequesterRsrc --keepParent build/Nagi.app Nagi-<version>.zip`
7. **添付** — リリースがあれば `gh release upload --clobber`、無ければ `gh release create`

### なぜ `ditto` か

**実測: 今の bundle なら `zip -r` でも署名は往復する。** 単一の実行ファイルだけを持ち、
シンボリックリンクもネストしたコードも無い（`build-app.sh` が `--deep` を要らないと
書いているのと同じ理由）ため、`zip -r` → `unzip` の後でも
`codesign --verify` は `valid on disk` / `satisfies its Designated Requirement` を返す。
「`zip` は署名を壊す」は、この bundle については**成り立たない**。

それでも `ditto` を選ぶのは、シンボリックリンクと拡張属性を保つ Apple 純正の経路で、
bundle が育った日（フレームワークを抱える、ヘルパーを持つ）に黙って壊れないから。
コストはゼロなので、成り立たなくなる可能性のある前提に賭ける理由がない。

壊れたときの damage は大きい。署名が壊れると Gatekeeper の文言が
「開発元を確認できません」ではなく**「壊れているため開けません」**に変わり、
サイトに書いた「このまま開く」手順では復帰できず、利用者から見ると打つ手がなくなる。

### 検証済みの事実

| 測ったこと | 結果 |
|------------|------|
| `ditto -c -k --sequesterRsrc --keepParent` → `ditto -x -k` 後の署名 | `valid on disk` / `satisfies its Designated Requirement` |
| 同上、実行ビットと `Info.plist` | `-rwxr-xr-x` のまま、`CFBundleShortVersionString` = `0.1.0` を読める |
| `zip -r` → `unzip` 後の署名 | 同じく valid（上記のとおり、この bundle では壊れない） |
| ad-hoc 署名 `Nagi.app` の `spctl -a -vv` | `rejected`（exit 3）。サイトの Gatekeeper 回避手順は実際に必要 |
| zip のサイズ | arm64 のみ 543 KB / universal 約 1 MB |
| `swift build --arch arm64 --arch x86_64`（CLT のみ） | `error: xcbuild executable ... does not exist`。使えない |
| `-Xswiftc -target x86_64-apple-macos14.0`（CLT のみ） | 通る。30.7s、`lipo -archs` = `x86_64`、`vtool` の minos = 14.0 |
| `lipo -create` した bundle | `x86_64 arm64`、1.8 MB、ad-hoc 署名も `codesign --verify` も通過 |
| `build-app.sh` の引数（既定 / `--debug` / `--universal` / 順序入替 / 未知） | 既定は arm64 のまま、`--universal --debug` は両方適用、`--bogus` は exit 1 |
| runner（フル Xcode）での `scripts/test.sh --skip "RealAppKit"` | **160 tests passed, 0.206s。** 下の「既知のリスク」は杞憂だった |
| CI 全体 | 56 秒で完走。`Nagi-0.1.0.zip` が v0.1.0 に付き、落として `codesign --verify` も通過 |

### 既知のリスク（解消済み）

`scripts/test.sh` をフル Xcode 環境で走らせたことがなかった。開発機は Command Line Tools
のみで、スクリプトの 2 つの分岐はどちらもその前提で書かれている。runner では
2 つ目の `-disable-cross-import-overlays` が**成立して付く**ので、そこが怪しいと見ていた。
実際には 160 本が 0.206 秒で通った。オーバーレイの API を使っていないという前提が正しかった。

### runner を固定する理由

`macos-latest` は予告なく上がる。リリース成果物を作る場所としては
`macos-15` に固定し、上げるときは意識的に上げる。

## universal ビルド

**最初の実装は arm64 単独の .app を配ってしまった。** macos-15 runner は Apple Silicon
なので既定ではそうなる。一方サイトは「macOS 14 Sonoma 以降」と書いていて、Sonoma は
Intel Mac も対象なので、起動できない人に配っていたことになる。
公開済みアセットを `lipo -archs` にかけて気づいた。

`scripts/build-app.sh --universal` を足し、CI だけがそれを渡す。ローカルの既定は
速い arm64 のまま（開発中に x86_64 を建てる意味がない）。

**`swift build --arch arm64 --arch x86_64` は使えない。** SwiftPM がそれを xcbuild に投げ、
xcbuild はフル Xcode にしか無い。「Command Line Tools だけでビルドできる」という
このプロジェクトの前提が壊れる。代わりに `-Xswiftc -target -Xswiftc x86_64-apple-macos<min>`
で x86_64 スライスを別 scratch path（`.build/x86_64`）に建て、`lipo -create` で束ねる。
これは CLT だけで通る。

deployment target は `Resources/Info.plist` の `LSMinimumSystemVersion` から読む。
二重に書かない理由は、arm64 スライスが `Package.swift` の `platforms:` から取るため、
食い違っても**他人の Intel Mac でしか露見しない**から。

CI には `lipo -archs` に両スライスが並ぶことを確かめるステップを入れた。
runner の世代が変わってビルドが片肺に戻ったとき、静かに配り続けないようにする。

### `workflow_dispatch` で古いタグを指すと、ビルドツールも古い版になる

ソースツリーをタグから取る、という設計の裏側。`scripts/build-app.sh` は
ソースと同じツリーに住んでいるので、**タグが古ければツールも古い**。

これは実際に踏んだ。`--universal` を足したあと `tag=v0.1.0` で手動実行したところ、
`ビルドする` ステップは**成功したのに** arm64 単独の .app が出来た。
v0.1.0 のツリーの `build-app.sh` は引数を `if [ "${1:-}" = "--debug" ]` でしか見ず、
知らない引数を**黙って捨てる**ためだった（このとき引数を検証するようにしたので、
今のツリーなら未知の引数は exit 1 になる）。

`lipo -archs` の確認ステップが無ければ、そのまま arm64 単独の zip が
リリースに上書きされていた。**このステップは飾りではない。**

解決は v0.1.0 タグを universal 対応後のコミットに付け替えることにした
（ダウンロード 0 件の時点だったので実害がなかった）。annotated タグだったので、
付け替えのときに lightweight にしないよう `-a` で作り直している。

## 手順

1. ~~ワークフローを main にマージする~~ 済
2. ~~Actions から `Release` を `tag=v0.1.0` で手動実行する~~ 済
3. ~~v0.1.0 に `Nagi-0.1.0.zip` が付き、サイトのダウンロードボタンが機能し始める~~ 済
4. ~~universal 対応を入れて arm64 単独のアセットを差し替える~~ 済。
   タグ付け替え → `on: push: tags` が自動で走り、`--clobber` が同名を置き換えた。
   最終形は 795,650 バイト、`x86_64 arm64`、両スライスとも minos 14.0、署名も検証済み

## 積み残し

- ~~v0.1.0 のリリース本文が空~~ 済。タイトルと本文を入れた
- ~~README の「インストール」がソースビルドしか書いていない~~ 済。
  ダウンロードを先に出し、ソースビルドを後ろに回した。`## 開発` に「リリース」節も足した
- **x86_64 スライスが実際に起動するところは未検証**。Intel 機がないため、
  `lipo` と `codesign` が通ることまでしか確かめていない
- Developer ID + 公証。加入したら `build-app.sh` の署名箇所を分岐させ、
  サイトと README とリリース本文から Gatekeeper の回避手順を消す
