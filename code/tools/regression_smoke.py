import subprocess, sys, os, pathlib, re, json

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
LOG_DIR = ROOT / "logs"
ANN = LOG_DIR / "announce.log"
SHADOW = LOG_DIR / "shadow_plans.jsonl"

def run_case(name: str, extra_args: list[str]) -> tuple[int,str]:
    # clean logs
    for p in [ANN, SHADOW, LOG_DIR / "meta.jsonl"]:
        try:
            p.unlink()
        except FileNotFoundError:
            pass

    cmd = [sys.executable, "-m", "tbot.main", "--run", "--iters", "1", "--sleep", "0.01",
           "--shadow",
           "--risk_usd", "250", "--max_qty", "5000",
           "--shadow_entry", "100", "--shadow_stop", "99", "--shadow_tp", "102",
           "--gate_min_rr", "1.0", "--gate_min_conf", "0.90",
           "--gate_cooldown_sec", "0", "--gate_max_plans_per_day", "999", "--gate_max_risk_usd", "999999",
           "--sim_in_session", "1", "--sim_pre_close", "1",
           "--force_signal", "S11", "--force_signal_repeat", "1", "--force_signal_ignore_session", "0"
          ] + extra_args

    p = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    out = (p.stdout or "") + "\n" + (p.stderr or "")
    return p.returncode, out

def count_in_file(path: pathlib.Path, pattern: str) -> int:
    if not path.exists():
        return 0
    rx = re.compile(pattern)
    c = 0
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if rx.search(line):
            c += 1
    return c

def main():
    results = []

    # CASE A: pre_close=True and ignore_pre_close=0 => NO FIRE/NO SHADOW
    rc_a, out_a = run_case("A_no_ignore", ["--force_signal_ignore_pre_close", "0"])
    fire_a = count_in_file(ANN, r"\bsignal_fire\b")
    acc_a  = count_in_file(ANN, r"\bshadow_accept\b")
    shc_a  = SHADOW.read_text(encoding="utf-8", errors="replace").count("\n") if SHADOW.exists() else 0

    pass_a = (rc_a == 0) and (fire_a == 0) and (acc_a == 0) and (shc_a == 0)
    results.append(("A_no_ignore", pass_a, {"rc": rc_a, "fire": fire_a, "accept": acc_a, "shadow_count": shc_a}))

    # CASE B: pre_close=True and ignore_pre_close=1 => MUST FIRE + ACCEPT + SHADOW_COUNT>=1
    rc_b, out_b = run_case("B_ignore", ["--force_signal_ignore_pre_close", "1"])
    fire_b = count_in_file(ANN, r"\bsignal_fire\b")
    acc_b  = count_in_file(ANN, r"\bshadow_accept\b")
    shc_b  = SHADOW.read_text(encoding="utf-8", errors="replace").count("\n") if SHADOW.exists() else 0

    pass_b = (rc_b == 0) and (fire_b >= 1) and (acc_b >= 1) and (shc_b >= 1)
    results.append(("B_ignore", pass_b, {"rc": rc_b, "fire": fire_b, "accept": acc_b, "shadow_count": shc_b}))

    # Print summary
    print("==== REGRESSION_SMOKE ====")
    all_ok = True
    for name, ok, meta in results:
        print(f"{name}: {'PASS' if ok else 'FAIL'}  {json.dumps(meta)}")
        if not ok:
            all_ok = False

    # If fail, show last announce snippet to debug quickly
    if not all_ok and ANN.exists():
        tail = ANN.read_text(encoding="utf-8", errors="replace").splitlines()[-50:]
        print("---- ANNOUNCE_TAIL ----")
        for ln in tail:
            print(ln)

    raise SystemExit(0 if all_ok else 2)

if __name__ == "__main__":
    main()
