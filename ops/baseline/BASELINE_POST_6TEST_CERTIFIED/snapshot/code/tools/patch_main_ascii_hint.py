from pathlib import Path
from datetime import datetime

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
src = P.read_text(encoding="utf-8", errors="replace")

bak = P.with_suffix(P.suffix + ".bak_ascii_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
bak.write_text(src, encoding="utf-8", newline="\n")

# Replace Persian hint with ASCII (prevents cp1252 UnicodeEncodeError in subprocess)
persian = "Use --smoke, --run, or --emit_test_trade to run tests."
ascii_msg = "For testing use --smoke or --run or --emit_test_trade."

changed = 0
if persian in src:
    src = src.replace(persian, ascii_msg)
    changed += 1

# Also catch the escaped-unicode form if it exists in file as a literal
escaped = "\\u0628\\u0631\\u0627\\u06cc \\u062a\\u0633\\u062a \\u0627\\u0632 --smoke \\u06cc\\u0627 --run \\u06cc\\u0627--emit_test_trade \\u0627\\u0633\\u062a\\u0641\\u0627\\u062f\\u0647 \\u06a9\\u0646."
if escaped in src:
    src = src.replace(escaped, ascii_msg)
    changed += 1

P.write_text(src, encoding="utf-8", newline="\n")
print(f"PATCHED: {P} | changes={changed} | backup={bak}")
