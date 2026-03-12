import pathlib, re

ROOT = pathlib.Path(r"C:\alpaca-bot\org_bot")
SG = ROOT / "tbot" / "runtime" / "shadow_gate.py"

txt = SG.read_text(encoding="utf-8")

# Ensure we have the taxonomy block and _ALLOWED_REASONS
if "_ALLOWED_REASONS" not in txt:
    raise SystemExit("shadow_gate.py: _ALLOWED_REASONS not found (taxonomy block missing)")

# 1) Export a public constant name for taxonomy lock (single source of truth)
# Add after _ALLOWED_REASONS definition (safe insert)
if "ALLOWED_REASONS =" not in txt:
    # insert right after the closing brace of _ALLOWED_REASONS (first occurrence)
    m = re.search(r"(?s)(_ALLOWED_REASONS\s*=\s*\{.*?\}\s*)\n", txt)
    if not m:
        raise SystemExit("shadow_gate.py: could not locate _ALLOWED_REASONS block to insert ALLOWED_REASONS")
    block = m.group(1)
    insert = block + "\n# Public export for taxonomy lock\nALLOWED_REASONS = frozenset(_ALLOWED_REASONS)\n"
    txt = txt.replace(block, insert, 1)

# 2) Add a validator helper for reject payloads (import-safe; no behavior change to trading)
if "def validate_gate_reasons(" not in txt:
    anchor = "def _normalize_reasons(reasons):"
    if anchor not in txt:
        raise SystemExit("shadow_gate.py: _normalize_reasons not found")
    add = """
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
        # Ensure we always keep a single obvious bucket
        norm = _normalize_reasons(list(norm) + ["unknown_reject"])
    return norm, unknown

"""
    txt = txt.replace(anchor, anchor + add, 1)

SG.write_text(txt, encoding="utf-8")
print("PATCHED:", SG)
