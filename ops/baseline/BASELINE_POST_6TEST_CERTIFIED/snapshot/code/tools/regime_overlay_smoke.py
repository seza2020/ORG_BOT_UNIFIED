# File: tools/regime_overlay_smoke.py
from __future__ import annotations

import os
import sys
import json
import subprocess


def _run(cmd: list[str], env: dict[str, str]) -> tuple[int, str]:
    p = subprocess.run(cmd, env=env, cwd=r"C:\alpaca-bot\org_bot", capture_output=True, text=True)
    out = (p.stdout or "") + "\n" + (p.stderr or "")
    return p.returncode, out


def _base_env() -> dict[str, str]:
    env = dict(os.environ)
    env["TBOT_REGIME_ENABLE"] = "1"
    # keep everything enabled; caps high so regime is the only driver
    env["TBOT_STRATEGY_POLICY_JSON"] = json.dumps({
        "S01": {"enabled": True, "weight": 1.0, "min_conf": 0.0, "max_fires_per_day": 10000, "max_accepts_per_day": 10000, "cooldown_sec": 0},
        "S11": {"enabled": True, "weight": 1.0, "min_conf": 0.0, "max_fires_per_day": 10000, "max_accepts_per_day": 10000, "cooldown_sec": 0},
        "S12": {"enabled": False},
        "S08": {"enabled": False},
    })
    return env


def main() -> int:
    cmd = [
        sys.executable, "-m", "tbot.main",
        "--run",
        "--iters", "1",
        "--sleep", "0.01",
        "--shadow",
        "--shadow_path", r".\logs\shadow_plans.jsonl",
        "--force_signal", "S11",
        "--force_signal_repeat", "1",
        "--force_signal_ignore_session", "1",
        "--force_signal_ignore_pre_close", "1",
        "--sim_daily_r", "0",
        "--sim_week_r", "0",
    ]

    # 1) HIGH_VOL -> alpha OFF -> expect signal_skip reason regime_alpha_off
    env1 = _base_env()
    env1["TBOT_REGIME_FORCE"] = "HIGH_VOL"
    rc1, out1 = _run(cmd, env1)
    if rc1 != 0:
        print("FAIL: runner rc != 0 (HIGH_VOL)")
        print(out1)
        return 2
    if "regime_alpha_off" not in out1:
        print("FAIL: expected regime_alpha_off (HIGH_VOL)")
        print(out1)
        return 3

    # 2) CHOP -> alpha CAP50 -> expect forced S11 fire with confidence ~0.495 (0.99*0.5)
    env2 = _base_env()
    env2["TBOT_REGIME_FORCE"] = "CHOP"
    rc2, out2 = _run(cmd, env2)
    if rc2 != 0:
        print("FAIL: runner rc != 0 (CHOP)")
        print(out2)
        return 4
    # Look for confidence 0.495 in emitted payload/logs
    if "confidence': 0.495" not in out2 and '"confidence": 0.495' not in out2:
        print("FAIL: expected CAP50 confidence 0.495 (CHOP)")
        print(out2)
        return 5

    print("PASS", {"rc": 0})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
