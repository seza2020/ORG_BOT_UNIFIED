# File: tools/patch_alpha_mode_enforce.py
from __future__ import annotations

from pathlib import Path

P = Path(r".\tbot\runtime\orchestrator.py")

IMPORT_ANCHOR = "from tbot.core.engine import detect_core_context"
IMPORT_LINE = "from tbot.policy.alpha_mode import decide_alpha_mode"

def main() -> int:
    txt = P.read_text(encoding="utf-8")

    # import
    if IMPORT_LINE not in txt:
        if IMPORT_ANCHOR in txt:
            txt = txt.replace(IMPORT_ANCHOR, IMPORT_ANCHOR + "\n" + IMPORT_LINE, 1)
        else:
            return 2

    # add alpha_mode compute right after core_context emit
    if 'kind="alpha_mode"' not in txt and "kind='alpha_mode'" not in txt:
        anchor = 'kind="core_context"'
        idx = txt.find(anchor)
        if idx < 0:
            return 3
        # insert after the second emit line after core_context payload
        # easiest: insert after the next occurrence of "meta.emit(ev); announce.emit(ev)" following core_context
        idx_emit = txt.find("meta.emit(ev); announce.emit(ev)", idx)
        if idx_emit < 0:
            return 4
        line_end = txt.find("\n", idx_emit)
        if line_end < 0:
            return 5

        block = """
        # Alpha mode decision (policy layer)
        try:
            _reg = rr.regime
        except Exception:
            _reg = "UNKNOWN"
        _adm = decide_alpha_mode(
            regime=str(_reg),
            bias=str(getattr(cc, "bias", "NEUTRAL")),
            trend_strength=float(getattr(cc, "trend_strength", 0.0)),
        )
        dec = _adm
        ev = make_event(level="INFO", kind="alpha_mode", payload={
            "mode": dec.mode,
            "cap_ratio": dec.cap_ratio,
            "reason": dec.reason,
        })
        meta.emit(ev); announce.emit(ev)
"""
        txt = txt[:line_end+1] + block + txt[line_end+1:]

    # enforce in shadow section: look for line "if shadow_enabled and (shadow_writer is not None) ..."
    # We'll inject a guard for alpha strategies before building plan.
    needle = "# Shadow plan + gate"
    idx2 = txt.find(needle)
    if idx2 < 0:
        P.write_text(txt, encoding="utf-8")
        return 0

    # Only inject once
    if "regime_alpha_off" not in txt:
        inject = """
                    # Alpha mode enforcement (policy)
                    if bool(is_alpha):
                        try:
                            _mode = str(getattr(locals().get("dec", None), "mode", "ON")).upper()
                            _cap = float(getattr(locals().get("dec", None), "cap_ratio", 1.0))
                            if _mode == "OFF":
                                ev = make_event(level="INFO", kind="signal_skip", payload={"sid": str(sig_payload["sid"]), "reason": "regime_alpha_off"})
                                meta.emit(ev); announce.emit(ev)
                                continue
                        except Exception:
                            pass
"""
        txt = txt.replace(needle, needle + inject, 1)

    P.write_text(txt, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
