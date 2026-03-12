import shutil
from pathlib import Path
from datetime import datetime
import re

ROOT = Path(r"C:\alpaca-bot\org_bot")
F = ROOT / "tbot" / "runtime" / "shadow_gate.py"
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

backup = F.with_name(F.name + f".bak_{stamp}")
shutil.copy2(F, backup)

src = F.read_text(encoding="utf-8")

# 1) Ensure imports
if "from tbot.runtime.llm_gate import LlmGate" not in src:
    src = "from tbot.runtime.llm_gate import LlmGate\nimport os\nimport uuid\n" + src

# 2) Extend taxonomy
if '"llm_gate_deny"' not in src:
    src = src.replace(
        '"fake_price_blocked",',
        '"fake_price_blocked",\n    "llm_gate_deny",'
    )

# 3) Inject before first "return True" inside evaluate
pattern = r"(def evaluate\([^\)]*\):[\s\S]+?)(return True)"
m = re.search(pattern, src)
if not m:
    print("PATCH_APPLIED=0")
    print("REASON=no_return_true_found")
    exit()

inject_block = """

        # --- LLM Advisory Gate ---
        try:
            _gate = LlmGate(runroot=os.environ.get("TBOT_RUNROOT",""))
            _meta = {
                "phase": os.environ.get("TBOT_PHASE","PHASE_1_ADVISORY_ONLY"),
                "trace_id": str(uuid.uuid4()),
                "symbol": getattr(plan, "symbol", "UNKNOWN"),
            }
            _res = _gate.evaluate(
                str(getattr(plan, "symbol", "UNKNOWN")),
                {},
                _meta,
            )
            if _res.decision != "ALLOW":
                reasons.append("llm_gate_deny")
                return False, reasons
        except Exception:
            reasons.append("llm_gate_deny")
            return False, reasons

"""

new_src = src.replace(m.group(2), inject_block + "\n        return True", 1)

F.write_text(new_src, encoding="utf-8")

print("PATCH_APPLIED=1")
print("TARGET=", F)
print("BACKUP=", backup)
