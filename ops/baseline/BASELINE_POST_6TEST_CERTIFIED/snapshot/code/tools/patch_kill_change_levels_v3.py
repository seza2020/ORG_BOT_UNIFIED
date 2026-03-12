from pathlib import Path
import re

P = Path(r"C:\alpaca-bot\org_bot\tbot\runtime\orchestrator.py")
lines = P.read_text(encoding="utf-8", errors="replace").splitlines(True)
orig = "".join(lines)

def patch_level_near_kind(kind_token: str) -> int:
    changed = 0
    for i, ln in enumerate(lines):
        if kind_token not in ln:
            continue

        if "level" in ln and "level" in ln:
            new_ln, n = re.subn(r'\blevel\s*=\s*[^,)\n]+', 'level="INFO"', ln, count=1)
            if n:
                lines[i] = new_ln
                changed += 1
                continue

        for j in range(max(0, i-6), i):
            if "level" not in lines[j]:
                continue
            new_lj, n = re.subn(r'\blevel\s*=\s*[^,)\n]+', 'level="INFO"', lines[j], count=1)
            if n:
                lines[j] = new_lj
                changed += 1
                break

    return changed

txt = "".join(lines)
quick_patterns = [
    (r'level\s*=\s*"WARN"\s*if\s*st\.alpha_kill\s*else\s*"INFO"', 'level="INFO"'),
    (r"level\s*=\s*'WARN'\s*if\s*st\.alpha_kill\s*else\s*'INFO'", 'level="INFO"'),
    (r'level\s*=\s*"ERROR"\s*if\s*st\.portfolio_kill\s*else\s*"INFO"', 'level="INFO"'),
    (r"level\s*=\s*'ERROR'\s*if\s*st\.portfolio_kill\s*else\s*'INFO'", 'level="INFO"'),
]
q_changed = 0
for pat, rep in quick_patterns:
    txt2, n = re.subn(pat, rep, txt)
    if n:
        q_changed += n
        txt = txt2

if q_changed:
    lines = txt.splitlines(True)

c1 = patch_level_near_kind("alpha_kill_change")
c2 = patch_level_near_kind("portfolio_kill_change")

new = "".join(lines)
if new == orig:
    raise SystemExit("NO_CHANGES: couldn't patch levels. Paste 15 lines around both kill_change blocks.")

P.write_text(new, encoding="utf-8")
print("PATCHED:", str(P))
print("CHANGES:", {"quick": q_changed, "alpha_kind_hits": c1, "portfolio_kind_hits": c2})
