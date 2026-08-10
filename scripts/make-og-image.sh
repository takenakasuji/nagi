#!/bin/bash
# docs/og.png（SNS 共有カードの画像）を作り直す。
#
# サイト本体はビルド工程を持たないが、OGP の画像だけは例外的にラスタが要る。
# Twitter / Slack / Facebook はいずれも SVG を読まないため、SVG を指すと
# カードが画像なしになる。ここで 1 度だけ PNG に焼いて docs/ に置く。
#
# ページを書き換えたらこれも回し直すこと。中身はヒーローと揃えてある。
#
#   ./scripts/make-og-image.sh
#
# 出力: docs/og.png（1200 x 630）
set -euo pipefail

cd "$(dirname "$0")/.."

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [ ! -x "$CHROME" ]; then
  echo "Google Chrome が見つからない: $CHROME" >&2
  echo "OGP 画像の生成にはヘッドレス Chrome が要る。サイト本体のビルドには不要。" >&2
  exit 1
fi

SRC="$(mktemp -d)/og.html"
trap 'rm -rf "$(dirname "$SRC")"' EXIT

# 色・書体はすべて docs/style.css のライト側トークンと同じ値。
# ここは単独で焼く画像なので、カスタムプロパティではなく直接書いている。
cat > "$SRC" <<'HTML'
<!doctype html>
<html lang="ja">
<meta charset="utf-8">
<style>
  html, body { margin: 0; padding: 0; }
  body {
    box-sizing: border-box;
    width: 1200px;
    height: 630px;
    /* リードが横いっぱいになると端で切れて見える。余白を先に確保しておき、
       文言が伸びたときは溢れるのではなく折り返させる。 */
    padding-inline: 64px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 26px;
    background: linear-gradient(180deg, #EAF1F8, #FFFFFF);
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans",
                 "Hiragino Kaku Gothic ProN", "Noto Sans JP", sans-serif;
    color: #1D1D1F;
    -webkit-font-smoothing: antialiased;
  }
  .mark { width: 104px; height: 104px; color: #0060DF; }
  h1 { margin: 0; font-size: 96px; font-weight: 700; letter-spacing: .01em; line-height: 1; }
  h1 span { font-size: 46px; font-weight: 500; color: #68686D; }
  /* 36px。42px だと「AI 時代のマークダウンエディター。雑に書いて、速く貯める。」が
     全角約 28.5 文字 = 1197px となり、1200px の版面に対して余白が消える。 */
  .lead { margin: 0; font-size: 36px; font-weight: 500; text-align: center; }
  .meta { margin: 0; font-size: 26px; font-weight: 400; color: #68686D; }
</style>
<body>
  <svg class="mark" viewBox="0 0 48 48" fill="none" stroke="currentColor"
       stroke-width="3.5" stroke-linecap="round">
    <path d="M4 16h24a6 6 0 1 0-6-6"/>
    <path d="M4 24h30a6 6 0 1 1-6 6"/>
    <path d="M4 32h18"/>
  </svg>
  <h1>Nagi<span>（凪）</span></h1>
  <p class="lead">AI 時代のマークダウンエディター。雑に書いて、速く貯める。</p>
  <p class="meta">macOS 14 Sonoma 以降 · 無料 · MIT ライセンス</p>
</body>
</html>
HTML

"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --window-size=1200,630 \
  --screenshot="docs/og.png" \
  --virtual-time-budget=3000 \
  "file://$SRC" >/dev/null 2>&1

if [ ! -s docs/og.png ]; then
  echo "docs/og.png が生成されなかった" >&2
  exit 1
fi

echo "docs/og.png: $(/usr/bin/stat -f%z docs/og.png) bytes"
