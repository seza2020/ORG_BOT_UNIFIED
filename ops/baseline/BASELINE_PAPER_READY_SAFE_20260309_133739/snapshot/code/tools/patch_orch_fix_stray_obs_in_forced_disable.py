from __future__ import annotations
from pathlib import Path
import re
from datetime import datetime

path = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = path.read_text(encoding="utf-8", errors="ignore")

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bakdir = Path(r"C:\alpaca-bot\org_bot\logs\ops\patches") / f"ORCH_FIX_STRAY_OBS_IN_FORCED_DISABLE_{stamp}"
bakdir.mkdir(parents=True, exist_ok=True)
(path.parent / "orchestrator.py").replace(bakdir / "orchestrator.py")  # backup

# We target ONLY the block inside: TBOT_DISABLE_FORCED_SIGNAL_TEST_V1
# Replace the stray OBS_REASON_NONE_V4 + the (misindented) meta.emit line that follows it
# with a correctly-indented single meta.emit line.
pat = re.compile(
    r"""(?msx)
    (\#\s*---\s*TBOT_DISABLE_FORCED_SIGNAL_TEST_V1\s*BEGIN\s*---.*?)
    (                                       # group2: inside block, find the OBS chunk
      \n[ \t]*\#\s*---\s*OBS_REASON_NONE_V4.*?
      \n[ \t]*\#\s*---\s*/OBS_REASON_NONE_V4\s*---\s*
      \n[ \t]*meta\.emit\(ev\);\s*announce\.emit\(ev\)\s*
    )
    """,
)

m = pat.search(s)
if not m:
    raise SystemExit("PATCH_FAIL: could not locate stray OBS_REASON_NONE_V4 inside TBOT_DISABLE_FORCED_SIGNAL_TEST block")

head = m.group(1)
chunk = m.group(2)

# Infer correct indentation from the 'ev = make_event' line inside the TBOT_DISABLE block
# Find last occurrence of a line containing 'ev = make_event' within head+some tail.
window = (head + s[m.start():m.end()])
m_ev = re.search(r"(?m)^([ \t]*)ev\s*=\s*make_event\(", window)
indent = m_ev.group(1) if m_ev else "        "  # fallback

replacement = "\n" + indent + "meta.emit(ev); announce.emit(ev)\n"

s2 = s[:m.start(2)] + replacement + s[m.end(2):]

path.write_text(s2, encoding="utf-8")
print("PATCH_OK:", str(path))
print("BACKUP_DIR:", str(bakdir))
print("NOTE: replaced stray OBS_REASON_NONE_V4+emit with one emit line using indent repr=", repr(indent))
