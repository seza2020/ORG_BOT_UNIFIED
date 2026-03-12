from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\strategies\s11_alpha.py")
s = P.read_text(encoding="utf-8")

TAG = "S11_CONF_THRESHOLD_V1"
if TAG in s:
    print("PATCH_SKIP: already present.")
    raise SystemExit(0)

# Find the line that defines conf from TBOT_S11_MIN_CONF
m = re.search(r"(?m)^\s*conf\s*=\s*_env_float\(\s*[\"']TBOT_S11_MIN_CONF[\"']\s*,\s*[\"'][0-9.]+[\"']\s*\)\s*$", s)
if not m:
    print("PATCH_FAIL: could not find conf=_env_float('TBOT_S11_MIN_CONF', ...)")
    raise SystemExit(2)

line_start = m.start()
line_end = m.end()

# Determine indentation of that line
line = s[line_start:line_end]
ind = re.match(r"^(\s*)", line).group(1)

replacement = (
    f"{ind}# {TAG}: TBOT_S11_MIN_CONF is a threshold; TBOT_S11_CONF_VALUE is the produced confidence\n"
    f"{ind}conf_value = _env_float('TBOT_S11_CONF_VALUE', '0.30')\n"
    f"{ind}min_conf = _env_float('TBOT_S11_MIN_CONF', '0.55')\n"
    f"{ind}conf = float(conf_value)\n"
    f"{ind}if conf < float(min_conf):\n"
    f"{ind}    return None, 0.0, 's11_conf_below_min'\n"
)

s2 = s[:line_start] + replacement + s[line_end:] + "\n"
P.write_text(s2, encoding="utf-8")
print("PATCH_OK: applied S11_CONF_THRESHOLD_V1")
