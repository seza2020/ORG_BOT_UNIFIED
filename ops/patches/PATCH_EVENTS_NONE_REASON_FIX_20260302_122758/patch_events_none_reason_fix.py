import re, sys

path = r"C:\alpaca-bot\ORG_BOT_UNIFIED\code\tbot\runtime\events.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

# --- 0) SANITIZE: remove literal "\n" / "\r\n" at file start (these are two characters, not newlines) ---
# Also drop UTF-8 BOM if present.
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

HELPER = (
"# === ENSURE_NONE_REASON_V1 ===\\n"
"def _ensure_none_reason(kind, payload):\\n"
"    try:\\n"
"        if kind == \\"strategy_result\\" and isinstance(payload, dict):\\n"
"            if payload.get(\\"returned\\") == \\"NONE\\":\\n"
"                r = payload.get(\\"reason\\")\\n"
"                if r is None or str(r).strip() == \\"\\":\\n"
"                    payload[\\"reason\\"] = \\"NONE_NO_REASON\\"\\n"
"    except Exception:\\n"
"        pass\\n"
"    return payload\\n"
"# === END ENSURE_NONE_REASON_V1 ===\\n"
)

def insert_helper_preserving_future(s: str) -> tuple[str,bool]:
    if "_ensure_none_reason" in s:
        return (s, False)

    n = len(s)
    i = 0

    # Skip initial comments/blank lines
    m0 = re.match(r'\\A(?:(?:#.*)?\\r?\\n)*', s)
    i = m0.end() if m0 else 0

    # Optional module docstring
    if s[i:i+3] in ("'''", '"""'):
        q = s[i:i+3]
        j = s.find(q, i+3)
        if j != -1:
            j2 = j + 3
            # consume trailing newlines
            while j2 < n and s[j2] in "\\r\\n":
                j2 += 1
            i = j2

    # Consume any __future__ imports block (must stay at top)
    # We allow blank lines between future imports.
    fut_lines = []
    pos = i
    while True:
        # skip blank lines
        m_blank = re.match(r'(?:\\s*\\r?\\n)+', s[pos:])
        if m_blank:
            pos += m_blank.end()
        m_fut = re.match(r'\\s*from\\s+__future__\\s+import\\s+[^\\n]+\\r?\\n', s[pos:])
        if m_fut:
            fut_lines.append((pos, pos + m_fut.end()))
            pos += m_fut.end()
            continue
        break
    if fut_lines:
        i = fut_lines[-1][1]

    s2 = s[:i] + "\\n" + HELPER + "\\n" + s[i:]
    return (s2, True)

def patch_make_event(s: str) -> tuple[str,bool]:
    if "def make_event" not in s:
        return (s, False)

    lines = s.splitlines(True)
    out = []
    in_fn = False
    indent_fn = ""
    injected = False
    changed = False

    for ln in lines:
        if (not in_fn) and re.match(r'^\\s*def\\s+make_event\\b', ln):
            in_fn = True
            base = re.match(r'^(\\s*)', ln).group(1)
            indent_fn = base + "    "
            injected = False
            out.append(ln)
            continue

        # detect leaving function: a non-empty, non-comment line at indentation <= base
        if in_fn:
            # if this line starts at base indent (or less) AND is not blank/comment, then function ended
            if re.match(r'^\\S', ln) or re.match(r'^\\s*def\\b', ln) or re.match(r'^\\s*class\\b', ln):
                in_fn = False

        if in_fn and (not injected) and re.match(r'^' + re.escape(indent_fn) + r'return\\b', ln):
            out.append(indent_fn + 'payload = _ensure_none_reason(kind, payload)\\n')
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
