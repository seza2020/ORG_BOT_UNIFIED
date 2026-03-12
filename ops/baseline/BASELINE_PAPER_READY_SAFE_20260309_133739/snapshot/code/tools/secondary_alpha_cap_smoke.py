# File: tools/secondary_alpha_cap_smoke.py
from __future__ import annotations

import os
import sys
import json
import subprocess


def _run(cmd: list[str], env: dict[str, str]) -> tuple[int, str]:
    p = subprocess.run(cmd, env=env, capture_output=True, text=True)
    out = (p.stdout or "") + "\n" + (p.stderr or "")
    return p.returncode, out


def main() -> int:
    # Force secondary alpha S12 by default (can swap to S08 later if desired).
    secondary_sid = os.getenv("TBOT_SMOKE_SECONDARY_SID", "S12").strip() or "S12"

    env = dict(os.environ)

    env["TBOT_ALPHA_SECONDARY_SID"] = secondary_sid

    # Hard cap: only 1 fire per day for secondary alpha.
    policy = {
        "S01": {"enabled": True, "weight": 1.0, "min_conf": 0.0, "max_fires_per_day": 10000, "max_accepts_per_day": 10000, "cooldown_sec": 0},
        "S11": {"enabled": True, "weight": 1.0, "min_conf": 0.0, "max_fires_per_day": 10000, "max_accepts_per_day": 10000, "cooldown_sec": 0},
        secondary_sid: {"enabled": True, "weight": 1.0, "min_conf": 0.0, "max_fires_per_day": 1, "max_accepts_per_day": 1, "cooldown_sec": 999999},
    }
    # Disable the other secondary (best-effort).
    other = "S08" if secondary_sid.upper() == "S12" else "S12"
    policy[other] = {"enabled": False}

    env["TBOT_STRATEGY_POLICY_JSON"] = json.dumps(policy)

    cmd = [
        sys.executable, "-m", "tbot.main",
        "--run",
        "--iters", "3",
        "--sleep", "0.01",
        "--shadow",
        "--shadow_path", r".\logs\shadow_plans.jsonl",
        "--force_signal", secondary_sid,
        "--force_signal_repeat", "3",
        "--force_signal_ignore_session", "1",
        "--force_signal_ignore_pre_close", "1",
        "--sim_daily_r", "0",
        "--sim_week_r", "0",
    ]

    rc, out = _run(cmd, env=env)

    if rc != 0:
        print("FAIL: runner rc != 0")
        print(out)
        return 2

    # Expect at least one cap skip for the secondary sid.
    # We accept either raw 'policy_fire_cap' or tiered 'policy_fire_cap:secondary'.
    want1 = f"signal_skip {{'sid': '{secondary_sid}', 'reason': 'policy_fire_cap"
    want2 = f"signal_skip {{\"sid\": \"{secondary_sid}\", \"reason\": \"policy_fire_cap"

    if (want1 not in out) and (want2 not in out) and ("policy_fire_cap" not in out):
        print("FAIL: did not detect policy_fire_cap in output")
        print(out)
        return 3

    print("PASS", {"rc": 0, "secondary": secondary_sid})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
