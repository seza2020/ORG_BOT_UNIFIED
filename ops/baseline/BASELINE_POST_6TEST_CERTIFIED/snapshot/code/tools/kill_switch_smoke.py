from __future__ import annotations

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

def tail(path: Path, n: int = 120) -> str:
    if not path.exists():
        return ""
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        return "\n".join(lines[-n:])
    except Exception:
        return ""

def shadow_line_count() -> int:
    if not SHADOW.exists():
        return 0
    try:
        return sum(1 for ln in SHADOW.read_text(encoding="utf-8", errors="ignore").splitlines() if ln.strip())
    except Exception:
        return 0

def run_cmd(extra_args: list[str]) -> tuple[int, str]:
    # Deterministic: do not depend on wall-clock session checks
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
    # rc=2 is argparse/bad args => fail
    if rc == 2:
        return False
    # allow rc=0 or rc=1 if there is no crash; some runners still exit(1) on normal shutdown
    if rc not in (0, 1):
        return False
    bad = (
        ("Traceback (most recent call last):" in out)
        or ("SyntaxError:" in out)
        or ("IndentationError:" in out)
        or ("tbot: error: unrecognized arguments" in out)
    )
    return not bad

def main() -> int:
    print("==== KILL_SWITCH_SMOKE ====")

    results = []
    debug = {}

    # -------------------------
    # W) Weekly portfolio kill should block forced signal
    # -------------------------
    clean_logs()
    rc_w, out_w = run_cmd(["--sim_week_r", "-5.5"])

    fire_w = count_in_file(ANN, r"\bsignal_fire\b")
    acc_w  = count_in_file(ANN, r"\bshadow_accept\b")
    sh_w   = shadow_line_count()

    pkc_w_ann  = count_in_file(ANN,  r"\bportfolio_kill_change\b")
    pkc_w_meta = count_in_file(META, r'"kind"\s*:\s*"portfolio_kill_change"')
    pkc_w = max(pkc_w_ann, pkc_w_meta)

    pass_w = rc_ok(rc_w, out_w) and (pkc_w >= 1) and (fire_w == 0) and (acc_w == 0) and (sh_w == 0)
    results.append(("W_weekly_kill_blocks_force", pass_w, {
        "rc": rc_w, "fire": fire_w, "accept": acc_w, "shadow_count": sh_w, "portfolio_kill_change": pkc_w
    }))
    debug["W"] = {
        "stdout_tail": "\n".join(out_w.splitlines()[-80:]),
        "announce_tail": tail(ANN),
        "meta_tail": "\n".join(META.read_text(encoding="utf-8", errors="ignore").splitlines()[-40:]) if META.exists() else ""
    }

    # -------------------------
    # A) Daily alpha kill should block S11 forced signal
    # -------------------------
    clean_logs()
    rc_a, out_a = run_cmd(["--sim_daily_r", "-2.1"])

    fire_a = count_in_file(ANN, r"\bsignal_fire\b")
    acc_a  = count_in_file(ANN, r"\bshadow_accept\b")
    sh_a   = shadow_line_count()

    akc_a_ann  = count_in_file(ANN,  r"\balpha_kill_change\b")
    akc_a_meta = count_in_file(META, r'"kind"\s*:\s*"alpha_kill_change"')
    akc_a = max(akc_a_ann, akc_a_meta)

    pass_a = rc_ok(rc_a, out_a) and (akc_a >= 1) and (fire_a == 0) and (acc_a == 0) and (sh_a == 0)
    results.append(("A_alpha_kill_blocks_S11_force", pass_a, {
        "rc": rc_a, "fire": fire_a, "accept": acc_a, "shadow_count": sh_a, "alpha_kill_change": akc_a
    }))
    debug["A"] = {
        "stdout_tail": "\n".join(out_a.splitlines()[-80:]),
        "announce_tail": tail(ANN),
        "meta_tail": "\n".join(META.read_text(encoding="utf-8", errors="ignore").splitlines()[-40:]) if META.exists() else ""
    }

    all_ok = True
    for name, ok, meta in results:
        print(f"{name}: " + ("PASS  " if ok else "FAIL  ") + json.dumps(meta))
        all_ok = all_ok and ok

    if all_ok:
        return 0

    print("---- DEBUG ----")
    print("[W_stdout_tail]");  print(debug["W"]["stdout_tail"]);  print()
    print("[W_announce_tail]");print(debug["W"]["announce_tail"]);print()
    print("[W_meta_tail]");    print(debug["W"]["meta_tail"]);    print()
    print("[A_stdout_tail]");  print(debug["A"]["stdout_tail"]);  print()
    print("[A_announce_tail]");print(debug["A"]["announce_tail"]);print()
    print("[A_meta_tail]");    print(debug["A"]["meta_tail"]);    print()
    return 2

if __name__ == "__main__":
    raise SystemExit(main())
