from __future__ import annotations
from pathlib import Path

TARGET = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")

REPLS = [
    # Common Persian message seen in your logs
    ("Use --smoke, --run, or --emit_test_trade to run tests.",
     "Use --smoke, --run, or --emit_test_trade to run tests."),
  ("  --smoke --run --emit_test_trade ",
     "Use --smoke, --run, or --emit_test_trade to run tests."),
]

def main():
    s = TARGET.read_text(encoding="utf-8", errors="replace")
    s2 = s
    hits = 0
    for a, b in REPLS:
        if a in s2:
            s2 = s2.replace(a, b)
            hits += 1

    if s2 != s:
        TARGET.write_text(s2, encoding="utf-8", newline="\n")
        print("PATCHED:", str(TARGET), "replacements=", hits)
    else:
        print("NO_CHANGES:", str(TARGET), "(message not found)")

if __name__ == "__main__":
    main()
