from __future__ import annotations
from pathlib import Path

P = Path(r"tbot\runtime\orchestrator.py")

MARK = "# PRICES_DEFAULT (auto)"

DEFAULT = """\
                    # PRICES_DEFAULT (auto)
                    prices = compute_shadow_prices(
                        sig_payload=sig_payload,
                        market=market,
                        default_entry=float(shadow_entry),
                        default_stop=float(shadow_stop),
                        default_tp=float(shadow_tp),
                    )

"""

def main() -> int:
    s = P.read_text(encoding="utf-8")

    needle = "if shadow_enabled and (shadow_writer is not None) and (gate is not None) and (sig_payload is not None):"
    i = s.find(needle)
    if i < 0:
        print("FAIL: shadow_enabled anchor not found")
        return 2

    eol = s.find("\n", i)
    if eol < 0:
        print("FAIL: no newline after anchor")
        return 3

    # insert default prices right after anchor line if not already there
    block_start = eol + 1
    window = s[block_start : block_start + 800]

    if MARK in window:
        print("SKIP: default prices already present near anchor")
        return 0

    s = s[:block_start] + DEFAULT + s[block_start:]
    P.write_text(s, encoding="utf-8")
    print("DONE: inserted default prices after shadow_enabled anchor")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
