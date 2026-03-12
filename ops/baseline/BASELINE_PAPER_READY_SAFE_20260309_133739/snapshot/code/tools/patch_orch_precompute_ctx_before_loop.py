# File: tools/patch_orch_precompute_ctx_before_loop.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # idempotent
    if "PATCH_PRECOMPUTE_CTX_BEFORE_LOOP=1" in txt:
        return 0

    # find the first "for strat in strategies:" (this is our insertion anchor)
    m = re.search(r"(?m)^(?P<indent>\s*)for\s+strat\s+in\s+strategies\s*:\s*$", txt)
    if not m:
        return 2

    indent = m.group("indent")

    block = (
        f"{indent}# PATCH_PRECOMPUTE_CTX_BEFORE_LOOP=1\n"
        f"{indent}# Precompute + attach core_context/alpha_mode for strategy access (safe)\n"
        f"{indent}try:\n"
        f"{indent}    if getattr(ctx, 'core_context', None) is None:\n"
        f"{indent}        cc = detect_core_context(symbol=str(symbols[0] if symbols else 'NA'), snap=(market.get(symbols[0]) if symbols else object()))\n"
        f"{indent}        ev = make_event(level='INFO', kind='core_context', payload={{\n"
        f"{indent}            'bias': cc.bias,\n"
        f"{indent}            'trend_strength': cc.trend_strength,\n"
        f"{indent}            'vwap_state': cc.vwap_state,\n"
        f"{indent}            'ema_sep': cc.ema_sep,\n"
        f"{indent}            'reason': cc.reason,\n"
        f"{indent}        }})\n"
        f"{indent}        meta.emit(ev); announce.emit(ev)\n"
        f"{indent}        try:\n"
        f"{indent}            setattr(ctx, 'core_context', cc)\n"
        f"{indent}        except Exception:\n"
        f"{indent}            pass\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n\n"
        f"{indent}try:\n"
        f"{indent}    if getattr(ctx, 'alpha_mode', None) is None:\n"
        f"{indent}        # rr should already exist in this loop; fall back safely if not\n"
        f"{indent}        _rr = locals().get('rr', None)\n"
        f"{indent}        dec = decide_alpha_mode(regime=(getattr(_rr, 'regime', 'TREND') if _rr is not None else 'TREND'))\n"
        f"{indent}        ev = make_event(level='INFO', kind='alpha_mode', payload={{'mode': dec.mode, 'cap_ratio': dec.cap_ratio, 'reason': dec.reason}})\n"
        f"{indent}        meta.emit(ev); announce.emit(ev)\n"
        f"{indent}        try:\n"
        f"{indent}            setattr(ctx, 'alpha_mode', dec.mode)\n"
        f"{indent}        except Exception:\n"
        f"{indent}            pass\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n\n"
    )

    # insert block right before the for-loop
    insert_pos = m.start()
    txt = txt[:insert_pos] + block + txt[insert_pos:]

    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
