import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
SG = ROOT / "tbot" / "runtime" / "shadow_gate.py"

txt = SG.read_text(encoding="utf-8")
lines = txt.splitlines(True)

def find_line_idx(pred):
    for i, ln in enumerate(lines):
        if pred(ln):
            return i
    return None

# 1) locate def _normalize_reasons
i_norm = find_line_idx(lambda ln: ln.startswith("def _normalize_reasons("))
if i_norm is None:
    raise SystemExit("shadow_gate.py: def _normalize_reasons not found")

# 2) if validate_gate_reasons is incorrectly inserted right after def _normalize_reasons, remove it
def next_nonempty_idx(start):
    j = start
    while j < len(lines) and lines[j].strip() == "":
        j += 1
    return j

j = next_nonempty_idx(i_norm + 1)

if j < len(lines) and lines[j].startswith("def validate_gate_reasons("):
    # remove the whole validate_gate_reasons function block from here
    k = j + 1
    # consume until we hit next top-level def/class (col 0) AFTER we've seen at least one indented line or blank
    while k < len(lines):
        ln = lines[k]
        if (ln.startswith("def ") or ln.startswith("class ")) and (not ln.startswith("def _normalize_reasons(")) and (ln[:1] != " " and ln[:1] != "\t"):
            break
        # another safe stop: two consecutive blank lines after we've passed at least some content
        k += 1

    del lines[j:k]

# 3) ensure we have validate_gate_reasons exactly once, placed AFTER _normalize_reasons body
# Remove any existing validate_gate_reasons elsewhere to avoid duplicates
out = []
skip = False
for ln in lines:
    if ln.startswith("def validate_gate_reasons("):
        skip = True
        continue
    if skip:
        # stop skipping when next top-level def/class begins
        if (ln.startswith("def ") or ln.startswith("class ")) and (ln[:1] != " " and ln[:1] != "\t"):
            skip = False
            out.append(ln)
        else:
            continue
    else:
        out.append(ln)
lines = out

# re-find normalize after edits
txt2 = "".join(lines)
lines2 = txt2.splitlines(True)
i_norm = None
for i, ln in enumerate(lines2):
    if ln.startswith("def _normalize_reasons("):
        i_norm = i
        break
if i_norm is None:
    raise SystemExit("shadow_gate.py: def _normalize_reasons disappeared unexpectedly")

# find end of _normalize_reasons: first subsequent top-level def/class line
k_end = i_norm + 1
while k_end < len(lines2):
    ln = lines2[k_end]
    if (ln.startswith("def ") or ln.startswith("class ")) and (ln[:1] != " " and ln[:1] != "\t"):
        break
    k_end += 1

validate_block = """\
def validate_gate_reasons(reasons):
    \"""
    Validate reject reasons against the locked taxonomy.

    Returns normalized list (sorted, unique). If any unknowns exist,
    'unknown_reject' will be appended (still normalized) and the unknown
    tokens returned separately.
    \"""
    norm = _normalize_reasons(reasons)
    unknown = [r for r in norm if r not in _ALLOWED_REASONS]
    if unknown:
        norm = _normalize_reasons(list(norm) + ["unknown_reject"])
    return norm, unknown

"""

# insert with one blank line before it (if needed)
insert = ""
# ensure there's exactly one blank line before insertion
if k_end > 0 and lines2[k_end-1].strip() != "":
    insert += "\n"
insert += validate_block
if k_end < len(lines2) and lines2[k_end].strip() != "":
    insert += "\n"

lines2.insert(k_end, insert)

SG.write_text("".join(lines2), encoding="utf-8")
print("FIXED:", SG)
