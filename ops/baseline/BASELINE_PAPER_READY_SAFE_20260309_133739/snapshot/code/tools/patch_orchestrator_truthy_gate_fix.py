import pathlib, re

P = pathlib.Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
s = P.read_text(encoding="utf-8")

# ------------------------------------------------------------
# A) Fix truthiness bug:
#     if shadow_enabled and shadow_writer and gate and sig_payload is not None:
#   -> use explicit None checks so __len__/__bool__ can't disable the block.
# ------------------------------------------------------------
s2 = re.sub(
    r'(?m)^([ \t]*)if\s+shadow_enabled\s+and\s+shadow_writer\s+and\s+gate\s+and\s+sig_payload\s+is\s+not\s+None\s*:\s*$',
    r'\1if shadow_enabled and (shadow_writer is not None) and (gate is not None) and (sig_payload is not None):',
    s
)

# ------------------------------------------------------------
# B) Remove stale/unsupported GateConfig kwargs if present (max_qty)
#   Example line to delete:
#       max_qty=int(shadow_max_qty),
# ------------------------------------------------------------
s3 = re.sub(r'(?m)^[ \t]*max_qty\s*=\s*int\(\s*shadow_max_qty\s*\)\s*,\s*\n', '', s2)

if s3 == s:
    print("PATCH: no changes needed (patterns not found).")
else:
    P.write_text(s3, encoding="utf-8")
    print("PATCHED:", P)
