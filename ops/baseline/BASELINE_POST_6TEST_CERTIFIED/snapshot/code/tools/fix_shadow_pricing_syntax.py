from pathlib import Path
from datetime import datetime
import shutil
import re

FILE = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\shadow_pricing.py")
BK = Path(r"C:\alpaca-bot\org_bot\logs\ops") / f"FIX_BACKUP_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
BK.mkdir(parents=True, exist_ok=True)

shutil.copy2(FILE, BK / FILE.name)

src = FILE.read_text(encoding="utf-8")

# Remove any broken try/except blocks we injected
src = re.sub(r"try:\s*p\s*=\s*compute_shadow_prices\([\s\S]*?except Exception:[\s\S]*?return plan", "", src)

# Enforce strict last pricing logic cleanly
src = re.sub(
    r"last\s*=\s*getattr\(snap,\s*\"last\",\s*None\)[\s\S]*?return ShadowPrices\(entry=entry,\s*stop=stop,\s*tp=tp\)",
    """last = getattr(snap, "last", None) if snap is not None else None
        if last is None:
            raise RuntimeError("SHADOW_PRICE_LAST_MISSING")

        entry = last
        stop = entry * (1 + stop_pct)
        tp = entry * (1 - stop_pct * rr)

        return ShadowPrices(entry=entry, stop=stop, tp=tp)
""",
    src,
)

FILE.write_text(src, encoding="utf-8")

print("FIXED shadow_pricing.py and backed up to:", BK)
