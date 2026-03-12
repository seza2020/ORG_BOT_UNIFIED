import json, subprocess, sys, pathlib

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
LOGS = ROOT / "logs"
ANN = LOGS / "announce.log"
SHADOW = LOGS / "shadow_plans.jsonl"

def rm_logs():
    for p in [LOGS/"meta.jsonl", ANN, SHADOW]:
        try: p.unlink()
        except FileNotFoundError: pass

def count_in_file(path: pathlib.Path, needle: str) -> int:
    if not path.exists(): return 0
    txt = path.read_text(encoding="utf-8", errors="ignore")
    return txt.count(needle)

def run(args):
    rm_logs()
    cmd = [sys.executable, "-m", "tbot.main"] + args
    r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    out = {
        "rc": r.returncode,
        "fire": count_in_file(ANN, "signal_fire"),
        "accept": count_in_file(ANN, "shadow_accept"),
        "reject": count_in_file(ANN, "shadow_reject"),
        "skip": count_in_file(ANN, "signal_skip"),
        "shadow_count": (len(SHADOW.read_text(encoding="utf-8", errors="ignore").splitlines()) if SHADOW.exists() else 0),
        "stderr": (r.stderr or "")[-2000:],
    }
    return out

def show(name, out, expect):
    ok = True
    for k, v in expect.items():
        if out.get(k) != v:
            ok = False
    print(f"{name}: {'PASS' if ok else 'FAIL'}  {json.dumps({k:out[k] for k in ['rc','fire','accept','reject','skip','shadow_count']})}")
    if not ok:
        print("---- EXPECT ----", expect)
        print("---- STDERR ----")
        print(out["stderr"])
    return ok

def insert_before(args, before_flag, new_flag, new_val):
    if before_flag in args:
        i = args.index(before_flag)
        return args[:i] + [new_flag, str(new_val)] + args[i:]
    return args + [new_flag, str(new_val)]

print("==== CORE_SURVIVES_ALPHA_KILL ====")

base_args = [
    "--run","--iters","1","--sleep","0.01",
    "--sim_in_session","1","--sim_pre_close","0",

    # AlphaKill ON
    "--sim_daily_r","-2.1",

    # Force CORE (S01) not S11
    "--force_signal","S01","--force_signal_repeat","1",
    "--force_signal_ignore_session","0",
    "--force_signal_ignore_pre_close","0",

    "--shadow",
    "--risk_usd","250","--max_qty","5000","--shadow_entry","100","--shadow_stop","99","--shadow_tp","102",
    "--gate_min_rr","1.0","--gate_min_conf","0.90","--gate_cooldown_sec","0","--gate_max_plans_per_day","999","--gate_max_risk_usd","999999",
]

out = run(base_args)

# EXPECT:
# - Because S01 is non-alpha, alpha_kill should NOT block forced signal_fire
# - So fire=1 accept=1 shadow_count=1
ok = show("CORE_forced_under_alpha_kill", out, {"rc":0,"fire":1,"accept":1,"shadow_count":1})

if not ok:
    raise SystemExit(1)
