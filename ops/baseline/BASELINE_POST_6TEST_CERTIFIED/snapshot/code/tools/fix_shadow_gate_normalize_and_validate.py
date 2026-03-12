import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
SG = ROOT / "tbot" / "runtime" / "shadow_gate.py"

txt = SG.read_text(encoding="utf-8")
lines = txt.splitlines(True)

def is_toplevel_def_or_class(ln: str) -> bool:
    return (ln.startswith("def ") or ln.startswith("class ")) and (not ln.startswith("def _normalize_reasons("))

# 1) find def _normalize_reasons start
start = None
for i, ln in enumerate(lines):
    if ln.startswith("def _normalize_reasons("):
        start = i
        break
if start is None:
    raise SystemExit("shadow_gate.py: def _normalize_reasons not found")

# 2) find end of its block = next top-level def/class
end = start + 1
while end < len(lines):
    ln = lines[end]
    if (ln.startswith("def ") or ln.startswith("class ")) and (ln[:1] not in (" ", "\t")):
        break
    end += 1

# 3) remove any existing validate_gate_reasons anywhere (avoid duplicates)
txt2 = "".join(lines)
txt2 = re.sub(
    r"(?ms)^def validate_gate_reasons\([^\n]*\):\n(?:^[ \t].*\n|^\n)*",
    "",
    txt2
)
lines = txt2.splitlines(True)

# Re-find _normalize_reasons block after removal
start = None
for i, ln in enumerate(lines):
    if ln.startswith("def _normalize_reasons("):
        start = i
        break
if start is None:
    raise SystemExit("shadow_gate.py: def _normalize_reasons not found (after cleanup)")

end = start + 1
while end < len(lines):
    ln = lines[end]
    if (ln.startswith("def ") or ln.startswith("class ")) and (ln[:1] not in (" ", "\t")):
        break
    end += 1

normalize_block = """\
def _normalize_reasons(reasons):
    \"""
    Return deterministic, unique, sorted list of reasons.

    - None/empty -> []
    - str items -> lower/strip
    - keeps only non-empty tokens
    \"""
    if not reasons:
        return []
    out = []
    seen = set()
    for r in reasons:
        if r is None:
            continue
        s = str(r).strip().lower()
        if not s:
            continue
        if s not in seen:
            seen.add(s)
            out.append(s)
    # deterministic (enterprise): sorted
    return sorted(out)

"""

validate_block = """\
def validate_gate_reasons(reasons):
    \"""
    Validate reject reasons against the locked taxonomy.

    Returns:
      - norm: normalized reasons (sorted, unique)
      - unknown: unknown tokens (if any)
    If unknown exists, 'unknown_reject' will be appended (still normalized).
    \"""
    norm = _normalize_reasons(reasons)
    unknown = [r for r in norm if r not in _ALLOWED_REASONS]
    if unknown:
        norm = _normalize_reasons(list(norm) + ["unknown_reject"])
    return norm, unknown

"""

# 4) replace the whole _normalize_reasons block with canonical one
new_lines = []
new_lines.extend(lines[:start])
# ensure one blank line before normalize (optional, safe)
if new_lines and new_lines[-1].strip() != "":
    new_lines.append("\n")
new_lines.append(normalize_block)
new_lines.append("\n")
new_lines.append(validate_block)

# then append the rest (from end of old normalize block)
new_lines.extend(lines[end:])

SG.write_text("".join(new_lines), encoding="utf-8")
print("FIXED NORMALIZE+VALIDATE:", SG)
