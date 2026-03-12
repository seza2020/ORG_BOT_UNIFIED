import os, re, sys

path = os.environ["TBOT_PATCH_TARGET"]

with open(path, "r", encoding="utf-8") as f:
    src = f.read()

MARK = "# === META_EVENTS_SINK_V1 ==="

if MARK in src:
    print("ALREADY_PATCHED")
    sys.exit(0)

HELPER = f"""
{MARK}
import os as _me_os, json as _me_json, time as _me_time

def _me_append_strategy_result(payload):
    try:
        logdir = (_me_os.getenv("TBOT_LOGDIR") or "").strip()
        if not logdir:
            rr = (_me_os.getenv("TBOT_RUNROOT") or _me_os.getenv("TBOT_RUNTIME") or "").strip()
            if rr:
                logdir = _me_os.path.join(rr, "logs")
        if not logdir:
            return

        _me_os.makedirs(logdir, exist_ok=True)
        outp = _me_os.path.join(logdir, "meta_events.jsonl")

        rec = {{
            "ts": _me_time.time(),
            "kind": "strategy_result",
            "payload": payload,
        }}

        with open(outp, "a", encoding="utf-8", newline="\\n") as w:
            w.write(_me_json.dumps(rec, ensure_ascii=False) + "\\n")
    except Exception:
        pass
"""

# Insert helper after imports
imports = list(re.finditer(r"(?m)^(from\s+\S+\s+import\s+.+|import\s+\S+.*)\s*$", src))
if imports:
    insert_at = imports[-1].end()
    src = src[:insert_at] + "\n\n" + HELPER + "\n" + src[insert_at:]
else:
    src = HELPER + "\n" + src

# Now patch make_event body
pattern = r"def\s+make_event\s*\([^)]*\)\s*->\s*Event:"
m = re.search(pattern, src)
if not m:
    print("make_event signature not found")
    sys.exit(1)

start = m.end()
body_start = src.find(":", m.start()) + 1

# find first return inside make_event
block = src[m.start():]
ret = re.search(r"\n\s+return\s+", block)
if not ret:
    print("return not found inside make_event")
    sys.exit(1)

ret_pos = m.start() + ret.start()

inject = """
    # META_EVENTS_SINK
    try:
        if kind == "strategy_result":
            _me_append_strategy_result(payload)
    except Exception:
        pass

"""

src = src[:ret_pos] + inject + src[ret_pos:]

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(src)

print("PATCH_OK")
