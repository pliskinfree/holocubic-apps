#!/usr/bin/env python3
"""Generate deterministic SC, Taiwan Big5 level-1, and Japanese JIS level-1 charsets."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FONT_TOOL = Path(r"E:\cubicsrc\cubic_lua\cubic_arduino\cubic-develop\tools\font")
PUNCTUATION = "，。！？；：、（）《》〈〉【】〔〕［］｛｝“”‘’—…·￥「」『』～・〜％℃℉‰°±×÷≤≥≈←↑→↓"


def dedupe(text: str) -> str:
    return "".join(dict.fromkeys(text))


def project_chars() -> str:
    chars: list[str] = []
    for relative in (
        "launcher/package/main.lua",
        "BTC/package/i18n.lua",
        "BTC/package/ui.lua",
        "weather/package/main.lua",
    ):
        text = (ROOT / relative).read_text(encoding="utf-8")
        chars.extend(re.findall(r"[\u3000-\u30ff\u3400-\u9fff\uf900-\ufaff]", text))
    return dedupe("".join(chars))


def big5_level1() -> str:
    chars: list[str] = []
    for lead in range(0xA4, 0xC7):
        for trail in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            if lead == 0xC6 and trail > 0x7E:
                break
            try:
                char = bytes((lead, trail)).decode("big5")
            except UnicodeDecodeError:
                continue
            if len(char) == 1:
                chars.append(char)
    return dedupe("".join(chars))


def jis_level1() -> str:
    chars: list[str] = []
    for ku in range(16, 48):
        for ten in range(1, 95):
            try:
                char = bytes((ku + 0xA0, ten + 0xA0)).decode("euc_jp")
            except UnicodeDecodeError:
                continue
            if len(char) == 1 and "\u3400" <= char <= "\u9fff":
                chars.append(char)
    kana = "".join(chr(code) for code in range(0x3041, 0x30FB)) + "ー々〆ヶ"
    return dedupe(kana + "".join(chars))


def main() -> None:
    sc_source = (FONT_TOOL / "common_hanzi_4000_unique.txt").read_text(encoding="utf-8").strip()
    extras = project_chars()
    charsets = {
        "zh_cn": dedupe(PUNCTUATION + extras + sc_source),
        "zh_tw": dedupe(PUNCTUATION + extras + big5_level1()),
        "ja": dedupe(PUNCTUATION + extras + jis_level1()),
    }
    for name, chars in charsets.items():
        output = ROOT / "tools" / f"charset_{name}.txt"
        output.write_text(chars, encoding="utf-8")
        print(f"[charset] {name}: {len(chars)} -> {output}")


if __name__ == "__main__":
    main()
