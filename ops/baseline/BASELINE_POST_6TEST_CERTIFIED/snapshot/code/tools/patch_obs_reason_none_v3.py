import shutil
from pathlib import Path
from datetime import datetime
import re

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"orchestrator.py"

txt = path.read_text(encoding="utf-8", errors="ignore")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"OBS_REASON_NONE_V3_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"orchestrator.py")

# ---- Remove broken V1 block completely ----
txt = re.sub(r"# --- OBS_REASON_NONE_V1[\s\S]*?# --- /OBS_REASON_NONE_V1 ---", "", txt)

# ---- Fix corrupted inline reason line ----
txt = re.sub(
    r'"reason":\s*\(.*?_sig\.get\("reason"\).*?\),',
    '"reason": (None if _sig is None else _sig.get("reason")),',
    txt,
    flags=re.DOTALL
)

# ---- Insert clean normalization right before meta.emit(ev) ----
anchor = "meta.emit(ev); announce.emit(ev)"
if anchor not in txt:
    raise SystemExit("ANCHOR meta.emit(ev) not found")

block = """
                    # --- OBS_REASON_NONE_V3 (observability-only) ---
                    try:
                        sr = ev.get("payload") if isinstance(ev, dict) else None
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
                    # --- /OBS_REASON_NONE_V3 ---
"""

txt = txt.replace(anchor, block + "\n                    " + anchor)

path.write_text(txt, encoding="utf-8")

print("PATCHED:", path)
print("BACKUP:", bak)
