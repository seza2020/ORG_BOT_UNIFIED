from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(r"C:\alpaca-bot\org_bot")
MAIN = ROOT / "tbot" / "main.py"

def ensure_sys_import(src: str) -> str:
    # Add "import sys" if not present anywhere in file.
    if re.search(r"(?m)^\s*import\s+sys\s*$", src):
        return src
    # Insert after first block of imports (simple heuristic).
    lines = src.splitlines(True)
    out = []
    inserted = False
    for i, ln in enumerate(lines):
        out.append(ln)
        if not inserted:
            # after a run of import lines, insert sys once
            if i > 0 and re.match(r"^\s*(import|from)\s+", lines[i-1]) and not re.match(r"^\s*(import|from)\s+", ln):
                out.insert(len(out)-1, "import sys\n")
                inserted = True
    if not inserted:
        # fallback: top of file
        return "import sys\n" + src
    return "".join(out)

def patch_print(src: str) -> tuple[str, int]:
    # Replace the problematic Persian print (often written with \\u escapes) with safe ASCII print.
    # Match any print(...) line that mentions --emit_test_trade (unique anchor).
    pat = re.compile(r"(?m)^\s*print\((?P<q>['\"]).*--emit_test_trade.*(?P=q)\)\s*$")
    if not pat.search(src):
        return src, 0

    repl = (
        "    try:\n"
        "        print(\"For testing use --smoke or --run or --emit_test_trade.\")\n"
        "    except UnicodeEncodeError:\n"
        "        # Windows consoles sometimes default to cp1252; write ASCII bytes directly.\n"
        "        sys.stdout.buffer.write(b\"For testing use --smoke or --run or --emit_test_trade.\\n\")\n"
    )
    # Preserve indentation by capturing leading spaces
    pat2 = re.compile(r"(?m)^(?P<indent>\s*)print\((?P<q>['\"]).*--emit_test_trade.*(?P=q)\)\s*$")
    def _sub(m: re.Match) -> str:
        ind = m.group("indent")
        # repl already has 4-space indent; normalize to "ind"
        return repl.replace("    ", ind)
    new = pat2.sub(_sub, src, count=1)
    return new, 1

def main() -> int:
    src = MAIN.read_text(encoding="utf-8", errors="ignore")
    src2 = ensure_sys_import(src)
    src3, n = patch_print(src2)
    if n == 0:
        print("NO_CHANGES: could not find the print line containing --emit_test_trade")
        return 2
    MAIN.write_text(src3, encoding="utf-8")
    print("PATCHED:", str(MAIN))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
