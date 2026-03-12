import io, os, re

ROOT = r"C:\alpaca-bot\org_bot"
F = os.path.join(ROOT, r"tbot\runtime\orchestrator.py")

with io.open(F, "r", encoding="utf-8") as f:
    s = f.read()

orig = s

# normalize portfolio_kill_change -> INFO
s = re.sub(
    r"(make_event\(\s*level\s*=\s*['\"])(ERROR|WARN)(['\"],\s*kind\s*=\s*['\"]portfolio_kill_change['\"])",
    r"\1INFO\3",
    s,
)

# normalize alpha_kill_change -> INFO
s = re.sub(
    r"(make_event\(\s*level\s*=\s*['\"])(ERROR|WARN)(['\"],\s*kind\s*=\s*['\"]alpha_kill_change['\"])",
    r"\1INFO\3",
    s,
)

if s == orig:
    raise SystemExit("PATCH FAILED: did not find target make_event(level=..., kind=..._kill_change)")

with io.open(F, "w", encoding="utf-8", newline="\n") as f:
    f.write(s)

print("PATCHED:", F)
