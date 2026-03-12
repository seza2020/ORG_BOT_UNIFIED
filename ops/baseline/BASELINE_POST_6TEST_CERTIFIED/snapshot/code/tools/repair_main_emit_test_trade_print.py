from __future__ import annotations
from pathlib import Path
import re

ROOT = Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"

def main() -> int:
    src = MAIN.read_text(encoding="utf-8", errors="ignore")

    # 1) If the broken try/except block exists (introduced by patch_main_safe_print_ascii.py),
    # replace it with ONE safe ASCII print line.
    # This is intentionally flexible about indentation.
    broken_try_pat = re.compile(
        r"(?ms)^(?P<ind>[ \t]*)try:\s*\n"
        r"(?P=ind)[ \t]*print\(\"For testing use --smoke or --run or --emit_test_trade\.\"\)\s*\n"
        r"(?P=ind)[ \t]*except UnicodeEncodeError:\s*\n"
        r"(?P=ind)[ \t]*#.*?\n"
        r"(?P=ind)[ \t]*sys\.stdout\.buffer\.write\(b\"For testing use --smoke or --run or --emit_test_trade\\n\"\)\s*\n?"
    )

    def _fix_try(m: re.Match) -> str:
        ind = m.group("ind")
        return ind + 'print("For testing use --smoke or --run or --emit_test_trade.")\n'

    src2, n1 = broken_try_pat.subn(_fix_try, src, count=1)

    # 2) Also replace ANY print line that mentions --emit_test_trade (Persian or anything else)
    # with the same ASCII print line, preserving indentation.
    any_print_pat = re.compile(
        r"(?m)^(?P<ind>[ \t]*)print\((?P<q>['\"]).*--emit_test_trade.*(?P=q)\)\s*$"
    )

    def _fix_print(m: re.Match) -> str:
        ind = m.group("ind")
        return ind + 'print("For testing use --smoke or --run or --emit_test_trade.")'

    src3, n2 = any_print_pat.subn(_fix_print, src2)

    if (n1 + n2) == 0:
        print("NO_CHANGES: could not find broken try/print block nor any print containing --emit_test_trade")
        return 2

    MAIN.write_text(src3, encoding="utf-8")
    print("PATCHED:", str(MAIN), "fixed_try_block=", n1, "fixed_print_lines=", n2)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
