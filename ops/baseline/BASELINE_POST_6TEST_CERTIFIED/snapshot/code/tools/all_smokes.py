import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot")

SMOKES = [
    r".\tools\kill_switch_smoke.py",
    r".\tools\regression_smoke2.py",
    r".\tools\gate_reason_normalize_smoke.py",
    r".\tools\secondary_alpha_cap_smoke.py",
    r".\tools\regime_overlay_smoke.py",
]

COMPILES = [
    r".\tbot\runtime\shadow_gate.py",
    r".\tbot\runtime\orchestrator.py",
    r".\tbot\main.py",
    r".\tools\secondary_alpha_cap_smoke.py",
    r".\tools\regime_overlay_smoke.py",
]

def run(cmd, cwd):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

def main():
    cwd = str(ROOT)

    # 1) Compile check (fast fail)
    for f in COMPILES:
        rc, out, err = run([sys.executable, "-m", "py_compile", f], cwd=cwd)
        if rc != 0:
            print("==== ALL_SMOKES ====")
            print("COMPILE_FAIL:", f)
            print(err.strip())
            return 2

    # 2) Run smokes
    results = []
    for s in SMOKES:
        rc, out, err = run([sys.executable, s], cwd=cwd)
        results.append({"script": s, "rc": rc})
        print(out.rstrip())
        if err.strip():
            print("---- STDERR ----")
            print(err.rstrip())

        if rc != 0:
            print("==== ALL_SMOKES ====")
            print("FAIL:", s)
            print(json.dumps({"results": results}, indent=2))
            return 1

    print("==== ALL_SMOKES ====")
    print("PASS")
    print(json.dumps({"results": results}, indent=2))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
