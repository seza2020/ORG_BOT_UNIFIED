# File: tools/patch_ctx_attach_core_alpha.py
from __future__ import annotations

from pathlib import Path

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # 1) attach core_context after we compute cc (near core_context event)
    if 'setattr(ctx, "core_context"' not in txt:
        anchor = 'kind="core_context"'
        idx = txt.find(anchor)
        if idx < 0:
            return 2

        # find the meta.emit for core_context event and insert after it
        idx_emit = txt.find("meta.emit(ev); announce.emit(ev)", idx)
        if idx_emit < 0:
            return 3
        line_end = txt.find("\n", idx_emit)
        if line_end < 0:
            return 4

        block = """
        # Attach core_context to ctx for strategy access (safe)
        try:
            setattr(ctx, "core_context", cc)
        except Exception:
            pass
"""
        txt = txt[:line_end+1] + block + txt[line_end+1:]

    # 2) attach alpha_mode after we compute dec (near alpha_mode event)
    if 'setattr(ctx, "alpha_mode"' not in txt:
        anchor2 = 'kind="alpha_mode"'
        idx2 = txt.find(anchor2)
        if idx2 < 0:
            return 5

        # insert before alpha_mode event emit is fine
        idx_ev = txt.rfind("ev = make_event", 0, idx2)
        if idx_ev < 0:
            return 6

        block2 = """
        # Attach alpha_mode to ctx for strategy access (safe)
        try:
            setattr(ctx, "alpha_mode", dec.mode)
        except Exception:
            pass

"""
        txt = txt[:idx_ev] + block2 + txt[idx_ev:]

    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
