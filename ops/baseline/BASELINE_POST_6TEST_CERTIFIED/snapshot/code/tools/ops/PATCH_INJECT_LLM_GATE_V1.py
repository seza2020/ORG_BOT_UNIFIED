import os, re, sys, json, shutil
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
TBOT = ROOT / "tbot"
RUNTIME = TBOT / "runtime"
OUTDIR = ROOT / "logs" / "ops"
OUTDIR.mkdir(parents=True, exist_ok=True)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
report = OUTDIR / f"LLM_GATE_PATCH_REPORT_PY_{stamp}.txt"

def read(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")

def write(p: Path, s: str):
    p.write_text(s, encoding="utf-8")

targets = [
    "shadow_gate", "ShadowGate", "gate_", "accept", "reject",
    "shadow_plans.jsonl", "telemetry", "reject_reason", "evaluate("
]

# Candidate files: runtime/*.py
files = [p for p in RUNTIME.rglob("*.py") if "__pycache__" not in str(p).lower() and ".bak_" not in p.name]
# Also include main.py for context (not patch target by default)
main_py = TBOT / "main.py"
if main_py.exists():
    files.append(main_py)

hits = []
for p in files:
    s = read(p)
    for i, line in enumerate(s.splitlines(), start=1):
        if any(t in line for t in targets):
            hits.append((str(p), i, line.strip()))

# Write report (first pass)
with report.open("w", encoding="utf-8") as f:
    f.write(f"TS={stamp}\n")
    f.write("=== HITS ===\n")
    for path, ln, line in hits[:800]:
        f.write(f"{path}:{ln}: {line}\n")

# Choose patch target:
# Prefer runtime file containing both "accept" and "reject" and "gate" clues
def score(p: Path, s: str) -> int:
    sc = 0
    name = p.name.lower()
    if "gate" in name: sc += 5
    if "shadow" in name: sc += 3
    if "/runtime/" in str(p).replace("\\","/"): sc += 2
    for kw, w in [("def evaluate",5), ("accept",3), ("reject",3), ("telemetry",2), ("shadow_plans.jsonl",2)]:
        if kw in s: sc += w
    return sc

best = None
best_sc = -1
best_s = None
for p in files:
    if "tbot\\runtime" not in str(p).lower().replace("/","\\"):
        continue
    s = read(p)
    sc = score(p, s)
    if sc > best_sc:
        best, best_sc, best_s = p, sc, s

if best is None:
    print(f"REPORT={report}")
    print("PATCH_APPLIED=0")
    print("REASON=no_runtime_file_found")
    sys.exit(0)

# Patch strategy:
# 1) Ensure imports: os, uuid and LlmGate import
# 2) Ensure helper _get_llm_gate exists
# 3) Inject a call near the first obvious accept path inside an evaluate-like function.
s = best_s

backup = best.with_name(best.name + f".bak_{stamp}")
shutil.copy2(best, backup)

def ensure_import(src: str, imp_line: str) -> str:
    if imp_line in src:
        return src
    # insert after first import block line
    m = re.search(r"(?m)^(import .+|from .+ import .+)\s*$", src)
    if m:
        insert_at = m.end()
        return src[:insert_at] + "\n" + imp_line + src[insert_at:]
    return imp_line + "\n" + src

s = ensure_import(s, "import os")
s = ensure_import(s, "import uuid")
s = ensure_import(s, "from tbot.runtime.llm_gate import LlmGate")

if "_TBOT_LLM_GATE" not in s:
    s += """

# --- LLM advisory gate (injected) ---
_TBOT_LLM_GATE = None

def _get_llm_gate(runroot: str):
    global _TBOT_LLM_GATE
    if _TBOT_LLM_GATE is None:
        _TBOT_LLM_GATE = LlmGate(runroot=runroot)
    return _TBOT_LLM_GATE
"""

# Injection anchor: look for a line that records accept OR writes accepted plan.
# We'll inject before the first occurrence of any of these tokens:
anchors = [
    "telemetry.record(\"accept\"",
    "telemetry.record('accept'",
    "kind == \"accept\"",
    "kind == 'accept'",
    "accepted =",
    "accepts +=",
]

lines = s.splitlines()
idx = None
for i, line in enumerate(lines):
    if any(a in line for a in anchors):
        idx = i
        break

if idx is None:
    # fallback: look for "return True" in evaluate gate files
    for i, line in enumerate(lines):
        if "return True" in line and "accept" in s.lower():
            idx = i
            break

if idx is None:
    # Do not patch if no safe anchor
    write(best, best_s)  # no-op (but backup exists)
    with report.open("a", encoding="utf-8") as f:
        f.write("\n=== PATCH ===\n")
        f.write(f"PATCH_APPLIED=0\nTARGET={best}\nREASON=no_anchor_found\n")
    print(f"REPORT={report}")
    print("PATCH_APPLIED=0")
    print(f"TARGET={best}")
    print("REASON=no_anchor_found")
    sys.exit(0)

# Determine indentation of anchor line
anchor_line = lines[idx]
indent = re.match(r"^(\s*)", anchor_line).group(1)

inject = [
    f"{indent}# --- LLM Gate (advisory) ---",
    f"{indent}try:",
    f"{indent}    _gate = _get_llm_gate(runroot=os.environ.get('TBOT_RUNROOT',''))",
    f"{indent}    _sym = (symbol if 'symbol' in locals() else (plan.get('symbol') if 'plan' in locals() and isinstance(plan, dict) else 'UNKNOWN'))",
    f"{indent}    _features = (features if 'features' in locals() else (plan.get('features') if 'plan' in locals() and isinstance(plan, dict) else {{}}))",
    f"{indent}    _meta = {{'phase': os.environ.get('TBOT_PHASE','PHASE_1_ADVISORY_ONLY'), 'trace_id': str(uuid.uuid4()), 'symbol': str(_sym)}}",
    f"{indent}    _res = _gate.evaluate(str(_sym), dict(_features) if isinstance(_features, dict) else {{}}, _meta)",
    f"{indent}    if _res.decision != 'ALLOW':",
    f"{indent}        raise RuntimeError(f'llm_gate:{_res.reason}')",
    f"{indent}except Exception:",
    f"{indent}    raise",
    "",
]

new_lines = lines[:idx] + inject + lines[idx:]
new_s = "\n".join(new_lines) + "\n"

write(best, new_s)

with report.open("a", encoding="utf-8") as f:
    f.write("\n=== PATCH ===\n")
    f.write(f"PATCH_APPLIED=1\nTARGET={best}\nBACKUP={backup}\nANCHOR_LINE={idx+1}\n")

print(f"REPORT={report}")
print("PATCH_APPLIED=1")
print(f"TARGET={best}")
print(f"BACKUP={backup}")
