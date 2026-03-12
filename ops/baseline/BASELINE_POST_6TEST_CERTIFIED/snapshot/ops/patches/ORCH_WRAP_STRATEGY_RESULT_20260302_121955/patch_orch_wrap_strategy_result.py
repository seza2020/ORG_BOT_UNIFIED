# Patch orchestrator.py: wrap payload of strategy_result emits with _ensure_none_reason(...)
# Fail-closed: if compile fails, restore original.
import io, os, re, sys

path = r"C:\alpaca-bot\ORG_BOT_UNIFIED\code\tbot\runtime\orchestrator.py"
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

HELPER = r'''
# === ENSURE_NONE_REASON_V1 ===
def _ensure_none_reason(rec):
    try:
        if isinstance(rec, dict):
            if rec.get("returned") == "NONE":
                r = rec.get("reason")
                if r is None or str(r).strip() == "":
                    rec["reason"] = "NONE_NO_REASON"
    except Exception:
        pass
    return rec
# === END ENSURE_NONE_REASON_V1 ===

'''.lstrip()

if "_ensure_none_reason" not in src:
    # Insert helper after initial imports block (best-effort)
    m = re.search(r"(?s)\\A(.*?\\n)(\\s*\\n)", src)
    if m:
        insert_at = m.end(1)  # after first line group (safe-ish)
        src = src[:insert_at] + "\\n" + HELPER + src[insert_at:]
    else:
        src = HELPER + src

def find_call_span(s: str, start: int) -> tuple[int,int]:
    # Find the span of a Python call starting at 'start' (index at 'e' of emit)
    # We scan forward to the first '(' then balance parentheses until close.
    i = start
    n = len(s)
    while i < n and s[i] != "(":
        i += 1
    if i >= n: 
        return (-1,-1)
    depth = 0
    j = i
    in_str = None
    esc = False
    while j < n:
        ch = s[j]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
        else:
            if ch in ("'", '"'):
                in_str = ch
            elif ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    return (start, j+1)
        j += 1
    return (-1,-1)

def wrap_strategy_result_payload(call_text: str) -> str:
    # If already wrapped, no-op
    if "_ensure_none_reason" in call_text:
        return call_text

    # Must contain 'strategy_result' string literal
    if ("'strategy_result'" not in call_text) and ('"strategy_result"' not in call_text):
        return call_text

    # Find the strategy_result literal occurrence
    idx = call_text.find("'strategy_result'")
    lit = "'strategy_result'"
    if idx < 0:
        idx = call_text.find('"strategy_result"')
        lit = '"strategy_result"'
    if idx < 0:
        return call_text

    # Find comma after the literal at top-level of the call args
    # We'll scan from end of literal to find first comma not inside strings/parens/brackets/braces.
    k = idx + len(lit)
    depth_p = depth_b = depth_c = 0
    in_str = None
    esc = False
    comma_pos = -1
    while k < len(call_text):
        ch = call_text[k]
        if in_str:
            if esc:
                esc = False
            elif ch == "\\":
                esc = True
            elif ch == in_str:
                in_str = None
        else:
            if ch in ("'", '"'):
                in_str = ch
            elif ch == "(":
                depth_p += 1
            elif ch == ")":
                depth_p = max(0, depth_p-1)
            elif ch == "[":
                depth_b += 1
            elif ch == "]":
                depth_b = max(0, depth_b-1)
            elif ch == "{":
                depth_c += 1
            elif ch == "}":
                depth_c = max(0, depth_c-1)
            elif ch == "," and depth_p == 0 and depth_b == 0 and depth_c == 0:
                comma_pos = k
                break
        k += 1
    if comma_pos < 0:
        return call_text

    # Payload expr is from comma_pos+1 to the final ')' of the call
    # We'll wrap exactly that slice.
    before = call_text[:comma_pos+1]
    payload = call_text[comma_pos+1:].strip()

    # Defensive: if payload begins with "_ensure_none_reason", skip
    if payload.startswith("_ensure_none_reason"):
        return call_text

    return before + " _ensure_none_reason(" + payload + ")"

# Locate candidate emit calls containing strategy_result
# We search for "strategy_result" then walk backwards to nearest "emit"
out = []
i = 0
changed = False
while True:
    j = src.find("strategy_result", i)
    if j < 0:
        break
    # walk backwards up to 200 chars to find an emit token on same vicinity
    k = max(0, j-200)
    window = src[k:j+200]
    m = re.search(r"\\bemit\\b|\\bemit_event\\b|\\bevents\\.emit\\b", window)
    if not m:
        i = j + 1
        continue
    emit_pos = k + m.start()
    span = find_call_span(src, emit_pos)
    if span == (-1,-1):
        i = j + 1
        continue
    call = src[span[0]:span[1]]
    new_call = wrap_strategy_result_payload(call)
    if new_call != call:
        src = src[:span[0]] + new_call + src[span[1]:]
        changed = True
        # shift i forward safely
        i = span[0] + len(new_call)
    else:
        i = span[1]

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(src)

print("PATCH_APPLIED=", changed)
