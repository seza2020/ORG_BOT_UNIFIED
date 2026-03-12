import json, subprocess, sys, pathlib

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
LOGS = ROOT / "logs"
ANN = LOGS / "announce.log"

def rm_logs():
    for p in [LOGS/"meta.jsonl", ANN, LOGS/"shadow_plans.jsonl"]:
        try: p.unlink()
        except FileNotFoundError: pass

def run(args):
    rm_logs()
    cmd = [sys.executable, "-m", "tbot.main"] + args
    r = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True)
    ann = ANN.read_text(encoding="utf-8", errors="ignore") if ANN.exists() else ""
    return {
        "rc": r.returncode,
        "skip_cnt": ann.count("signal_skip"),
        "skip_out": ("out_of_session" in ann),
        "skip_pre": ("pre_close_active" in ann),
        "skip_port": ("portfolio_kill_active" in ann),
        "ann_tail": "\n".join(ann.splitlines()[-20:]),
        "stderr": (r.stderr or "")[-1500:],
    }

def show(name, out, expect):
    ok = True
    for k,v in expect.items():
        if out.get(k) != v:
            ok = False
    print(f"{name}: {'PASS' if ok else 'FAIL'}  " + json.dumps({k:out[k] for k in ['rc','skip_cnt','skip_out','skip_pre','skip_port']}))
    if not ok:
        print("---- EXPECT ----", expect)
        print("---- STDERR ----")
        print(out["stderr"])
        print("---- ANN_TAIL ----")
        print(out["ann_tail"])
    return ok

print("==== SIGNAL_SKIP_REASON_SMOKE ====")

# 1) out_of_session
out1 = run([
    "--run","--iters","1","--sleep","0.01",
    "--sim_in_session","0","--sim_pre_close","0",
])
ok1 = show("A_out_of_session", out1, {"rc":0, "skip_cnt":1, "skip_out":True})

# 2) pre_close
out2 = run([
    "--run","--iters","1","--sleep","0.01",
    "--sim_in_session","1","--sim_pre_close","1",
])
ok2 = show("B_pre_close", out2, {"rc":0, "skip_cnt":1, "skip_pre":True})

# 3) portfolio kill (weekly)
out3 = run([
    "--run","--iters","1","--sleep","0.01",
    "--sim_in_session","1","--sim_pre_close","0",
    "--sim_week_r","-5.1",
])
ok3 = show("C_portfolio_kill", out3, {"rc":0, "skip_cnt":1, "skip_port":True})

if not (ok1 and ok2 and ok3):
    raise SystemExit(1)
