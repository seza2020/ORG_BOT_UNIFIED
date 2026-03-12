from __future__ import annotations

from pathlib import Path

P = Path(r"tbot\runtime\orchestrator.py")

MARK = "# SHADOW_DYNAMIC_PRICE (auto-inserted)"

INJECT = """\
                    # SHADOW_DYNAMIC_PRICE (auto-inserted)
                    # If enabled, derive entry/stop/tp from market last price for more realistic paper/replay evaluation.
                    import os as _os
                    _mode = (_os.getenv("TBOT_SHADOW_PRICE_MODE", "fixed") or "fixed").strip().lower()
                    _rr = float(_os.getenv("TBOT_SHADOW_RR", "2.0") or 2.0)
                    _stop_pct = float(_os.getenv("TBOT_SHADOW_STOP_PCT", "0.003") or 0.003)

                    _entry = float(shadow_entry)
                    _stop = float(shadow_stop)
                    _tp = float(shadow_tp)

                    if _mode == "last":
                        try:
                            _sym = str(sig_payload["symbol"])
                            _snap = market.get(_sym) if market is not None else None
                            _last = getattr(_snap, "last", None) if _snap is not None else None
                            if _last is not None:
                                _entry = float(_last)
                                # stop distance is pct of entry (bounded)
                                _dist = max(0.01, abs(_entry) * _stop_pct)
                                if str(sig_payload.get("side","")).upper() == "SHORT":
                                    _stop = _entry + _dist
                                    _tp = _entry - (_rr * _dist)
                                else:
                                    _stop = _entry - _dist
                                    _tp = _entry + (_rr * _dist)
                        except Exception:
                            pass

"""

def main() -> int:
    s = P.read_text(encoding="utf-8")
    if MARK in s:
        print("SKIP: dynamic price block already present")
        return 0

    needle = "plan = build_shadow_plan("
    idx = s.find(needle)
    if idx < 0:
        print("FAIL: could not find build_shadow_plan anchor")
        return 2

    # insert immediately before plan = build_shadow_plan(
    s2 = s[:idx] + INJECT + s[idx:]
    P.write_text(s2, encoding="utf-8")
    print("DONE: inserted dynamic pricing block")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
