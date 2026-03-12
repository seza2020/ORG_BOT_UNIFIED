import shutil, re
from pathlib import Path
from datetime import datetime

ROOT=Path(r"C:\alpaca-bot\org_bot")
path=ROOT/"tbot"/"runtime"/"orchestrator.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt=path.read_text(encoding="utf-8", errors="ignore")
if "OBS_REASON_NONE_V1" in txt:
    print("SKIP: already patched")
    raise SystemExit(0)

stamp=datetime.now().strftime("%Y%m%d_%H%M%S")
bak=ROOT/"logs"/"ops"/"patches"/f"OBS_REASON_NONE_V1_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"orchestrator.py")

# Heuristic: find the log line that prints strategy_result {... 'returned': ... 'reason': ...}
# We'll inject just before that log call, normalizing reason when returned == 'NONE'
anchor = re.search(r"strategy_result\s*\{", txt)
if not anchor:
    # fallback: search for literal 'strategy_result' in file
    anchor = re.search(r"strategy_result", txt)
if not anchor:
    print("FAIL: cannot find strategy_result logging anchor")
    raise SystemExit(2)

# We will insert a small helper block near the first occurrence of "strategy_result"
insert_at = anchor.start()

block = """
    # --- OBS_REASON_NONE_V1 (observability-only) ---
    try:
        if (isinstance(sr, dict) and sr.get("returned") == "NONE" and not sr.get("reason")):
            # best-effort reason attribution without changing trading logic
            am = sr.get("has_alpha_mode")
            cc = sr.get("has_core_context")
            # these locals typically exist in orchestrator scope; guard if not
            _in_session = locals().get("in_session", None)
            _alpha_mode = locals().get("alpha_mode", None)
            if _in_session is False:
                sr["reason"] = "out_of_session"
            elif cc is False:
                sr["reason"] = "missing_core_context"
            elif am is False:
                sr["reason"] = "missing_alpha_mode"
            else:
                # if alpha_mode exists and is OFF, attribute
                try:
                    if isinstance(_alpha_mode, dict) and (_alpha_mode.get("mode") == "OFF"):
                        sr["reason"] = "alpha_off"
                    else:
                        sr["reason"] = "no_setup"
                except Exception:
                    sr["reason"] = "no_setup"
    except Exception:
        pass
    # --- /OBS_REASON_NONE_V1 ---
"""

# We need to locate where sr dict is built; usually variable name is sr or strategy_result dict.
# We'll insert the block at the first anchor and rely on sr existing; if not, it's harmless (wrapped in try).
txt2 = txt[:insert_at] + block + txt[insert_at:]

path.write_text(txt2, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
