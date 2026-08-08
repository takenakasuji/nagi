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


# --- トークン（docs/style.css と一致させること） ---------------------------

LIGHT_MATERIAL = over("#FFFFFF", 0.72, "#EAF1F8")  # -> #F9FBFD
DARK_MATERIAL = over("#3A3A3C", 0.66, "#16202B")  # -> #2E3136

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
]

# 却下した値。再導入されていないことを確かめるための記録。
REJECTED = [
    ("#007AFF は白文字で不足", "#FFFFFF", "#007AFF", 4.5),
    ("#0A84FF の塗り＋白文字は不足", "#FFFFFF", "#0A84FF", 4.5),
    ("#6E6E73 はグラデ上端で不足", "#6E6E73", "#EAF1F8", 4.5),
    ("#86868B（tertiary）は白地で不足", "#86868B", "#FFFFFF", 4.5),
    ("accent をダークの材質に文字で乗せると不足", "#0A84FF", DARK_MATERIAL, 4.5),
]


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
