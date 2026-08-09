#!/usr/bin/env python3
"""配布サイトのカラートークンの WCAG コントラスト比を検証する。

半透明の面（--material）は合成後の実効色で測る。標準ライブラリだけで動く。

    python3 specs/contrast.py

すべて合格なら終了コード 0、1 つでも落ちれば 1。
"""

import sys


def _linear(channel: int) -> float:
    c = channel / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def _rgb(color: str) -> tuple[int, int, int]:
    h = color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def luminance(color: str) -> float:
    r, g, b = _rgb(color)
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b)


def ratio(fg: str, bg: str) -> float:
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def over(fg: str, alpha: float, bg: str) -> str:
    """半透明の fg を bg の上に重ねた実効色。"""
    f, b = _rgb(fg), _rgb(bg)
    return "#%02X%02X%02X" % tuple(round(alpha * f[i] + (1 - alpha) * b[i]) for i in range(3))


def mix(a: str, ratio: float, b: str) -> str:
    """CSS の color-mix(in srgb, a <ratio>%, b) と同じ計算。"""
    return over(a, ratio, b)


# --- トークン（docs/style.css と一致させること） ---------------------------

LIGHT_MATERIAL = over("#FFFFFF", 0.72, "#EAF1F8")  # -> #F9FBFD
DARK_MATERIAL = over("#3A3A3C", 0.66, "#16202B")  # -> #2E3136

# hover の色も測る。トークンだけ測っていると color-mix() で作った状態が
# 素通りする（実際、ダークの secondary hover が 4.2:1 まで落ちていた）。
LIGHT_PRIMARY_HOVER = mix("#0060DF", 0.88, "#000000")
DARK_PRIMARY_HOVER = mix("#0A6ADF", 0.88, "#000000")

# (説明, 前景, 背景, 必要な比)
CHECKS = [
    ("ライト label      on bg", "#1D1D1F", "#FFFFFF", 4.5),
    ("ライト label      on hero-from", "#1D1D1F", "#EAF1F8", 4.5),
    ("ライト secondary  on bg", "#68686D", "#FFFFFF", 4.5),
    ("ライト secondary  on bg-subtle", "#68686D", "#F5F5F7", 4.5),
    ("ライト secondary  on hero-from", "#68686D", "#EAF1F8", 4.5),
    ("ライト secondary  on material", "#68686D", LIGHT_MATERIAL, 4.5),
    ("ライト accent     on bg", "#0060DF", "#FFFFFF", 4.5),
    ("ライト accent     on hero-from", "#0060DF", "#EAF1F8", 4.5),
    ("ライト 白         on accent-fill", "#FFFFFF", "#0060DF", 4.5),
    ("ダーク label      on bg", "#F5F5F7", "#1C1C1E", 4.5),
    ("ダーク label      on bg-subtle", "#F5F5F7", "#000000", 4.5),
    ("ダーク label      on material", "#F5F5F7", DARK_MATERIAL, 4.5),
    ("ダーク secondary  on bg", "#A1A1A6", "#1C1C1E", 4.5),
    ("ダーク secondary  on bg-subtle", "#A1A1A6", "#000000", 4.5),
    ("ダーク secondary  on hero-from", "#A1A1A6", "#16202B", 4.5),
    ("ダーク secondary  on material", "#A1A1A6", DARK_MATERIAL, 4.5),
    ("ダーク accent     on bg", "#0A84FF", "#1C1C1E", 4.5),
    ("ダーク accent     on hero-from", "#0A84FF", "#16202B", 4.5),
    ("ダーク 白         on accent-fill", "#FFFFFF", "#0A6ADF", 4.5),
    # hover 状態。secondary は hover で --bg を敷くので accent on bg に帰着するが、
    # 「上の行と同じだから」で済ませると読む側が追えないので明示的に並べる。
    ("ライト 白         on primary hover", "#FFFFFF", LIGHT_PRIMARY_HOVER, 4.5),
    ("ダーク 白         on primary hover", "#FFFFFF", DARK_PRIMARY_HOVER, 4.5),
    ("ライト accent     on secondary hover", "#0060DF", "#FFFFFF", 4.5),
    ("ダーク accent     on secondary hover", "#0A84FF", "#1C1C1E", 4.5),
]

# エディタ本文領域の背景。**実効背景（合成後）ではない。**
#
# 採り方: 使い捨てのテストで本物のパネルを組み立て、
# `bitmapImageRepForCachingDisplay` + `cacheDisplay(in:to:)` でオフスクリーンに
# 描かせ、本文の余白 6 点を読んだ（ライト・ダークとも 6 点すべて同値、alpha 1.0）。
#
# オフスクリーン描画には窓の背後にあるものが入らないので、ここに出てくるのは
# `.regularMaterial` の**不透明フォールバック**であって、実際に画面で起きている
# 合成の結果ではない。実機の窓を、明るい下地と暗い下地の上それぞれで
# デジタルカラーメーターで読む、という測定はまだ行っていない。
# 本文の色に余裕を持たせてあるのはこの不確かさを吸収するため（設計書を参照）。
EDITOR_LIGHT_BG = "#F4F4F4"
EDITOR_DARK_BG = "#2F2F2F"

CHECKS += [
    ("エディタ 本文 (light)",   "#1C1C1E", EDITOR_LIGHT_BG, 4.5),
    ("エディタ 見出し (light)", "#0A58CA", EDITOR_LIGHT_BG, 4.5),
    ("エディタ コード (light)", "#1F7A3D", EDITOR_LIGHT_BG, 4.5),
    ("エディタ リンク (light)", "#7A34C4", EDITOR_LIGHT_BG, 4.5),
    ("エディタ 引用 (light)",   "#666B72", EDITOR_LIGHT_BG, 4.5),
    ("エディタ 本文 (dark)",    "#E4E4E6", EDITOR_DARK_BG, 4.5),
    ("エディタ 見出し (dark)",  "#6FA8FF", EDITOR_DARK_BG, 4.5),
    ("エディタ コード (dark)",  "#7FCE8F", EDITOR_DARK_BG, 4.5),
    ("エディタ リンク (dark)",  "#C08CF0", EDITOR_DARK_BG, 4.5),
    ("エディタ 引用 (dark)",    "#9AA0A8", EDITOR_DARK_BG, 4.5),
]

# 却下した値。再導入されていないことを確かめるための記録。
REJECTED = [
    ("#007AFF は白文字で不足", "#FFFFFF", "#007AFF", 4.5),
    ("#0A84FF の塗り＋白文字は不足", "#FFFFFF", "#0A84FF", 4.5),
    ("#6E6E73 はグラデ上端で不足", "#6E6E73", "#EAF1F8", 4.5),
    ("#86868B（tertiary）は白地で不足", "#86868B", "#FFFFFF", 4.5),
    ("accent をダークの材質に文字で乗せると不足", "#0A84FF", DARK_MATERIAL, 4.5),
    # 却下した hover 案: ダークで accent を 8% ティントすると背景が青寄りになり、
    # 同色の accent 文字とのコントラストが 4.5 を割る（安静時が 4.51 しかないため）。
    ("accent 8% ティント上の accent 文字は不足", "#0A84FF", mix("#0A84FF", 0.08, "#16202B"), 4.5),
]

# コントラストでは測れないが記録しておく却下案:
# secondary の hover を accent-fill の塗り＋白文字にする案は 5.62 / 5.07 で
# 数値上は通るが、隣の primary の安静時と画素単位で同一になり主従が消える。
# 数値だけ見て再導入しないこと。


def main() -> int:
    print(f"材質の合成後  ライト: {LIGHT_MATERIAL}  ダーク: {DARK_MATERIAL}\n")

    failed = 0
    for label, fg, bg, need in CHECKS:
        r = ratio(fg, bg)
        ok = r >= need
        failed += not ok
        print(f"  {'OK  ' if ok else 'FAIL'} {label:32s} {fg} on {bg}  {r:5.2f}:1")

    print("\n却下した値（いずれも不足していることの確認）:")
    for label, fg, bg, need in REJECTED:
        r = ratio(fg, bg)
        still_bad = r < need
        failed += not still_bad
        print(f"  {'OK  ' if still_bad else 'FAIL'} {label:38s} {r:5.2f}:1")

    print()
    if failed:
        print(f"{failed} 件が期待どおりでない")
        return 1
    print("すべて期待どおり")
    return 0


if __name__ == "__main__":
    sys.exit(main())
