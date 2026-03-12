from __future__ import annotations

from pathlib import Path
import json
import os
import re
import subprocess
import sys

ROOT = Path(r"C:\alpaca-bot\org_bot")
TOOLS = ROOT / "tools"
LOGS = ROOT / "logs"

TARGET = TOOLS / "kill_switch_smoke.py"

FILE_TEXT = r'''from __future__ import annotations

from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(r"C:\alpaca-bot\org_bot")
LOGS = ROOT / "logs"
ANN = LOGS / "announce.log"
SHADOW = LOGS / "shadow_plans.jsonl"
META = LOGS / "meta.jsonl"

def _rm(p: Path) -> None:
    try:
        if p.exists():
            p.unlink()
    except Exception:
        pass

def clean_logs() -> None:
    _rm(ANN)
    _rm(SHADOW)
    _rm(META)

def count_in_file(path: Path, pattern: str) -> int:
    if not path.exists():
        return 0
    rx = re.compile(pattern)
    n = 0
    with path.open("r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if rx.search(line):
                n += 1
    return n

def tail(path: Path, n: int = 80) -> str:
    if not path.exists():
        return ""
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        return "\n".join(lines[-n:])
    except Exception:
        return ""

def run_cmd(extra_args: list[str]) -> tuple[int, str]:
    # Force deterministic "in_session" so the smoke doesn't depend on wall-clock time.
    cmd = [
        sys.executable, "-m", "tbot.main",
        "--run", "--iters", "1", "--sleep", "0.01",
        "--shadow",
        "--risk_usd", "250",
        "--max_qty", "5000",
        "--force_signal", "S11",
        "--sim_in_session", "1",
        "--sim_pre_close", "0",
        "--gate_min_rr", "1.0",
        "--gate_min_conf", "0.9",
        "--gate_cooldown_sec", "0",
        "--gate_max_plans_per_day", "999",
        "--gate_max_risk_usd", "999999",
    ] + extra_args

    p = subprocess.run(cmd, capture_output=True, text=True)
    out = (p.stdout or "") + ("\n" if (p.stdout and p.stderr) else "") + (p.stderr or "")
    return p.returncode, out

def rc_ok(rc: int, out: str) -> bool:
    # Allow rc=0 or rc=1 in kill-block scenarios, but FAIL on real crashes/argparse issues.
    if rc == 2:
        return False
    if rc not in (0, 1):
        return False
    bad = (
        ("Traceback (most recent call last):" in out) or
        ("SyntaxError:" in out) or
        ("IndentationError:" in out)
    )
    return not bad

def main() -> int:
    print("==== KILL_SWITCH_SMOKE ====")

    # -------------------------
    # W) Weekly portfolio kill should block forced signal
    # -------------------------
    clean_logs()
    rc_w, out_w = run_cmd(["--sim_week_r", "-5.5"])

    fire_w = count_in_file(ANN, r"\\bsignal_fire\\b")
    acc_w  = count_in_file(ANN, r"\\bshadow_accept\\b")
    sh_w   = SHADOW.read_text(encoding="utf-8", errors="ignore").count("\n") + (1 if SHADOW.exists() and SHADOW.stat().st_size > 0 else 0) if SHADOW.exists() else 0
    pkc_w  = count_in_file(ANN, r"\\bportfolio_kill_change\\b")

    pass_w = rc_ok(rc_w, out_w) and (pkc_w >= 1) and (fire_w == 0) and (acc_w == 0) and (sh_w == 0)

    print("W_weekly_kill_blocks_force: " + ("PASS  " if pass_w else "FAIL  ") + json.dumps({
        "rc": rc_w,
        "fire": fire_w,
        "accept": acc_w,
        "shadow_count": sh_w,
        "portfolio_kill_change": pkc_w,
    }))

    # -------------------------
    # A) Daily alpha kill should block S11 forced signal
    # -------------------------
    clean_logs()
    rc_a, out_a = run_cmd(["--sim_daily_r", "-2.1"])

    fire_a = count_in_file(ANN, r"\\bsignal_fire\\b")
    acc_a  = count_in_file(ANN, r"\\bshadow_accept\\b")
    sh_a   = SHADOW.read_text(encoding="utf-8", errors="ignore").count("\n") + (1 if SHADOW.exists() and SHADOW.stat().st_size > 0 else 0) if SHADOW.exists() else 0
    akc_a  = count_in_file(ANN, r"\\balpha_kill_change\\b")

    pass_a = rc_ok(rc_a, out_a) and (akc_a >= 1) and (fire_a == 0) and (acc_a == 0) and (sh_a == 0)

    print("A_alpha_kill_blocks_S11_force: " + ("PASS  " if pass_a else "FAIL  ") + json.dumps({
        "rc": rc_a,
        "fire": fire_a,
        "accept": acc_a,
        "shadow_count": sh_a,
        "alpha_kill_change": akc_a,
    }))

    if pass_w and pass_a:
        return 0

    print("---- DEBUG ----")
    print("[W_tail]")
    print(tail(ANN))
    print()
    print("[A_tail]")
    print(tail(ANN))
    print()
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
'''

def main() -> int:
    TARGET.write_text(FILE_TEXT, encoding="utf-8", newline="\n")
    print("REWROTE:", str(TARGET))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
