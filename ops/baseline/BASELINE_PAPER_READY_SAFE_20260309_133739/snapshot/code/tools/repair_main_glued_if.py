from __future__ import annotations
import re
from pathlib import Path

TARGET = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")

def main():
    s = TARGET.read_text(encoding="utf-8", errors="ignore")

    # Fix the common "else 0if __name__" / "else 0if__name__" corruption
    s2 = re.sub(r'else\s+0\s*if\s+__name__', 'else 0\n\nif __name__', s)
    s2 = re.sub(r'else\s+0if\s+__name__', 'else 0\n\nif __name__', s2)
    s2 = re.sub(r'else\s+0if__name__', 'else 0\n\nif __name__', s2)

    # Also fix any "return ... else 0if" variant (more general)
    s2 = re.sub(r'(else\s+0)\s*if\b', r'\1\n\nif', s2)

    if s2 != s:
        TARGET.write_text(s2, encoding="utf-8", newline="\n")
        print("PATCHED:", str(TARGET))
    else:
        print("NO_CHANGES: pattern not found (file may already be fixed).")

if __name__ == "__main__":
    main()
