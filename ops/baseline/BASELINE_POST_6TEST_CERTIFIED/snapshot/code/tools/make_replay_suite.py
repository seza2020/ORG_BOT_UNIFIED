# File: tools/make_replay_suite.py
from __future__ import annotations

import csv
from pathlib import Path
import random


SYMS = ["SPY", "QQQ", "IWM", "NVDA", "AAPL"]


def _emit(rows, sym, last, vwap, ef, es):
    rows.append({
        "symbol": sym,
        "last": f"{last:.2f}",
        "vwap": f"{vwap:.2f}",
        "ema_fast": f"{ef:.2f}",
        "ema_slow": f"{es:.2f}",
    })


def make_suite(path: Path, mode: str, steps_per_sym: int = 1200, seed: int = 7) -> None:
    """
    Deterministic synthetic suite with multiple regimes.
    - trend: last steadily rises, ef>es, last>=vwap often
    - chop: last oscillates around vwap, ef~es
    - spike: occasional large jumps, ef/es diverge, last-vwap swings
    """
    rnd = random.Random(seed)
    rows = []

    # base prices per symbol (distinct)
    base = {"SPY": 100.0, "QQQ": 200.0, "IWM": 150.0, "NVDA": 450.0, "AAPL": 180.0}

    # state per symbol
    st = {s: {"last": base[s], "ef": base[s], "es": base[s], "vwap": base[s]} for s in SYMS}

    for i in range(steps_per_sym):
        for sym in SYMS:
            s = st[sym]
            last = s["last"]
            ef = s["ef"]
            es = s["es"]
            vwap = s["vwap"]

            if mode == "trend":
                drift = 0.05 + rnd.random() * 0.05
                noise = (rnd.random() - 0.5) * 0.03
                last = last + drift + noise
                vwap = vwap + drift * 0.8 + noise * 0.2
                # EMAs: fast follows more
                ef = ef + (last - ef) * 0.25
                es = es + (last - es) * 0.10

            elif mode == "chop":
                # oscillate around vwap
                osc = (rnd.random() - 0.5) * 0.40
                last = vwap + osc
                # vwap slowly wanders
                vwap = vwap + (rnd.random() - 0.5) * 0.05
                ef = ef + (last - ef) * 0.20
                es = es + (last - es) * 0.18

            elif mode == "spike":
                # mostly chop, occasional spikes
                osc = (rnd.random() - 0.5) * 0.50
                last = vwap + osc
                vwap = vwap + (rnd.random() - 0.5) * 0.05

                if rnd.random() < 0.03:
                    spike = (1.0 + rnd.random() * 3.0) * (1 if rnd.random() > 0.5 else -1)
                    last = last + spike
                    vwap = vwap + spike * 0.2

                ef = ef + (last - ef) * 0.30
                es = es + (last - es) * 0.12

            else:
                raise ValueError("unknown mode")

            s["last"], s["ef"], s["es"], s["vwap"] = last, ef, es, vwap
            _emit(rows, sym, last, vwap, ef, es)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["symbol","last","vwap","ema_fast","ema_slow"])
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    out1 = Path(r".\replay\replay_suite_01_trend.csv")
    out2 = Path(r".\replay\replay_suite_02_chop.csv")
    out3 = Path(r".\replay\replay_suite_03_spike.csv")

    make_suite(out1, "trend", steps_per_sym=1200, seed=7)
    make_suite(out2, "chop",  steps_per_sym=1200, seed=11)
    make_suite(out3, "spike", steps_per_sym=1200, seed=19)

    print(f"WROTE {out1}")
    print(f"WROTE {out2}")
    print(f"WROTE {out3}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
