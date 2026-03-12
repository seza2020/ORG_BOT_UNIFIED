import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")
orig = s

# Fix the single-line injection:
# confidence=..., max_qty=...  -> put max_qty on next line with same indent
pattern = r'(?m)^(?P<indent>[ \t]*)confidence=float\(sig_payload\["confidence"\]\),\s*max_qty=int\(shadow_max_qty\),\s*$'
s2 = re.sub(pattern, r'\g<indent>confidence=float(sig_payload["confidence"]),\n\g<indent>max_qty=int(shadow_max_qty),', s)

if s2 == s:
    # more tolerant: there may be many spaces between comma and max_qty
    pattern2 = r'(?m)^(?P<indent>[ \t]*)confidence=float\(sig_payload\["confidence"\]\),[ \t]+max_qty=int\(shadow_max_qty\),\s*$'
    s2 = re.sub(pattern2, r'\g<indent>confidence=float(sig_payload["confidence"]),\n\g<indent>max_qty=int(shadow_max_qty),', s)

s = s2

if s == orig:
    raise SystemExit("PATCH FAIL: did not find the combined confidence/max_qty line to split")

P.write_text(s, encoding="utf-8")
print("PATCHED:", P)
