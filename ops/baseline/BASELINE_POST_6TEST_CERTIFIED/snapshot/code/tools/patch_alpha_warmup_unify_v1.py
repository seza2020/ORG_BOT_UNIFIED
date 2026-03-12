from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\policy\scorecard_policy.py")
s = P.read_text(encoding="utf-8")

TAG = "ALPHA_WARMUP_UNIFY_V1"
if TAG in s:
    print("PATCH_SKIP: already patched")
    raise SystemExit(0)

# 1) Remove early return warmup_cap block (accepts < 5)
pat_early = r"\n\s*# Warmup phase: do NOT block; just cap\.\s*\n\s*if score\.accepts < 5:\s*\n\s*return ScorecardDecision\(True,\s*0\.5,\s*\"warmup_cap\"\)\s*\n"
if not re.search(pat_early, s):
    print("PATCH_FAIL: cannot find early warmup_cap block")
    raise SystemExit(2)

s = re.sub(pat_early, "\n    # " + TAG + ": warmup handled by unified gate below (removed early warmup_cap)\n", s, count=1)

# 2) Fix warmup_auto_v2 block to use 'score' not 'sc'
s = s.replace("getattr(sc, 'fires', 0)", "getattr(score, 'fires', 0)")
s = s.replace("getattr(sc, 'accepts', 0)", "getattr(score, 'accepts', 0)")

# 3) Ensure warmup branch returns ScorecardDecision (not dynamic AlphaDecision)
pat_dyn = r"return type\('AlphaDecision',\(object,\),\{[^}]*\}\)\(\)"
if re.search(pat_dyn, s):
    s = re.sub(
        pat_dyn,
        "return ScorecardDecision(True, _cap_ratio, 'warmup_insufficient_sample')",
        s,
        count=1,
    )

P.write_text(s, encoding="utf-8")
print("PATCH_OK: unified warmup in decide_alpha (removed warmup_cap, fixed score refs, standardized return)")
