from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tools\kill_switch_smoke.py")
s = P.read_text(encoding="utf-8", errors="replace")

# Add a helper rc_ok(rc, out)
if "def rc_ok(" not in s:
    # insert after run_cmd()
    s = re.sub(
        r'(?ms)(def run_cmd\(extra_args: list\[str\]\) -> tuple\[int,str\]:\s*.*?\n)\n',
        r'\1\n\ndef rc_ok(rc: int, out: str) -> bool:\n'
        r'    # Accept rc=0 or rc=1 for kill-block scenarios, BUT fail on real crashes\n'
        r'    if rc == 2:\n'
        r'        return False  # argparse / bad args\n'
        r'    if rc not in (0, 1):\n'
        r'        return False\n'
        r'    bad = ("Traceback (most recent call last):" in out) or ("Exception:" in out) or ("ERROR: " in out)\n'
        r'    return not bad\n\n',
        s
    )

# Replace pass_w and pass_a logic to use rc_ok + output
# We need to ensure we have out_w/out_a variables; they exist as second element returned by run_cmd
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

# Also ensure we actually store subprocess output as out_w/out_a (most versions already do)
# If your file uses different variable names, this will still be safe; but we patch common pattern:
s = re.sub(r'(?m)^\s*rc_w,\s*_\s*=\s*run_cmd\(', '    rc_w, out_w = run_cmd(', s)
s = re.sub(r'(?m)^\s*rc_a,\s*_\s*=\s*run_cmd\(', '    rc_a, out_a = run_cmd(', s)

P.write_text(s, encoding="utf-8")
print("PATCHED:", P)
