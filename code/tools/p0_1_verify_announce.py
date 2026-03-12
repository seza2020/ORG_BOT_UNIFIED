import logging
from pathlib import Path

from tbot.runtime import _shadow_observability as o

# نصب patch ها (emit patch و هر چی داخلش هست)
o.patch_logging_emit()

# نوشتن مستقیم به announce.log با FileHandler (قطعی)
p = Path(r"logs\announce.log")
p.parent.mkdir(parents=True, exist_ok=True)

h = logging.FileHandler(str(p), encoding="utf-8")
lg = logging.getLogger("announce_selftest")
lg.setLevel(logging.INFO)
lg.handlers = [h]
lg.propagate = False

lg.info("INFO  | 2026-02-19T00:00:00 | SELFTEST | HEARTBEAT\nin_session=True pre_close=False\nportfolio_kill=False\n")
h.close()

# چک نتیجه در همان فایل
txt = p.read_text(encoding="utf-8", errors="ignore").splitlines()
hits = [ln for ln in txt[-200:] if ("SELFTEST" in ln) or ("shadow_gate=" in ln)]

print("=== LAST_HITS ===")
for ln in hits[-30:]:
    print(ln)

ok = any("shadow_gate=" in ln for ln in hits)
print("RESULT shadow_gate_present =", ok)
