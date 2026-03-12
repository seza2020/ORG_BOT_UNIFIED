import re, shutil, json
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"risk_ledger.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore")

if "RISK_LEDGER_LIFECYCLE_V1" in txt:
    print("SKIP: already patched")
    raise SystemExit(0)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"RISK_LEDGER_LIFECYCLE_V1_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"risk_ledger.py")

# We will inject a small helper emit_event + lifecycle wrappers.
# Anchor strategy: find class RiskLedger definition.
m = re.search(r"(?m)^\s*class\s+RiskLedger\s*[\(:]", txt)
if not m:
    print("FAIL: could not find class RiskLedger")
    raise SystemExit(2)

# Find insertion point: right after class line (next newline after it).
ins = txt.find("\n", m.start())
if ins == -1:
    print("FAIL: malformed file (no newline after class)")
    raise SystemExit(3)
ins += 1

block = r'''
    # --- RISK_LEDGER_LIFECYCLE_V1 (observability/ledger only) ---
    def emit_event(self, kind: str, **fields):
        """
        Write a single JSONL event into the ledger file.
        This is observability-only (no trading logic).
        """
        try:
            evt = {
                "ts": datetime.utcnow().replace(microsecond=0).isoformat(),
                "day": fields.pop("day", None),
                "scope": fields.pop("scope", None),
                "kind": kind,
            }
            # Merge remaining fields
            for k, v in fields.items():
                evt[k] = v
            # Drop None keys to keep ledger compact
            evt = {k: v for k, v in evt.items() if v is not None}

            # Prefer existing writer if present; else append directly.
            fp = getattr(self, "ledger_path", None) or getattr(self, "_ledger_path", None)
            if fp is None:
                # best-effort: try to find a path attribute
                fp = fields.get("path")

            if fp is None:
                # If the class already has a method for writing lines, use it
                w = getattr(self, "_append_line", None)
                if callable(w):
                    w(json.dumps(evt, ensure_ascii=False))
                    return True
                return False

            p = Path(str(fp))
            p.parent.mkdir(parents=True, exist_ok=True)
            with p.open("a", encoding="utf-8") as f:
                f.write(json.dumps(evt, ensure_ascii=False) + "\n")
            return True
        except Exception:
            return False

    def on_run_start(self, run_id: str = None, **fields):
        return self.emit_event("run_start", run_id=run_id, **fields)

    def on_run_end(self, run_id: str = None, exit_code: int = None, **fields):
        return self.emit_event("run_end", run_id=run_id, exit_code=exit_code, **fields)

    def on_session_start(self, session: str = None, **fields):
        return self.emit_event("session_start", session=session, **fields)

    def on_session_end(self, session: str = None, **fields):
        return self.emit_event("session_end", session=session, **fields)

    def on_gate_snapshot(self, **fields):
        # fields: plans_used, plans_left, risk_used_usd, risk_left_usd, cooldown_left_sec, cap_hit, cap_usd
        return self.emit_event("gate_snapshot", **fields)
    # --- /RISK_LEDGER_LIFECYCLE_V1 ---
'''
# Ensure datetime/json/Path imports exist; if not, add them near top.
need_imports = []
if "from datetime import datetime" not in txt and "import datetime" not in txt:
    need_imports.append("from datetime import datetime")
if "import json" not in txt:
    need_imports.append("import json")
if "from pathlib import Path" not in txt:
    need_imports.append("from pathlib import Path")

if need_imports:
    # Insert imports after the last import line in the file (simple heuristic).
    im = list(re.finditer(r"(?m)^(import\s+\w+|from\s+\w+.*import\s+.*)\s*$", txt))
    if im:
        last = im[-1].end()
        txt = txt[:last] + "\n" + "\n".join(need_imports) + txt[last:]
    else:
        txt = "\n".join(need_imports) + "\n\n" + txt

txt = txt[:ins] + block + txt[ins:]

path.write_text(txt, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
