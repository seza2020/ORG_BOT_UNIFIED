# File: tools/patch_alpha_mode_thresholds_env.py
from __future__ import annotations

from pathlib import Path
import re

P = Path(r".\tbot\policy\alpha_mode.py")
MARK = "PATCH_ALPHA_MODE_THRESHOLDS_ENV=1"

def main() -> int:
    txt = P.read_text(encoding="utf-8")
    if MARK in txt:
        return 0

    # Replace decide_alpha_mode body with env-driven thresholds.
    # We match the function header and replace until the next "def " at column 0, or EOF.
    m = re.search(r"(?s)^def\s+decide_alpha_mode\(.*?\):\s*\n", txt, flags=re.M)
    if not m:
        return 2

    start = m.start()
    # find next top-level def after this function
    m2 = re.search(r"(?m)^def\s+\w+\(", txt[m.end():])
    end = (m.end() + m2.start()) if m2 else len(txt)

    repl = """# {mark}
def decide_alpha_mode(*, regime: str, core_context=None):
    \"""
    Decide alpha mode based on regime + core_context.

    Env overrides:
      TBOT_ALPHA_ON_MIN_STRENGTH    (default 0.50)
      TBOT_ALPHA_CAP50_MIN_STRENGTH (default 0.25)
    \"""
    import os

    reg = str(regime or "").upper().strip()

    # default hard blocks
    if reg == "HIGH_VOL":
        return AlphaModeDecision(mode="OFF", cap_ratio=0.0, reason="regime_high_vol")
    if reg == "CHOP":
        return AlphaModeDecision(mode="OFF", cap_ratio=0.0, reason="regime_chop")

    # TREND or unknown => strength-based
    try:
        on_min = float(os.getenv("TBOT_ALPHA_ON_MIN_STRENGTH", "0.50"))
    except Exception:
        on_min = 0.50
    try:
        cap_min = float(os.getenv("TBOT_ALPHA_CAP50_MIN_STRENGTH", "0.25"))
    except Exception:
        cap_min = 0.25

    s = 0.0
    try:
        s = float(getattr(core_context, "trend_strength", 0.0) or 0.0)
    except Exception:
        s = 0.0

    if s >= on_min:
        return AlphaModeDecision(mode="ON", cap_ratio=1.0, reason="alpha_on_strength")
    if s >= cap_min:
        return AlphaModeDecision(mode="CAP50", cap_ratio=0.5, reason="alpha_cap50_strength")
    return AlphaModeDecision(mode="OFF", cap_ratio=0.0, reason="alpha_off_trend_weak")
""".format(mark=MARK)

    txt2 = txt[:start] + repl + txt[end:]
    P.write_text(txt2, encoding="utf-8")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
