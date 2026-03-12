import json, subprocess, sys
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

def run_once(extra_args):
    clean_logs()
    cmd = [sys.executable, "-m", "tbot.main",
           "--run","--iters","1","--sleep","0.01",
           "--sim_in_session","1","--sim_pre_close","0",
           "--force_signal","S11","--force_signal_repeat","1",
           "--force_signal_ignore_session","0","--force_signal_ignore_pre_close","0",
           "--shadow",
           "--risk_usd","250","--max_qty","5000",
           "--shadow_entry","100","--shadow_stop","99","--shadow_tp","102",
           "--gate_min_rr","1.0","--gate_min_conf","0.90","--gate_cooldown_sec","0",
           "--gate_max_plans_per_day","999","--gate_max_risk_usd","999999"
          ]
    cmd += extra_args
    rc = subprocess.call(cmd, cwd=str(ROOT))
    fires, accepts, rejects = [], [], []
    if META.exists():
        for line in META.read_text(encoding="utf-8").splitlines():
            try:
                obj = json.loads(line)
            except Exception:
                continue
            k = obj.get("kind")
            if k == "signal_fire":
                fires.append(obj.get("payload", {}))
            elif k == "shadow_accept":
                accepts.append(obj.get("payload", {}))
            elif k == "shadow_reject":
                rejects.append(obj.get("payload", {}))
    return rc, fires, accepts, rejects

def main():
    print("==== GATE_REASON_SMOKE_ASSERT ====")

    # 1) RR below min
    rc, fires, acc, rej = run_once(["--gate_min_rr","3.0"])
    assert rc == 0
    assert len(fires) == 1 and len(acc) == 0 and len(rej) == 1
    assert rej[-1].get("reasons") == ["rr_below_min"]

    # 2) CONF below min
    rc, fires, acc, rej = run_once(["--gate_min_conf","0.995"])
    assert rc == 0
    assert len(fires) == 1 and len(acc) == 0 and len(rej) == 1
    assert rej[-1].get("reasons") == ["confidence_below_min"]

    # 3) Risk above max
    rc, fires, acc, rej = run_once(["--gate_max_risk_usd","100"])
    assert rc == 0
    assert len(fires) == 1 and len(acc) == 0 and len(rej) == 1
    assert rej[-1].get("reasons") == ["risk_above_max"]

    print("PASS")

if __name__ == "__main__":
    main()
