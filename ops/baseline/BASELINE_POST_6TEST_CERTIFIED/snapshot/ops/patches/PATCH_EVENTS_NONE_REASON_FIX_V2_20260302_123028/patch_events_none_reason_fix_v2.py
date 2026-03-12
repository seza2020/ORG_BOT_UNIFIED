import re, sys

path = r"C:\\alpaca-bot\\ORG_BOT_UNIFIED\\code\\tbot\\runtime\\events\.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# 0) SANITIZE: remove UTF-8 BOM + literal "\n" / "\r\n" at file start (two chars, not newlines)
changed_sanitize = False
if src.startswith("\ufeff"):
    src = src.lstrip("\ufeff")
    changed_sanitize = True

while src.startswith("\\r\\n") or src.startswith("\\n") or src.startswith("\\r"):
    if src.startswith("\\r\\n"):
        src = src[4:]
    elif src.startswith("\\n") or src.startswith("\\r"):
        src = src[2:]
    changed_sanitize = True

HELPER = """# === ENSURE_NONE_REASON_V1 ===
def _ensure_none_reason(kind, payload):
    try:
        if kind == "strategy_result" and isinstance(payload, dict):
            if payload.get("returned") == "NONE":
                r = payload.get("reason")
                if r is None or str(r).strip() == "":
                    payload["reason"] = "NONE_NO_REASON"
    except Exception:
        pass
    return payload
# === END ENSURE_NONE_REASON_V1 ===
"""

def insert_helper_preserving_future(s: str) -> tuple[str,bool]:
    if "_ensure_none_reason" in s:
        return (s, False)

    n = len(s)
    i = 0

    # Skip initial comments/blank lines
    m0 = re.match(r"\A(?:(?:#.*)?\r?\n)*", s)
    i = m0.end() if m0 else 0

    # Optional module docstring
    if s[i:i+3] in ("'''", '"""'):
        q = s[i:i+3]
        j = s.find(q, i+3)
        if j != -1:
            j2 = j + 3
            while j2 < n and s[j2] in "\r\n":
                j2 += 1
            i = j2

    # Consume __future__ imports (must stay at top)
    pos = i
    while True:
        m_blank = re.match(r"(?:\s*\r?\n)+", s[pos:])
        if m_blank:
            pos += m_blank.end()
        m_fut = re.match(r"\s*from\s+__future__\s+import\s+[^\n]+\r?\n", s[pos:])
        if m_fut:
            pos += m_fut.end()
            continue
        break
    i = pos

    s2 = s[:i] + "\n" + HELPER + "\n" + s[i:]
    return (s2, True)

def patch_make_event(s: str) -> tuple[str,bool]:
    if "def make_event" not in s:
        return (s, False)

    lines = s.splitlines(True)
    out = []
    in_fn = False
    base_indent = ""
    indent_fn = ""
    injected = False
    changed = False

    for ln in lines:
        if (not in_fn) and re.match(r"^\s*def\s+make_event\b", ln):
            in_fn = True
            base_indent = re.match(r"^(\s*)", ln).group(1)
            indent_fn = base_indent + "    "
            injected = False
            out.append(ln)
            continue

        # leaving function: a new def/class at base indent, or a non-empty line with indentation <= base_indent
        if in_fn:
            if re.match(r"^\s*(def|class)\b", ln) and (len(re.match(r"^(\s*)", ln).group(1)) <= len(base_indent)):
                in_fn = False

        if in_fn and (not injected) and re.match(r"^" + re.escape(indent_fn) + r"return\b", ln):
            out.append(indent_fn + 'payload = _ensure_none_reason(kind, payload)\n')
            injected = True
            changed = True

        out.append(ln)

    return ("".join(out), changed)

src2, ch_helper = insert_helper_preserving_future(src)
src3, ch_patch  = patch_make_event(src2)

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(src3)

print("SANITIZE_CHANGED=", changed_sanitize)
print("HELPER_INSERTED=", ch_helper)
print("MAKE_EVENT_PATCHED=", ch_patch)
