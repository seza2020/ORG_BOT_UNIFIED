from __future__ import annotations
import shutil, re
from pathlib import Path
from datetime import datetime

F = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_gate.py")
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = F.with_name(F.name + f".bak_{stamp}")
shutil.copy2(F, backup)

src = F.read_text(encoding="utf-8", errors="replace")

def ensure_import(src: str, line: str) -> str:
    if re.search(rf"(?m)^\s*{re.escape(line)}\s*$", src):
        return src
    # insert after first import/from block line, else at top
    lines = src.splitlines()
    for i, l in enumerate(lines):
        if l.startswith("import ") or l.startswith("from "):
            j = i
            while j < len(lines) and (lines[j].startswith("import ") or lines[j].startswith("from ")):
                j += 1
            lines = lines[:j] + [line] + lines[j:]
            return "\n".join(lines) + "\n"
    return line + "\n" + src

# 1) imports
src = ensure_import(src, "import os")
src = ensure_import(src, "import uuid")
src = ensure_import(src, "from tbot.runtime.llm_gate import LlmGate")

# 2) taxonomy
if '"llm_gate_deny"' not in src:
    m = re.search(r"(?s)(_ALLOWED_REASONS\s*=\s*\{.*?\n\})", src)
    if m:
        block = m.group(1)
        if '"llm_gate_deny"' not in block:
            block2 = block[:-2] + '    "llm_gate_deny",\n}'
            src = src.replace(block, block2, 1)

# 3) inject before: return (ok, reasons)
rx = re.compile(r"(?m)^(?P<indent>\s*)return\s*\(\s*ok\s*,\s*reasons\s*\)\s*$")
m = rx.search(src)
if not m:
    print("PATCH_APPLIED=0")
    print("REASON=return_ok_reasons_not_found")
    print("TARGET=", str(F))
    print("BACKUP=", str(backup))
    raise SystemExit(0)

indent = m.group("indent")

inject = f"""
{indent}# --- LLM Advisory Gate (Injected) ---
{indent}if ok:
{indent}    try:
{indent}        _gate = LlmGate(runroot=os.environ.get("TBOT_RUNROOT",""))
{indent}        _sym = getattr(plan, "symbol", "UNKNOWN") if "plan" in locals() else "UNKNOWN"
{indent}        _features = getattr(plan, "features", {{}}) if "plan" in locals() else {{}}
{indent}        if not isinstance(_features, dict):
{indent}            _features = {{}}
{indent}        _meta = {{
{indent}            "phase": os.environ.get("TBOT_PHASE","PHASE_1_ADVISORY_ONLY"),
{indent}            "trace_id": str(uuid.uuid4()),
{indent}            "symbol": str(_sym),
{indent}        }}
{indent}        _res = _gate.evaluate(str(_sym), _features, _meta)
{indent}        if _res.decision != "ALLOW":
{indent}            ok = False
{indent}            reasons.append("llm_gate_deny")
{indent}    except Exception:
{indent}        ok = False
{indent}        reasons.append("llm_gate_deny")
"""

# inject once (before the return line)
src = src[:m.start()] + inject + "\n" + src[m.start():]

F.write_text(src, encoding="utf-8")

print("PATCH_APPLIED=1")
print("TARGET=", str(F))
print("BACKUP=", str(backup))
