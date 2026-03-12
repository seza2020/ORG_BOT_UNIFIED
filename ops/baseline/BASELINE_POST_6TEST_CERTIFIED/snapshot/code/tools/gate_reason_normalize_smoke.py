import os, sys, re, ast, json, subprocess

ROOT = os.path.abspath(os.getcwd())
LOG_DIR = os.path.join(ROOT, "logs")
ANN = os.path.join(LOG_DIR, "announce.log")
META = os.path.join(LOG_DIR, "meta.jsonl")
SHADOW = os.path.join(LOG_DIR, "shadow_plans.jsonl")

def rm_logs():
    for p in (ANN, META, SHADOW):
        try:
            os.remove(p)
        except FileNotFoundError:
            pass

def tail(path, n=60):
    if not os.path.exists(path):
        return ""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    return "".join(lines[-n:])

def _extract_payload(line: str):
    # line example:
    # WARN | ... | shadow_reject {'sid': 'S11', ... 'reasons': ['rr_below_min']}
    m = re.search(r"\|\s*(shadow_reject|shadow_accept)\s*(\{.*\})\s*$", line.strip())
    if not m:
        return None, None
    kind = m.group(1)
    payload_txt = m.group(2)
    try:
        payload = ast.literal_eval(payload_txt)
    except Exception:
        payload = None
    return kind, payload

def last_event(kind_wanted: str):
    if not os.path.exists(ANN):
        return None
    with open(ANN, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    for line in reversed(lines):
        if f"| {kind_wanted} " in line:
            k, payload = _extract_payload(line)
            if k == kind_wanted:
                return payload
    return None

def run_case(name, gate_min_rr=1.0, gate_min_conf=0.90, gate_max_risk_usd=999999.0, gate_max_plans_per_day=999, gate_cooldown_sec=0, expect_reason=None, expect_accept=False):
    rm_logs()

    cmd = [
        sys.executable, "-m", "tbot.main",
        "--run",
        "--iters", "1",
        "--sleep", "0.01",

        # IMPORTANT: these expect a value in your CLI
        "--sim_in_session", "1",
        "--sim_pre_close", "0",

        "--force_signal", "S11",
        "--force_signal_repeat", "1",
        "--force_signal_ignore_session", "0",
        "--force_signal_ignore_pre_close", "1",

        "--shadow",
        "--risk_usd", "250",
        "--max_qty", "5000",
        "--shadow_entry", "100",
        "--shadow_stop", "99",
        "--shadow_tp", "102",

        "--gate_min_rr", str(gate_min_rr),
        "--gate_min_conf", str(gate_min_conf),
        "--gate_cooldown_sec", str(gate_cooldown_sec),
        "--gate_max_plans_per_day", str(gate_max_plans_per_day),
        "--gate_max_risk_usd", str(gate_max_risk_usd),
    ]

    p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    # Even if p.returncode==0, we validate log evidence.
    rej = last_event("shadow_reject")
    acc = last_event("shadow_accept")

    if expect_accept:
        if acc is None:
            return 1, f"{name}: no accept\n---- ANN_TAIL ----\n{tail(ANN)}"
        # accept should have no reasons key, or empty list
        reasons = acc.get("reasons", [])
        if reasons not in ([], None):
            return 1, f"{name}: accept has reasons={reasons}\n---- PAYLOAD ----\n{json.dumps(acc, indent=2)}"
        return 0, "ok"

    # expecting reject with exactly one normalized reason
    if rej is None:
        return 1, f"{name}: no shadow_reject found\n---- STDERR ----\n{p.stderr}\n---- ANN_TAIL ----\n{tail(ANN)}"

    reasons = rej.get("reasons", None)
    if reasons != [expect_reason]:
        return 1, f"{name}: reasons mismatch. got={reasons} expect={[expect_reason]}\n---- PAYLOAD ----\n{json.dumps(rej, indent=2)}"
    return 0, json.dumps({"reasons": reasons})

def main():
    print("==== GATE_REASON_NORMALIZE_SMOKE (FIXED) ====")

    tests = [
        ("A_rr_below_min", dict(gate_min_rr=3.0, expect_reason="rr_below_min")),
        ("B_conf_below_min", dict(gate_min_conf=0.995, expect_reason="confidence_below_min")),
        ("C_risk_above_max", dict(gate_max_risk_usd=100.0, expect_reason="risk_above_max")),
        ("D_plan_cap", dict(gate_max_plans_per_day=0, expect_reason="daily_plan_cap_reached")),
        ("E_accept_has_no_reasons", dict(expect_accept=True)),
    ]

    all_ok = True
    for name, kw in tests:
        rc, detail = run_case(name, **kw)
        if rc == 0:
            print(f"{name}: PASS  {{\"rc\": 0, \"detail\": {json.dumps(detail)} }}")
        else:
            all_ok = False
            print(f"{name}: FAIL  {{\"rc\": 1, \"detail\": {json.dumps(detail)} }}")

    raise SystemExit(0 if all_ok else 1)

if __name__ == "__main__":
    main()
