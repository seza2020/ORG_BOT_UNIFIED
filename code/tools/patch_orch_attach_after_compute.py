# File: tools/patch_orch_attach_after_compute.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def insert_after_line(txt: str, pattern: str, inject: str) -> str:
    m = re.search(pattern, txt, flags=re.M)
    if not m:
        return txt
    line_end = txt.find("\n", m.end())
    if line_end < 0:
        line_end = len(txt)
    return txt[:line_end+1] + inject + txt[line_end+1:]

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # idempotent: if already attached, do nothing
    if 'setattr(ctx, "core_context"' in txt and 'setattr(ctx, "alpha_mode"' in txt:
        return 0

    # --- core_context attach (after compute) ---
    if 'setattr(ctx, "core_context"' not in txt:
        pat_cc = r'^\s*cc\s*=\s*detect_core_context\(.+\)\s*$'
        # detect indent from the cc line
        m = re.search(pat_cc, txt, flags=re.M)
        if not m:
            return 2
        indent = re.match(r'^\s*', m.group(0)).group(0)
        inject_cc = (
            f'{indent}# Attach core_context to ctx for strategy access (safe)\n'
            f'{indent}try:\n'
            f'{indent}    setattr(ctx, "core_context", cc)\n'
            f'{indent}except Exception:\n'
            f'{indent}    pass\n'
        )
        txt = insert_after_line(txt, pat_cc, inject_cc)

    # --- alpha_mode attach (after compute) ---
    if 'setattr(ctx, "alpha_mode"' not in txt:
        pat_dec = r'^\s*dec\s*=\s*decide_alpha_mode\(.+\)\s*$'
        m2 = re.search(pat_dec, txt, flags=re.M)
        if not m2:
            return 3
        indent2 = re.match(r'^\s*', m2.group(0)).group(0)
        inject_dec = (
            f'{indent2}# Attach alpha_mode to ctx for strategy access (safe)\n'
            f'{indent2}try:\n'
            f'{indent2}    setattr(ctx, "alpha_mode", dec.mode)\n'
            f'{indent2}except Exception:\n'
            f'{indent2}    pass\n'
        )
        txt = insert_after_line(txt, pat_dec, inject_dec)

    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
