import os, re, sys

path = r"C:\alpaca-bot\ORG_BOT_UNIFIED\code\tbot\runtime\events.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

HELPER = '''
# === ENSURE_NONE_REASON_V1 ===
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
'''.lstrip()

def insert_helper_preserving_future(s: str) -> str:
    if "_ensure_none_reason" in s:
        return s

    # Keep shebang/encoding + module docstring at top, then future imports, then insert helper.
    # 1) Detect module docstring
    i = 0
    n = len(s)

    # Skip initial comments/blank lines
    m0 = re.match(r'\\A(?:(?:#.*)?\\r?\\n)*', s)
    i = m0.end() if m0 else 0

    # Optional module docstring
    doc_end = None
    if s[i:i+3] in ("'''", '"""'):
        q = s[i:i+3]
        j = s.find(q, i+3)
        if j != -1:
            doc_end = j+3
            # include trailing newline
            k = doc_end
            while k < n and s[k] in "\\r\\n":
                k += 1
            i = k

    # 2) Consume future imports block (must remain at top)
    # Allow blank lines between them
    fut_pat = re.compile(r'^(\\s*from\\s+__future__\\s+import\\s+[^\\n]+\\n)+', re.M)
    m = fut_pat.match(s, i)
    if m:
        i = m.end()

    # Insert helper at i
    return s[:i] + "\\n" + HELPER + "\\n" + s[i:]

src2 = insert_helper_preserving_future(src)

def patch_make_event_or_emit(s: str) -> tuple[str,bool,str]:
    changed = False

    # Prefer make_event(kind=..., payload=...)
    if "def make_event" in s:
        # Insert: payload = _ensure_none_reason(kind, payload) before Event(...) construction/return
        # Best-effort: find inside make_event block the first 'return ' line and inject just before it.
        lines = s.splitlines(True)
        out = []
        in_fn = False
        indent = ""
        injected = False
        for ln in lines:
            if (not in_fn) and re.match(r'^\\s*def\\s+make_event\\b', ln):
                in_fn = True
                indent = re.match(r'^(\\s*)', ln).group(1) + "    "
                injected = False
                out.append(ln)
                continue

            if in_fn and (not injected) and re.match(r'^' + re.escape(indent[:-4]) + r'\\S', ln):
                # function ended without finding return
                in_fn = False

            if in_fn and (not injected) and re.match(r'^' + re.escape(indent) + r'return\\b', ln):
                out.append(indent + 'payload = _ensure_none_reason(kind, payload)\\n')
                injected = True
                changed = True

            out.append(ln)

        return ("".join(out), changed, "make_event")

    # Fallback: patch emit(kind, payload) style if exists
    if re.search(r'\\bdef\\s+emit\\b', s):
        # inject near start of emit()
        lines = s.splitlines(True)
        out=[]
        in_fn=False
        indent=""
        injected=False
        for ln in lines:
            if (not in_fn) and re.match(r'^\\s*def\\s+emit\\b', ln):
                in_fn=True
                indent = re.match(r'^(\\s*)', ln).group(1) + "    "
                injected=False
                out.append(ln)
                continue
            if in_fn and (not injected) and re.match(r'^' + re.escape(indent) + r'\\S', ln):
                # first real statement line
                out.append(indent + 'payload = _ensure_none_reason(kind, payload)\\n')
                injected=True
                changed=True
            # detect end
            if in_fn and re.match(r'^' + re.escape(indent[:-4]) + r'\\S', ln) and not re.match(r'^\\s*(#|$)', ln):
                in_fn=False
            out.append(ln)
        return ("".join(out), changed, "emit")

    return (s, False, "none")

src3, changed, mode = patch_make_event_or_emit(src2)

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(src3)

print("PATCH_MODE=", mode)
print("PATCH_APPLIED=", changed)
