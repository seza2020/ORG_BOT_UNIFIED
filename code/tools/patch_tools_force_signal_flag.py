from pathlib import Path

TOOLS = Path(r"C:\alpaca-bot\org_bot\tools")
hits = []

for p in TOOLS.glob("*.py"):
    txt = p.read_text(encoding="utf-8", errors="replace")
    if "--force_signal" in txt:
        new = txt.replace("--force_signal", "--force_signal")
        p.write_text(new, encoding="utf-8")
        hits.append(str(p))

if not hits:
    print("NO_CHANGES: no tools/*.py contained --force_signal")
else:
    print("PATCHED_FILES:")
    for h in hits:
        print(" -", h)
