from __future__ import annotations

from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\policy\scorecard_policy.py")
s = P.read_text(encoding="utf-8")

TAG = "PATCH_SC_TO_SCORE_V1"
if TAG in s:
    print("PATCH_SKIP: already applied.")
    raise SystemExit(0)

# Must have the injected warmup block
if "ALPHA_WARMUP_AUTO_V2" not in s:
    print("PATCH_FAIL: ALPHA_WARMUP_AUTO_V2 not found.")
    raise SystemExit(2)

# Only patch within decide_alpha(...) function region (best-effort)
# We'll replace exact patterns getattr(sc, 'fires'...) and getattr(sc, 'accepts'...)
before = s

# If already correct, mark + exit
if "getattr(score, 'fires'" in s and "getattr(score, 'accepts'" in s:
    s2 = s + f"\n# {TAG}\n"
    P.write_text(s2, encoding="utf-8")
    print("PATCH_OK: already correct; tagged file.")
    raise SystemExit(0)

s = s.replace("getattr(sc, 'fires', 0)", "getattr(score, 'fires', 0)")
s = s.replace("getattr(sc, 'accepts', 0)", "getattr(score, 'accepts', 0)")

if s == before:
    print("PATCH_FAIL: no changes made (patterns not found).")
    raise SystemExit(3)

# Minimal sanity: ensure we didn't accidentally change other things
if "getattr(sc, 'fires'" in s or "getattr(sc, 'accepts'" in s:
    print("PATCH_WARN: some sc getattr still present; check file.")
    # continue anyway

# Backup then write
bak = P.with_suffix(P.suffix + ".bak_sc_to_score")
bak.write_text(before, encoding="utf-8")
P.write_text(s + f"\n# {TAG}\n", encoding="utf-8")

print("PATCH_OK: replaced sc -> score in ALPHA_WARMUP_AUTO_V2 (backup written).")
print("BACKUP:", str(bak))
