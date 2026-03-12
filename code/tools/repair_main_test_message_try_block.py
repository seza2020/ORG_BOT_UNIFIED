from __future__ import annotations
from pathlib import Path
import re, shutil
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"

MSG = 'For testing use --smoke or --run or --emit_test_trade.'

def main() -> int:
    if not MAIN.exists():
        print("ERROR: not found:", str(MAIN))
        return 2

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    bk = MAIN.with_suffix(f".py.bak_fix_try_{ts}")
    shutil.copy2(MAIN, bk)

    src = MAIN.read_text(encoding="utf-8", errors="ignore")
    lines = src.splitlines(True)

    joined = "".join(lines)

    pat_try_block = re.compile(
        r"(?ms)^(?P<ind>[ \t]*)try:\s*\n"
        r"(?:(?P=ind)[ \t]*.*\n){0,10}?"
        r"(?P=ind)(?P<bodyind>[ \t]*)print\((?P<q>['\"]).*?For testing use --smoke.*?(?P=q)\)\s*\n"
        r"(?:(?P=ind)[ \t]*.*\n){0,10}?"
        r"(?P=ind)except\s+UnicodeEncodeError\s*:\s*\n"
        r"(?:(?P=ind)[ \t]+.*\n){1,10}"
    )

    def repl_try(m: re.Match) -> str:
        ind = m.group("ind")
        return ind + f'print({MSG!r})\n'

    joined2, n1 = pat_try_block.subn(repl_try, joined, count=1)

    if n1 == 0:
        pat_orphan_try = re.compile(
            r"(?ms)^(?P<ind>[ \t]*)try:\s*\n"
            r"(?:(?P=ind)[ \t]*.*\n){0,15}?"
            r"(?P=ind)print\((?P<q>['\"]).*?For testing use --smoke.*?(?P=q)\)\s*\n"
        )
        joined2, n2 = pat_orphan_try.subn(repl_try, joined, count=1)
    else:
        n2 = 0

    pat_any_print = re.compile(
        r"(?m)^(?P<ind>[ \t]*)print\((?P<q>['\"]).*--emit_test_trade.*(?P=q)\)\s*$"
    )
    def repl_print(m: re.Match) -> str:
        return m.group("ind") + f'print({MSG!r})'
    joined3, n3 = pat_any_print.subn(repl_print, joined2)

    if (n1 + n2 + n3) == 0:
        print("NO_CHANGES: could not find any test-message try/print block to fix")
        print("BACKUP   :", str(bk))
        return 2

    MAIN.write_text(joined3, encoding="utf-8")
    print("PATCHED:", str(MAIN))
    print("BACKUP :", str(bk))
    print("HITS   :", {"try_block": n1, "orphan_try": n2, "print_lines": n3})
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
