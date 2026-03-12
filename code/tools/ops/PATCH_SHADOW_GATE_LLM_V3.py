import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
F = ROOT / "tbot" / "runtime" / "shadow_gate.py"
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = F.with_name(F.name + f".bak_{stamp}")
shutil.copy2(F, backup)

src = F.read_text(encoding="utf-8", errors="replace")
lines = src.splitlines()

def has_line_prefix(prefix: str) -> bool:
    return any(l.startswith(prefix) for l in lines)

# 1) Ensure imports (non-destructive)
need_imports = []
if "from tbot.runtime.llm_gate import LlmGate" not in src:
    need_imports.append("from tbot.runtime.llm_gate import LlmGate")
if not re.search(r"(?m)^import\s+os\s*$", src):
    need_imports.append("import os")
if not re.search(r"(?m)^import\s+uuid\s*$", src):
    need_imports.append("import uuid")

if need_imports:
    # Insert after the first import block line, else at top
    inserted = False
    for i, l in enumerate(lines):
        if l.startswith("import ") or l.startswith("from "):
            # insert after last consecutive import/from at top section
            j = i
            while j < len(lines) and (lines[j].startswith("import ") or lines[j].startswith("from ")):
                j += 1
            lines = lines[:j] + need_imports + lines[j:]
            inserted = True
            break
    if not inserted:
        lines = need_imports + [""] + lines

# refresh src after possible import injection
src = "\n".join(lines) + "\n"

# 2) Extend taxonomy for stable reject_reason
# Add "llm_gate_deny" into _ALLOWED_REASONS if not present
if '"llm_gate_deny"' not in src:
    # safest: insert near the end of _ALLOWED_REASONS set block
    m = re.search(r"(?s)(_ALLOWED_REASONS\s*=\s*\{.*?\n\})", src)
    if m:
        block = m.group(1)
        if '"llm_gate_deny"' not in block:
            block2 = block[:-2] + '    "llm_gate_deny",\n}'  # before closing }
            src = src.replace(block, block2, 1)

# 3) Find def evaluate(...) block boundaries
lines = src.splitlines()
eval_idx = None
eval_indent = ""
for i, l in enumerate(lines):
    if re.match(r"^\s*def\s+evaluate\s*\(", l):
        eval_idx = i
        eval_indent = re.match(r"^(\s*)", l).group(1)
        break

if eval_idx is None:
    print("PATCH_APPLIED=0")
    print("REASON=def_evaluate_not_found")
    print("TARGET=", F)
    print("BACKUP=", backup)
    raise SystemExit(0)

# block ends at next def/class at same indent (or less) after eval line
end_idx = len(lines)
for j in range(eval_idx + 1, len(lines)):
    lj = lines[j]
    if re.match(rf"^{re.escape(eval_indent)}(def|class)\s+", lj):
        end_idx = j
        break

block = lines[eval_idx:end_idx]

# 4) Locate first ACCEPT return inside evaluate
# Accept return patterns:
#   return (True, reasons)
#   return(True, reasons)
#   return True, reasons
accept_line_idx = None
accept_line_indent = None
rx_accept = re.compile(r"^\s*return\s*\(?\s*True\b", re.IGNORECASE)

for k, l in enumerate(block):
    if rx_accept.match(l.strip()):
        # guard: must be a real return statement line
        if re.match(r"^\s*return\b", l):
            accept_line_idx = k
            accept_line_indent = re.match(r"^(\s*)", l).group(1)
            break

if accept_line_idx is None:
    # Try a more specific pattern for tuple form: return (True, ...
    rx_accept2 = re.compile(r"^\s*return\s*\(\s*True\s*,", re.IGNORECASE)
    for k, l in enumerate(block):
        if rx_accept2.match(l):
            accept_line_idx = k
            accept_line_indent = re.match(r"^(\s*)", l).group(1)
            break

if accept_line_idx is None:
    print("PATCH_APPLIED=0")
    print("REASON=accept_return_not_found_in_evaluate")
    print("TARGET=", F)
    print("BACKUP=", backup)
    raise SystemExit(0)

indent = accept_line_indent

inject = [
    f"{indent}# --- LLM Advisory Gate (Injected) ---",
    f"{indent}try:",
    f"{indent}    _gate = LlmGate(runroot=os.environ.get('TBOT_RUNROOT',''))",
    f"{indent}    _sym = getattr(plan, 'symbol', 'UNKNOWN') if 'plan' in locals() else 'UNKNOWN'",
    f"{indent}    _features = getattr(plan, 'features', {{}}) if 'plan' in locals() else {{}}",
    f"{indent}    if not isinstance(_features, dict):",
    f"{indent}        _features = {{}}",
    f"{indent}    _meta = {{",
    f"{indent}        'phase': os.environ.get('TBOT_PHASE','PHASE_1_ADVISORY_ONLY'),",
    f"{indent}        'trace_id': str(uuid.uuid4()),",
    f"{indent}        'symbol': str(_sym),",
    f"{indent}    }}",
    f"{indent}    _res = _gate.evaluate(str(_sym), _features, _meta)",
    f"{indent}    if _res.decision != 'ALLOW':",
    f"{indent}        reasons.append('llm_gate_deny')",
    f"{indent}        return (False, reasons)",
    f"{indent}except Exception:",
    f"{indent}    reasons.append('llm_gate_deny')",
    f"{indent}    return (False, reasons)",
    "",
]

# Insert injection before accept return line inside block
new_block = block[:accept_line_idx] + inject + block[accept_line_idx:]
new_lines = lines[:eval_idx] + new_block + lines[end_idx:]
new_src = "\n".join(new_lines) + "\n"

F.write_text(new_src, encoding="utf-8")

print("PATCH_APPLIED=1")
print("TARGET=", F)
print("BACKUP=", backup)
print("INJECT_BEFORE_BLOCK_LINE=", accept_line_idx + 1)
