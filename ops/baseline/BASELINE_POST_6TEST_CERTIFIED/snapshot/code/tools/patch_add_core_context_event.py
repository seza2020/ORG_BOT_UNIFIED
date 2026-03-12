# File: tools/patch_add_core_context_event.py
from __future__ import annotations

from pathlib import Path

TARGET = Path(r".\tbot\runtime\orchestrator.py")

IMPORT_LINE = "from tbot.core.engine import detect_core_context"
IMPORT_ANCHOR = "from tbot.regime.overlay import overlay_for_regime"

INSERT_ANCHOR = "meta.emit(ev); announce.emit(ev)"  # first occurrence after regime event is emitted

BLOCK = """
        cc = detect_core_context(symbol=str(symbols[0] if symbols else 'NA'), snap=(market.get(symbols[0]) if symbols else object()))
        ev = make_event(level="INFO", kind="core_context", payload={
            "bias": cc.bias,
            "trend_strength": cc.trend_strength,
            "vwap_state": cc.vwap_state,
            "ema_sep": cc.ema_sep,
            "reason": cc.reason,
        })
        meta.emit(ev); announce.emit(ev)
"""

def main() -> int:
    txt = TARGET.read_text(encoding="utf-8")

    # 1) ensure import
    if IMPORT_LINE not in txt:
        if IMPORT_ANCHOR in txt:
            txt = txt.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + "\n" + IMPORT_LINE, 1)
        else:
            return 2

    # 2) insert block only once (idempotent)
    if 'kind="core_context"' not in txt and "kind='core_context'" not in txt:
        # We want to insert after the regime emit, not after other emits.
        # Anchor: the first occurrence AFTER the regime event creation line `kind="regime"`
        idx_reg = txt.find('kind="regime"')
        if idx_reg < 0:
            return 3
        idx_emit = txt.find(INSERT_ANCHOR, idx_reg)
        if idx_emit < 0:
            return 4

        # insert after the emit line
        line_end = txt.find("\n", idx_emit)
        if line_end < 0:
            line_end = idx_emit + len(INSERT_ANCHOR)

        txt = txt[:line_end+1] + BLOCK + txt[line_end+1:]

    TARGET.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
