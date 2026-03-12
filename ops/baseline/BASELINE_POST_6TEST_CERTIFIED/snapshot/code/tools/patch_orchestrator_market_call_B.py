from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
txt = P.read_text(encoding="utf-8", errors="replace")

txt2 = txt
txt2 = re.sub(r"market\s*=\s*build_market_snapshot\(\s*now\s*=\s*now\s*,\s*symbols\s*=\s*symbols\s*\)",
              "market = build_market_snapshot(now, symbols)", txt2)

if txt2 == txt:
    print("NO_CHANGES: could not match build_market_snapshot(now=now, symbols=symbols)")
    raise SystemExit(0)

P.write_text(txt2, encoding="utf-8")
print("PATCHED:", P)
