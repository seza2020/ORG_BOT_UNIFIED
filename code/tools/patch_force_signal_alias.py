from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\main.py")
txt = P.read_text(encoding="utf-8", errors="replace")

if "--force_signal_sid" in txt:
    print("NO_CHANGES: --force_signal_sid already present")
    raise SystemExit(0)

m = re.search(r'(ap\.add_argument\(\s*["\']--force_signal["\'][^\n]*\n(?:.*\n){0,6}?\s*\))', txt)
if not m:
    pos = txt.find("--force_signal")
    if pos < 0:
        print("NO_CHANGES: could not find --force_signal argument")
        raise SystemExit(0)
    line_start = txt.rfind("\n", 0, pos)
    line_end = txt.find("\n", pos)
    anchor_end = line_end if line_end > 0 else pos
    insert_at = anchor_end + 1
else:
    insert_at = m.end() + 1

alias = 'ap.add_argument("--force_signal_sid", dest="force_signal", default="", help="DEPRECATED alias for --force_signal")\n'

txt2 = txt[:insert_at] + alias + txt[insert_at:]
P.write_text(txt2, encoding="utf-8")
print("PATCHED:", P)
