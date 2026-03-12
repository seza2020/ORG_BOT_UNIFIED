# File: tools/persian_scan.py
from __future__ import annotations

import os
import sys

RANGES = [
    (0x0600, 0x06FF),
    (0x0750, 0x077F),
    (0x08A0, 0x08FF),
    (0xFB50, 0xFDFF),
    (0xFE70, 0xFEFF),
]

def is_persian_char(ch: str) -> bool:
    o = ord(ch)
    return any(a <= o <= b for a, b in RANGES)

def main() -> int:
    hits = 0
    for dirpath, _, filenames in os.walk("."):
        for fn in filenames:
            if not fn.lower().endswith(".py"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                text = open(path, "r", encoding="utf-8").read()
            except Exception as e:
                print(f"[READ_FAIL] {path} :: {e}")
                continue

            for i, line in enumerate(text.splitlines(), 1):
                for j, ch in enumerate(line, 1):
                    if is_persian_char(ch):
                        hits += 1
                        snippet = line.strip()
                        if len(snippet) > 160:
                            snippet = snippet[:160] + "..."
                        print(f"[PERSIAN] {path}:{i}:{j} U+{ord(ch):04X} {repr(ch)} :: {snippet}")
                        if hits >= 50:
                            print("[STOP] too many hits, aborting early.")
                            return 2

    print(f"DONE. Persian-char hits = {hits}")
    return 0 if hits == 0 else 1

if __name__ == '__main__':
    raise SystemExit(main())
