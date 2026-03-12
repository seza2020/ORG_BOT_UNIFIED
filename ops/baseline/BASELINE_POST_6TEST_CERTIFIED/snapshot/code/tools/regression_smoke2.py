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

def tail_lines(path: pathlib.Path, n: int = 12):
    if not path.exists(): return []
    lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    return lines[-n:]

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
        "tail": tail_lines(ANN, 14),
        "stderr": (r.stderr or "")[-4000:],
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
        print("---- ANN_TAIL ----")
        for line in out["tail"]:
            print(line)
    return ok

def set_flag(args, flag, value):
    # set or append a flag value safely
    if flag in args:
        i = args.index(flag)
        if i+1 >= len(args):
            raise SystemExit(f"bad args: {flag} has no value slot")
        args[i+1] = str(value)
    else:
        args += [flag, str(value)]
    return args

def insert_before(args, before_flag, new_flag, new_val):
    # insert [new_flag, new_val] before before_flag if possible else append
    if before_flag in args:
        i = args.index(before_flag)
        return args[:i] + [new_flag, str(new_val)] + args[i:]
    return args + [new_flag, str(new_val)]

print("==== REGRESSION_SMOKE2 ====")

base_args = [
    "--run","--iters","1","--sleep","0.01",
    "--sim_in_session","1","--sim_pre_close","0",
    "--force_signal","S11","--force_signal_repeat","1",
    "--force_signal_ignore_session","0",
    "--shadow",
    "--risk_usd","250","--max_qty","5000","--shadow_entry","100","--shadow_stop","99","--shadow_tp","102",
    "--gate_min_rr","1.0","--gate_min_conf","0.90","--gate_cooldown_sec","0","--gate_max_plans_per_day","999","--gate_max_risk_usd","999999",
]

ok1 = show("A_baseline_forced", run(base_args), {"rc":0,"fire":1,"accept":1,"shadow_count":1})

kill_args = list(base_args)
# safely insert sim_daily_r before --force_signal (order doesn't matter, but this prevents accidental reshuffle)
kill_args = insert_before(kill_args, "--force_signal", "--sim_daily_r", "-2.1")
ok2 = show("B_alpha_kill_blocks_fire", run(kill_args), {"rc":0,"fire":0,"accept":0,"shadow_count":0,"skip":1})

preclose_args = list(base_args)
preclose_args = set_flag(preclose_args, "--sim_pre_close", "1")
# ignore_pre_close stays 0 in this case
ok3 = show("C_preclose_blocks", run(preclose_args), {"rc":0,"fire":0,"accept":0,"shadow_count":0})

if not (ok1 and ok2 and ok3):
    raise SystemExit(1)
