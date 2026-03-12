from __future__ import annotations
from pathlib import Path

P = Path(r"tbot\runtime\orchestrator.py")

MARK = "# SHADOW_PRICE_CALL (auto)"

BLOCK = """\
                    # SHADOW_PRICE_CALL (auto)
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
        print("SKIP: price call already present")
        return 0

    needle = "plan = build_shadow_plan("
    i = s.find(needle)
    if i < 0:
        print("FAIL: build_shadow_plan anchor not found")
        return 2

    # Determine indent by looking backward to the start of the line
    line_start = s.rfind("\n", 0, i) + 1
    indent = ""
    j = line_start
    while j < len(s) and s[j] in (" ", "\t"):
        indent += s[j]
        j += 1

    # Our block already uses 20 spaces style; adjust by prefixing indent to each line
    adj = "\n".join((indent + ln if ln.strip() else ln) for ln in BLOCK.splitlines()) + "\n"

    s = s[:line_start] + adj + s[line_start:]

    # Now replace entry/stop/tp args to use prices.*
    s = s.replace("entry=float(shadow_entry),", "entry=float(prices.entry),")
    s = s.replace("stop=float(shadow_stop),", "stop=float(prices.stop),")
    s = s.replace("tp=float(shadow_tp),", "tp=float(prices.tp),")

    P.write_text(s, encoding="utf-8")
    print("DONE: inserted price call + rewired entry/stop/tp")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
