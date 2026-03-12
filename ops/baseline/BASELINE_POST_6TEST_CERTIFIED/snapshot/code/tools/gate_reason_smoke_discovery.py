import json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOG_DIR = ROOT / "logs"
META = LOG_DIR / "meta.jsonl"
ANN  = LOG_DIR / "announce.log"
SHADOW = LOG_DIR / "shadow_plans.jsonl"

def clean_logs():
    for p in (META, ANN, SHADOW):
        try:
            p.unlink()
        except FileNotFoundError:
            pass

def run_case(name, extra_args):
    clean_logs()

    cmd = [sys.executable, "-m", "tbot.main",
           "--run",
           "--iters", "1",
           "--sleep", "0.01",
           "--sim_in_session", "1",
           "--sim_pre_close", "0",
           "--force_signal", "S11",
           "--force_signal_repeat", "1",
           "--force_signal_ignore_session", "0",
           "--force_signal_ignore_pre_close", "0",
           "--shadow",
           "--risk_usd", "250",
           "--max_qty", "5000",
           "--shadow_entry", "100",
           "--shadow_stop", "99",
           "--shadow_tp", "102",
           "--gate_min_rr", "1.0",
           "--gate_min_conf", "0.90",
           "--gate_cooldown_sec", "0",
           "--gate_max_plans_per_day", "999",
           "--gate_max_risk_usd", "999999"
          ]

    cmd += extra_args

    rc = subprocess.call(cmd, cwd=str(ROOT))
    # parse meta.jsonl (truth)
    rejects = []
    accepts = []
    fires = []
    if META.exists():
        for line in META.read_text(encoding="utf-8").splitlines():
            try:
                obj = json.loads(line)
            except Exception:
                continue
            k = obj.get("kind")
            if k == "shadow_reject":
                rejects.append(obj.get("payload", {}))
            elif k == "shadow_accept":
                accepts.append(obj.get("payload", {}))
            elif k == "signal_fire":
                fires.append(obj.get("payload", {}))

    out = {
        "rc": rc,
        "fire": len(fires),
        "accept": len(accepts),
        "reject": len(rejects),
        "reasons": (rejects[-1].get("reasons") if rejects else None),
        "reject_payload_tail": (rejects[-1] if rejects else None),
    }
    print(f"\n=== {name} ===")
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return out

def run_case_2iters(name, extra_args):
    clean_logs()
    cmd = [sys.executable, "-m", "tbot.main",
           "--run",
           "--iters", "2",
           "--sleep", "0.01",
           "--sim_in_session", "1",
           "--sim_pre_close", "0",
           "--force_signal", "S11",
           "--force_signal_repeat", "2",
           "--force_signal_ignore_session", "0",
           "--force_signal_ignore_pre_close", "0",
           "--shadow",
           "--risk_usd", "250",
           "--max_qty", "5000",
           "--shadow_entry", "100",
           "--shadow_stop", "99",
           "--shadow_tp", "102",
           "--gate_min_rr", "1.0",
           "--gate_min_conf", "0.90",
           "--gate_cooldown_sec", "0",
           "--gate_max_plans_per_day", "999",
           "--gate_max_risk_usd", "999999"
          ]
    cmd += extra_args

    rc = subprocess.call(cmd, cwd=str(ROOT))

    rejects = []
    accepts = []
    fires = []
    if META.exists():
        for line in META.read_text(encoding="utf-8").splitlines():
            try:
                obj = json.loads(line)
            except Exception:
                continue
            k = obj.get("kind")
            if k == "shadow_reject":
                rejects.append(obj.get("payload", {}))
            elif k == "shadow_accept":
                accepts.append(obj.get("payload", {}))
            elif k == "signal_fire":
                fires.append(obj.get("payload", {}))

    out = {
        "rc": rc,
        "fire": len(fires),
        "accept": len(accepts),
        "reject": len(rejects),
        "reasons_all": [r.get("reasons") for r in rejects],
        "reject_payload_tail": (rejects[-1] if rejects else None),
    }
    print(f"\n=== {name} ===")
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return out

def main():
    print("==== GATE_REASON_SMOKE_DISCOVERY ====")

    run_case("RR_BELOW_MIN", ["--gate_min_rr", "3.0"])

    run_case("CONF_BELOW_MIN", ["--gate_min_conf", "0.995"])

    # Max risk
    run_case("MAX_RISK_USD", ["--gate_max_risk_usd", "100"])

    run_case_2iters("MAX_PLANS_PER_DAY", ["--gate_max_plans_per_day", "1", "--gate_cooldown_sec", "0"])

    run_case_2iters("COOLDOWN_ACTIVE", ["--gate_cooldown_sec", "999", "--gate_max_plans_per_day", "999"])

if __name__ == "__main__":
    main()
