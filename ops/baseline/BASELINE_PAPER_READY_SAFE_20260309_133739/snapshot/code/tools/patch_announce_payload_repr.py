import re
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\org_bot\tbot")
if not ROOT.exists():
    raise SystemExit(f"ROOT not found: {ROOT}")

candidates = list(ROOT.rglob("*.py"))

PATTERNS = [
    # " ".join(f"{k}={v}" for k,v in payload.items())
    (re.compile(r'(" "\.join\(\s*f["\']\{k\}=\{v\}["\']\s*for\s*k\s*,\s*v\s*in\s*payload\.items\(\)\s*\))'),
     '{payload!r}'),
    (re.compile(r'(" "\.join\(\s*f["\']\{k\}=\{v\}["\']\s*for\s*\(\s*k\s*,\s*v\s*\)\s*in\s*payload\.items\(\)\s*\))'),
     '{payload!r}'),

    # " ".join([f"{k}={v}" for k,v in payload.items()])
    (re.compile(r'(" "\.join\(\s*\[\s*f["\']\{k\}=\{v\}["\']\s*for\s*k\s*,\s*v\s*in\s*payload\.items\(\)\s*\]\s*\))'),
     '{payload!r}'),
    (re.compile(r'(" "\.join\(\s*\[\s*f["\']\{k\}=\{v\}["\']\s*for\s*\(\s*k\s*,\s*v\s*\)\s*in\s*payload\.items\(\)\s*\]\s*\))'),
     '{payload!r}'),

    # join(f"{k}={v}" for k,v in payload.items())
    (re.compile(r'(join\(\s*f["\']\{k\}=\{v\}["\']\s*for\s*k\s*,\s*v\s*in\s*payload\.items\(\)\s*\))'),
     'payload!r'),
]

KV_INLINE = re.compile(r'(alpha_kill_change|portfolio_kill_change)\s+value=\{[^}]+\}\s+[^\\n]*', re.IGNORECASE)

patched_files = []

for p in candidates:
    txt = p.read_text(encoding="utf-8", errors="replace")

    original = txt
    changed = False

    for rx, replacement in PATTERNS:
        if rx.search(txt):
            txt = rx.sub(replacement, txt)
            changed = True

    if ("portfolio_kill_change" in txt or "alpha_kill_change" in txt) and ("payload" in txt) and ("emit" in txt):
        pass

    if changed and txt != original:
        p.write_text(txt, encoding="utf-8")
        patched_files.append(str(p))

print("PATCH_DONE")
print("PATCHED_FILES:")
for f in patched_files:
    print(" -", f)

if not patched_files:
    print("NOTE: no files matched the auto-patch patterns.")
    print("If kill_switch_smoke still FAILs, paste the file path list from STEP 1 and I'll patch the exact file precisely.")
