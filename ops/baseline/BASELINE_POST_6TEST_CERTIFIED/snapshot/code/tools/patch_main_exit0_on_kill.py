import re
from pathlib import Path
from datetime import datetime

p = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
src = p.read_text(encoding="utf-8", errors="replace")

bak = p.with_suffix(p.suffix + ".bak_exit0_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
bak.write_text(src, encoding="utf-8", newline="\n")

# 1) Kill any explicit process-exit from our code (but keep argparse's own SystemExit behavior).
# We only patch occurrences in our file.
src2 = re.sub(
    r'^(?P<indent>\s*)(?:raise\s+SystemExit|sys\.exit)\s*\(.*\)\s*$',
    r'\g<indent>return 0  # patched: suppress nonzero exit on normal shutdown',
    src,
    flags=re.M
)

# 2) Ensure __main__ runner is a plain call (no SystemExit wrapper)
# Replace from the __main__ block to EOF.
src2 = re.sub(
    r'if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*.*\Z',
    'if __name__ == "__main__":\n    main()\n',
    src2,
    flags=re.S
)

if src2 == src:
    print("NO_CHANGES: main.py already looks exit0-safe (or patterns not found).")
else:
    p.write_text(src2, encoding="utf-8", newline="\n")
    print("PATCHED:", str(p))
    print("BACKUP :", str(bak))

