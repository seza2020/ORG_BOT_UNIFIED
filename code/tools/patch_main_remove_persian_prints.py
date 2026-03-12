from __future__ import annotations
from pathlib import Path
import re

TARGET = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")

# Any Arabic/Persian Unicode blocks (no Persian literals in this file)
FA_RE = re.compile(r"[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]")

EN_MSG = "Use --smoke, --run, or --emit_test_trade to run tests."

def patch_print_lines(src: str) -> tuple[str, int]:
    """
    Replace any print(...) line that contains Persian/Arabic characters with an English message,
    but only for the common CLI guidance message area (keeps other content intact).
    """
    lines = src.splitlines()
    out = []
    hits = 0

    for ln in lines:
        if "print" in ln and FA_RE.search(ln):
            # Heuristic: this message usually mentions one of these flags
            if ("--smoke" in ln) or ("--run" in ln) or ("--emit_test_trade" in ln) or ("emit_test_trade" in ln):
                indent = ln[: len(ln) - len(ln.lstrip(" "))]
                out.append(f'{indent}print("{EN_MSG}")')
                hits += 1
                continue
        out.append(ln)

    return ("\n".join(out) + ("\n" if src.endswith("\n") else "")), hits

def main():
    s = TARGET.read_text(encoding="utf-8", errors="replace")
    s2, hits = patch_print_lines(s)

    if hits > 0 and s2 != s:
        TARGET.write_text(s2, encoding="utf-8", newline="\n")
        print("PATCHED:", str(TARGET), "replaced_lines=", hits)
    else:
        print("NO_CHANGES:", str(TARGET), "(no matching Persian print-lines found)")

if __name__ == "__main__":
    main()
