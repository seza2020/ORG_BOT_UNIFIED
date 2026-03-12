# File: tools/s11_mvp_diag_smoke.py
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")

def run(cmd):
    p = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

def load_events(meta_path: Path):
    out = []
    with meta_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out

def main() -> int:
    # Force env for this smoke
    env = os.environ.copy()
    env["TBOT_ENABLE_S11_MVP"] = "1"
    env["TBOT_MARKET_MODE"] = "replay"
    env["TBOT_REPLAY_CSV"] = r".\replay\replay_suite_01_trend.csv"

    # run a short shadow run into default logs/meta.jsonl
    cmd = [
        sys.executable, "-m", "tbot.main", "--run",
        "--iters", "120",
        "--sleep", "0.01",
        "--shadow",
        "--shadow_path", r".\logs\shadow_plans.jsonl",
        "--sim_in_session", "1",
        "--sim_pre_close", "0",
    ]
    p = subprocess.run(cmd, cwd=str(ROOT), env=env, capture_output=True, text=True)
    if p.returncode != 0:
        print("FAIL: run rc=", p.returncode)
        print(p.stdout)
        print(p.stderr)
        return 2

    meta = ROOT / "logs" / "meta.jsonl"
    if not meta.exists():
        print("FAIL: meta missing")
        return 3

    evs = load_events(meta)

    cc = [e for e in evs if e.get("kind") == "core_context"]
    am = [e for e in evs if e.get("kind") == "alpha_mode"]
    fires = [e for e in evs if e.get("kind") == "signal_fire"]

    long_bias = 0
    strong = 0
    for e in cc:
        pld = e.get("payload") or {}
        if str(pld.get("bias", "")).upper() == "LONG":
            long_bias += 1
        try:
            if float(pld.get("trend_strength", 0.0)) >= 0.60:
                strong += 1
        except Exception:
            pass

    on_mode = 0
    cap_mode = 0
    off_mode = 0
    for e in am:
        pld = e.get("payload") or {}
        m = str(pld.get("mode", "")).upper()
        if m == "ON":
            on_mode += 1
        elif m == "CAP50":
            cap_mode += 1
        elif m == "OFF":
            off_mode += 1

    print("PASS_DIAG", {
        "core_context": len(cc),
        "alpha_mode": len(am),
        "signal_fire": len(fires),
        "core_bias_long": long_bias,
        "core_strength_ge_0.60": strong,
        "alpha_mode_on": on_mode,
        "alpha_mode_cap50": cap_mode,
        "alpha_mode_off": off_mode,
    })

    # This smoke only checks that we have at least some LONG+strong+ON in TREND suite.
    # If not, S11 MVP will never fire by design.
    if long_bias == 0 or strong == 0 or (on_mode + cap_mode) == 0:
        print("FAIL: gating conditions never satisfied")
        return 4

    return 0

if __name__ == "__main__":
    raise SystemExit(main())
