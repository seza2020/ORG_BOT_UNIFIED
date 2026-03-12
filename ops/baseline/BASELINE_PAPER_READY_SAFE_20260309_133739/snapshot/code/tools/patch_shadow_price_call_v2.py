from __future__ import annotations
from pathlib import Path

P = Path(r"tbot\runtime\orchestrator.py")

MARK = "# SHADOW_PRICE_CALL (auto v2)"

INJECT = """\
                    # SHADOW_PRICE_CALL (auto v2)
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
    if MARK in s:
        print("SKIP: already patched")
        return 0

    # Ensure import exists (idempotent best-effort)
    if "from tbot.runtime.shadow_pricing import compute_shadow_prices" not in s:
        s = s.replace(
            "from tbot.runtime.shadow_gate import GateConfig, ShadowGate",
            "from tbot.runtime.shadow_gate import GateConfig, ShadowGate\nfrom tbot.runtime.shadow_pricing import compute_shadow_prices",
        )

    needle = "if shadow_enabled and (shadow_writer is not None) and (gate is not None) and (sig_payload is not None):"
    i = s.find(needle)
    if i < 0:
        print("FAIL: shadow_enabled anchor not found")
        return 2

    # insert right after that line
    eol = s.find("\n", i)
    if eol < 0:
        print("FAIL: no newline after anchor")
        return 3

    s = s[: eol + 1] + INJECT + s[eol + 1 :]

    # Rewire entry/stop/tp to use prices
    s = s.replace("entry=float(shadow_entry),", "entry=float(prices.entry),")
    s = s.replace("stop=float(shadow_stop),", "stop=float(prices.stop),")
    s = s.replace("tp=float(shadow_tp),", "tp=float(prices.tp),")

    P.write_text(s, encoding="utf-8")
    print("DONE: inserted pricing block after shadow_enabled anchor")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
