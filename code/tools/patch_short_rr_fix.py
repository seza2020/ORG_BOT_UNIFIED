from __future__ import annotations
from pathlib import Path
import re

P = Path(r".\tbot\runtime\orchestrator.py")

def main():
    s = P.read_text(encoding="utf-8")

    # Guard: only patch once
    if "TBOT_SHORT_FLIP_TP_STOP" in s:
        print("SKIP: already patched")
        return 0

    # We patch just before build_shadow_plan(...) call inside shadow plan section.
    # Replace the build_shadow_plan(...) call header to inject side-aware entry/stop/tp.
    pat = r"(?m)^\s*plan\s*=\s*build_shadow_plan\(\s*$"
    m = re.search(pat, s)
    if not m:
        print("PATCH_FAIL: could not find 'plan = build_shadow_plan(' line")
        return 2

    inject = r"""
                    # TBOT_SHORT_FLIP_TP_STOP: ensure stop/tp are consistent with side
                    _entry_eff = float(shadow_entry)
                    _stop_eff = float(shadow_stop)
                    _tp_eff = float(shadow_tp)
                    try:
                        _side = str(sig_payload.get("side","")).upper()
                        if _side == "SHORT":
                            # interpret provided (entry,stop,tp) as LONG-template distances
                            _stop_dist = abs(_entry_eff - _stop_eff)
                            _tp_dist = abs(_tp_eff - _entry_eff)
                            _stop_eff = _entry_eff + _stop_dist
                            _tp_eff = _entry_eff - _tp_dist
                    except Exception:
                        pass

                    plan = build_shadow_plan(
""".lstrip("\n")

    s2 = re.sub(pat, inject, s, count=1)
    if s2 == s:
        print("PATCH_FAIL: substitution did not change file")
        return 3

    # Also ensure build_shadow_plan args use _entry_eff/_stop_eff/_tp_eff
    s2 = s2.replace("entry=float(shadow_entry),", "entry=float(_entry_eff),")
    s2 = s2.replace("stop=float(shadow_stop),", "stop=float(_stop_eff),")
    s2 = s2.replace("tp=float(shadow_tp),", "tp=float(_tp_eff),")

    P.write_text(s2, encoding="utf-8")
    print("PATCH_OK")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
