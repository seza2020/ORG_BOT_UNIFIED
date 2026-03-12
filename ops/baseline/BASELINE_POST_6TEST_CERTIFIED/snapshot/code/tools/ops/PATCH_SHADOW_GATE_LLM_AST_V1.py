from __future__ import annotations
import ast
import shutil
import re
from pathlib import Path
from datetime import datetime

F = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_gate.py")
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
backup = F.with_name(F.name + f".bak_{stamp}")
shutil.copy2(F, backup)

src = F.read_text(encoding="utf-8", errors="replace")
lines = src.splitlines()

# ---------- AST: locate ShadowGate.evaluate return lineno ----------
tree = ast.parse(src)

return_lineno = None  # 1-based

class V(ast.NodeVisitor):
    def visit_ClassDef(self, node: ast.ClassDef):
        if node.name != "ShadowGate":
            return
        for n in node.body:
            if isinstance(n, ast.FunctionDef) and n.name == "evaluate":
                # Collect Return nodes
                rets = [x for x in ast.walk(n) if isinstance(x, ast.Return)]
                if len(rets) != 1:
                    # We expect exactly 1 based on your scan; fail safe if not
                    raise RuntimeError(f"Unexpected return count in evaluate: {len(rets)}")
                r = rets[0]
                # Ensure it's returning (ok, reasons) or equivalent tuple/name
                return_expr = ast.unparse(r.value) if r.value else ""
                # We accept any single return; injection will gate by `if ok:`
                globals()["return_lineno"] = r.lineno

V().visit(tree)

if not return_lineno:
    print("PATCH_APPLIED=0")
    print("REASON=return_lineno_not_found")
    print("TARGET=", str(F))
    print("BACKUP=", str(backup))
    raise SystemExit(0)

# ---------- Ensure imports ----------
def ensure_import_line(lines, line):
    # already present (exact)
    if any(l.strip() == line for l in lines):
        return lines
    # insert after top import block
    for i, l in enumerate(lines):
        if l.startswith("import ") or l.startswith("from "):
            j = i
            while j < len(lines) and (lines[j].startswith("import ") or lines[j].startswith("from ")):
                j += 1
            return lines[:j] + [line] + lines[j:]
    return [line, ""] + lines

lines = ensure_import_line(lines, "import os")
lines = ensure_import_line(lines, "import uuid")
lines = ensure_import_line(lines, "from tbot.runtime.llm_gate import LlmGate")

src2 = "\n".join(lines) + "\n"

# ---------- Ensure taxonomy ----------
if '"llm_gate_deny"' not in src2:
    m = re.search(r"(?s)(_ALLOWED_REASONS\s*=\s*\{.*?\n\})", src2)
    if m:
        block = m.group(1)
        if '"llm_gate_deny"' not in block:
            block2 = block[:-2] + '    "llm_gate_deny",\n}'
            src2 = src2.replace(block, block2, 1)

# rebuild lines after taxonomy change
lines = src2.splitlines()

# ---------- Inject before the AST return line ----------
idx = return_lineno - 1  # 0-based
if idx < 0 or idx >= len(lines):
    print("PATCH_APPLIED=0")
    print("REASON=return_lineno_out_of_range")
    print("TARGET=", str(F))
    print("BACKUP=", str(backup))
    raise SystemExit(0)

return_line = lines[idx]
indent = re.match(r"^(\s*)", return_line).group(1)

inject = [
    f"{indent}# --- LLM Advisory Gate (Injected) ---",
    f"{indent}if ok:",
    f"{indent}    try:",
    f"{indent}        _gate = LlmGate(runroot=os.environ.get('TBOT_RUNROOT',''))",
    f"{indent}        _sym = getattr(plan, 'symbol', 'UNKNOWN') if 'plan' in locals() else 'UNKNOWN'",
    f"{indent}        _features = getattr(plan, 'features', {{}}) if 'plan' in locals() else {{}}",
    f"{indent}        if not isinstance(_features, dict):",
    f"{indent}            _features = {{}}",
    f"{indent}        _meta = {{",
    f"{indent}            'phase': os.environ.get('TBOT_PHASE','PHASE_1_ADVISORY_ONLY'),",
    f"{indent}            'trace_id': str(uuid.uuid4()),",
    f"{indent}            'symbol': str(_sym),",
    f"{indent}        }}",
    f"{indent}        _res = _gate.evaluate(str(_sym), _features, _meta)",
    f"{indent}        if _res.decision != 'ALLOW':",
    f"{indent}            ok = False",
    f"{indent}            reasons.append('llm_gate_deny')",
    f"{indent}    except Exception:",
    f"{indent}        ok = False",
    f"{indent}        reasons.append('llm_gate_deny')",
    "",
]

# idempotency guard: if already injected, do nothing
guard_str = "# --- LLM Advisory Gate (Injected) ---"
if any(guard_str in l for l in lines[max(0, idx-30):idx+1]):
    print("PATCH_APPLIED=0")
    print("REASON=already_injected")
    print("TARGET=", str(F))
    print("BACKUP=", str(backup))
    print("RETURN_LINENO=", return_lineno)
    raise SystemExit(0)

new_lines = lines[:idx] + inject + lines[idx:]
F.write_text("\n".join(new_lines) + "\n", encoding="utf-8")

print("PATCH_APPLIED=1")
print("TARGET=", str(F))
print("BACKUP=", str(backup))
print("RETURN_LINENO=", return_lineno)
