from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tools\kill_switch_smoke.py")
s = P.read_text(encoding="utf-8", errors="replace")

# -----------------------------
# -----------------------------
run_cmd_block = r'''
def run_cmd(extra_args: list[str]) -> tuple[int,str]:
    cmd = [sys.executable, "-m", "tbot.main", "--run", "--iters", "1", "--sleep", "0.01",
           "--shadow",
           "--risk_usd", "250", "--max_qty", "5000",
           "--force_signal", "S11",
           "--gate_min_rr", "1.0", "--gate_min_conf", "0.9",
           "--gate_cooldown_sec", "0",
           "--gate_max_plans_per_day", "999",
           "--gate_max_risk_usd", "999999",
          ] + extra_args

    p = subprocess.run(cmd, capture_output=True, text=True)
    out = (p.stdout or "") + ("\n" if p.stdout and p.stderr else "") + (p.stderr or "")
    return p.returncode, out
'''.strip("\n")

# Replace existing def run_cmd(...) block until next def
s2, n = re.subn(r'(?ms)^def run_cmd\(.*?\n(?=^def\s+|\Z)', run_cmd_block + "\n\n", s)
if n == 0:
    raise SystemExit("NO_CHANGES: could not locate def run_cmd() block to replace")

s = s2

# -----------------------------
# 2) Ensure helper rc_ok exists (after run_cmd)
# -----------------------------
if "def rc_ok(" not in s:
    s = re.sub(
        r'(?ms)(' + re.escape(run_cmd_block) + r'\n\n)',
        r'\1def rc_ok(rc: int, out: str) -> bool:\n'
        r'    # Accept rc=0 or rc=1 for kill-block scenarios, but fail on real crashes\n'
        r'    if rc == 2:\n'
        r'        return False  # argparse / bad args\n'
        r'    if rc not in (0, 1):\n'
        r'        return False\n'
        r'    bad = ("Traceback (most recent call last):" in out) or ("Exception:" in out)\n'
        r'    return not bad\n\n',
        s,
        count=1
    )

# -----------------------------
# 3) Force rc_w/out_w and rc_a/out_a capture
# -----------------------------
s = re.sub(r'(?m)^\s*rc_w\s*,\s*_\s*=\s*run_cmd\(', '    rc_w, out_w = run_cmd(', s)
s = re.sub(r'(?m)^\s*rc_a\s*,\s*_\s*=\s*run_cmd\(', '    rc_a, out_a = run_cmd(', s)

# If it already had rc_w, out_w etc, keep it; but ensure variables exist:
s = re.sub(r'(?m)^\s*rc_w\s*,\s*out_w\s*=\s*run_cmd\(', '    rc_w, out_w = run_cmd(', s)
s = re.sub(r'(?m)^\s*rc_a\s*,\s*out_a\s*=\s*run_cmd\(', '    rc_a, out_a = run_cmd(', s)

# -----------------------------
# 4) Relax pass_w/pass_a to use rc_ok
# -----------------------------
s = re.sub(
    r'(?m)^\s*pass_w\s*=\s*\(rc_w\s*==\s*0\)\s*and\s*\(fire_w\s*==\s*0\)\s*and\s*\(acc_w\s*==\s*0\)\s*and\s*\(sh_w\s*==\s*0\)\s*$',
    '    pass_w = rc_ok(rc_w, out_w) and (fire_w == 0) and (acc_w == 0) and (sh_w == 0)',
    s
)
s = re.sub(
    r'(?m)^\s*pass_a\s*=\s*\(rc_a\s*==\s*0\)\s*and\s*\(fire_a\s*==\s*0\)\s*and\s*\(acc_a\s*==\s*0\)\s*and\s*\(sh_a\s*==\s*0\)\s*$',
    '    pass_a = rc_ok(rc_a, out_a) and (fire_a == 0) and (acc_a == 0) and (sh_a == 0)',
    s
)

P.write_text(s, encoding="utf-8")
print("PATCHED:", P)
