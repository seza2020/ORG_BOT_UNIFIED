# File: C:\alpaca-bot\org_bot\tools\patch_base_add_market.py
from __future__ import annotations

from pathlib import Path


BASE = Path(r"C:\alpaca-bot\org_bot\tbot\strategies\base.py")

MARKET_BLOCK = """
@dataclass(frozen=True)
class MarketSnapshot:
    symbol: str
    ts: datetime

    # price / bar (optional)
    open: float | None = None
    high: float | None = None
    low: float | None = None
    close: float | None = None

    # indicators (optional)
    vwap: float | None = None
    ema_fast: float | None = None
    ema_slow: float | None = None

    # session/meta (optional)
    bar_index: int | None = None     # 0..N from session start
    gap_pct: float | None = None
    orb_high: float | None = None
    orb_low: float | None = None
""".lstrip("\n")


def main() -> None:
    txt = BASE.read_text(encoding="utf-8")

    # 1) Add MarketSnapshot dataclass (before SignalContext) if missing
    if "class MarketSnapshot" not in txt:
        needle = "\n@dataclass(frozen=True)\nclass SignalContext:"
        idx = txt.find(needle)
        if idx == -1:
            raise SystemExit("Could not find SignalContext block to insert MarketSnapshot before it.")
        txt = txt[:idx] + "\n\n" + MARKET_BLOCK + txt[idx:]

    # 2) Add `market` field in SignalContext if missing
    if "market:" not in txt:
        lines = txt.splitlines(True)
        out = []
        in_ctx = False
        injected = False
        for ln in lines:
            out.append(ln)
            if ln.startswith("class SignalContext"):
                in_ctx = True
            if in_ctx and (not injected) and ("symbols:" in ln):
                indent = ln[: len(ln) - len(ln.lstrip(" \t"))]
                out.append(f"{indent}market: dict[str, MarketSnapshot] | None = None\n")
                injected = True

        txt = "".join(out)

    BASE.write_text(txt, encoding="utf-8")
    print("PATCHED:", str(BASE))


if __name__ == "__main__":
    main()
