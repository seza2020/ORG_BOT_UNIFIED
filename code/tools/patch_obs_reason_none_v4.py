import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"orchestrator.py"
txt = path.read_text(encoding="utf-8", errors="ignore")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"OBS_REASON_NONE_V4_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"orchestrator.py")

# remove any prior V3/V4 blocks (idempotent)
txt = re.sub(r"# --- OBS_REASON_NONE_V3[\s\S]*?# --- /OBS_REASON_NONE_V3 ---\s*", "", txt)
txt = re.sub(r"# --- OBS_REASON_NONE_V4[\s\S]*?# --- /OBS_REASON_NONE_V4 ---\s*", "", txt)

anchor = "meta.emit(ev); announce.emit(ev)"
if anchor not in txt:
    raise SystemExit("ANCHOR meta.emit(ev); announce.emit(ev) not found")

block = r"""
                    # --- OBS_REASON_NONE_V4 (observability-only) ---
                    try:
                        sr = None
                        # dict event: {"name":..., "payload": {...}}
                        if isinstance(ev, dict):
                            sr = ev.get("payload") or ev.get("data") or ev.get("event") or None
                        # object event: ev.payload
                        if sr is None and hasattr(ev, "payload"):
                            sr = getattr(ev, "payload", None)
                        # nested: {"payload":{"payload":{...}}} (defensive)
                        if isinstance(sr, dict) and isinstance(sr.get("payload"), dict) and ("returned" in sr.get("payload")):
                            sr = sr.get("payload")

                        if isinstance(sr, dict) and sr.get("returned") == "NONE" and not sr.get("reason"):
                            _in_session = locals().get("in_session", None)
                            _alpha_mode = locals().get("alpha_mode", None)

                            if _in_session is False:
                                sr["reason"] = "out_of_session"
                            elif isinstance(_alpha_mode, dict) and _alpha_mode.get("mode") == "OFF":
                                sr["reason"] = "alpha_off"
                            else:
                                sr["reason"] = "no_setup"
                    except Exception:
                        pass
                    # --- /OBS_REASON_NONE_V4 ---
"""

txt = txt.replace(anchor, block + "\n                    " + anchor)
path.write_text(txt, encoding="utf-8")

print("PATCHED:", path)
print("BACKUP:", bak)
