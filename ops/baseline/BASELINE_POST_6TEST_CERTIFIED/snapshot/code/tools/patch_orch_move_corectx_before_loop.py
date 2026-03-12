# File: tools/patch_orch_move_corectx_before_loop.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    if "PATCH_MOVED_CORECTX=1" in txt:
        return 0

    # 1) find the core_context block (from "cc = detect_core_context" through the attach pass)
    m = re.search(
        r"(?ms)^\s*cc\s*=\s*detect_core_context.*?^\s*pass\s*$",
        txt,
    )
    if not m:
        return 2

    core_block = m.group(0)

    # 2) remove it from original place
    txt_wo = txt[:m.start()] + txt[m.end():]

    # 3) insert before "for strat in strategies:"
    m2 = re.search(r"(?m)^\s*for\s+strat\s+in\s+strategies\s*:\s*$", txt_wo)
    if not m2:
        return 3

    insert_pos = m2.start()

    marker = "        # PATCH_MOVED_CORECTX=1\n"
    txt_new = txt_wo[:insert_pos] + marker + core_block + "\n\n" + txt_wo[insert_pos:]

    P.write_text(txt_new, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
