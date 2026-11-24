#!/usr/bin/env python3
"""Cut Noto Sans JP down to what the three mods draw: kana, CJK punctuation,
full-width forms, and every character in their lang/ja.lua files.
Usage: build_font.py <NotoSansJP-Regular.ttf> <out.ttf> <ja.lua>..."""
import subprocess, sys, tempfile
src, out, files = sys.argv[1], sys.argv[2], sys.argv[3:]
chars = set()
for f in files:
    chars |= set(open(f, encoding="utf-8").read())
for a, b in [(0x3000, 0x303F), (0x3040, 0x309F), (0x30A0, 0x30FF), (0xFF01, 0xFF5E), (0xFF61, 0xFF9F)]:
    chars |= {chr(c) for c in range(a, b + 1)}
text = "".join(sorted(c for c in chars if ord(c) > 0x2000))
with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".txt", delete=False) as t:
    t.write(text)
subprocess.run(["pyftsubset", src, "--text-file=" + t.name, "--output-file=" + out, "--layout-features=",
                "--no-hinting", "--drop-tables+=vhea,vmtx,BASE,STAT,GPOS,GSUB", "--name-IDs=*"], check=True)
print(f"{len(text)} characters -> {out}")
