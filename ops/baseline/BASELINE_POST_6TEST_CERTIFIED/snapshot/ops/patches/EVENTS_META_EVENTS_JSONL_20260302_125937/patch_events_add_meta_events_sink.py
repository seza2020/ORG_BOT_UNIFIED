import os, re, json

path = os.environ["TBOT_PATCH_TARGET"]
with open(path, "r", encoding="utf-8") as f:
    src = f.read()

MARK = "## META_EVENTS_JSONL_SINK_V1"

helper = r'''
''' + MARK + r'''
import os as _me_os, json as _me_json, time as _me_time

def _me_append(kind: str, ev):
    try:
        # Resolve logdir/runroot
        logdir = (_me_os.getenv("TBOT_LOGDIR") or "").strip()
        if not logdir:
            rr = (_me_os.getenv("TBOT_RUNROOT") or _me_os.getenv("TBOT_RUNTIME") or "").strip()
            if rr:
                logdir = _me_os.path.join(rr, "logs")
        if not logdir:
            return

        _me_os.makedirs(logdir, exist_ok=True)
        outp = _me_os.path.join(logdir, "meta_events.jsonl")

        rec = None
        if isinstance(ev, dict):
            rec = ev
        else:
            # best-effort: common attrs
            d = getattr(ev, "__dict__", None)
            if isinstance(d, dict):
                rec = dict(d)

        if not isinstance(rec, dict):
            return

        rec2 = dict(rec)
        rec2["_sink"] = "meta_events"
        rec2["_sink_ts"] = _me_time.time()
        rec2["_kind"] = kind

        with open(outp, "a", encoding="utf-8", newline="\n") as w:
            w.write(_me_json.dumps(rec2, ensure_ascii=False) + "\n")
    except Exception:
        pass
''' + "\n"

if MARK not in src:
    # insert helper after top imports block (safe)
    m = list(re.finditer(r"(?m)^(from\s+\S+\s+import\s+.+|import\s+\S+.*)\s*$", src))
    if m:
        insert_at = m[-1].end()
        src = src[:insert_at] + "\n\n" + helper + src[insert_at:]
    else:
        src = helper + src

# Patch make_event: append only strategy_result
# We inject just before the first "return" inside make_event.
mm = re.search(r"(?ms)^def\s+make_event\s*\(.*?\):\s*\n(.*?)(?=^\S)", src)
if not mm:
    raise SystemExit("make_event not found")

block = mm.group(0)

if "_me_append(" not in block:
    # Find first return line inside make_event block
    rret = re.search(r"(?m)^\s+return\s+", block)
    if not rret:
        raise SystemExit("make_event: no return found")
    ins = r'''
    # META_EVENTS_JSONL: persist strategy_result to machine-readable log
    try:
        if kind == "strategy_result":
            _me_append(kind, ev)
    except Exception:
        pass

'''
    block2 = block[:rret.start()] + ins + block[rret.start():]
    src = src.replace(block, block2, 1)

with open(path, "w", encoding="utf-8", newline="") as f:
    f.write(src)

print("PATCH_OK")
