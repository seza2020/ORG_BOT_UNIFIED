from __future__ import annotations
from pathlib import Path
import re

ROOTS = [Path("tbot"), Path("tools")]

FA_RE = re.compile(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]")

def main():
    hits = 0
    for root in ROOTS:
        if not root.exists():
            continue
        for p in root.rglob("*.py"):
            parts = {x.lower() for x in p.parts}
            if "__pycache__" in parts or ".venv" in parts or "venv" in parts:
                continue
            text = p.read_text(encoding="utf-8", errors="replace")
            for i, line in enumerate(text.splitlines(), start=1):
                if FA_RE.search(line):
                    preview = line.strip()
                    if len(preview) > 200:
                        preview = preview[:200] + "..."
                    print(f"{p}:{i}: {preview}")
                    hits += 1
    print("DONE hits=", hits)

if __name__ == "__main__":
    main()
