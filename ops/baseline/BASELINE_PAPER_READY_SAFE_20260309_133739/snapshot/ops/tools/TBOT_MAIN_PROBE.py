import os
import sys
import time
import runpy
import traceback
from pathlib import Path

ROOT = Path(r"C:\alpaca-bot\ORG_BOT_UNIFIED")
LOGS = ROOT / "runtime" / "paper" / "logs"
LOGS.mkdir(parents=True, exist_ok=True)

PROBE_LOG = LOGS / "main_probe.log"
TRACE_LOG = LOGS / "main_trace.log"

def wl(path, msg):
    with open(path, "a", encoding="utf-8") as f:
        f.write(msg + "\n")

def now():
    return time.strftime("%Y-%m-%d %H:%M:%S")

try:
    if TRACE_LOG.exists():
        TRACE_LOG.unlink()
except Exception:
    pass

module = "tbot.main"
argv = ["tbot.main"] + sys.argv[1:]

wl(PROBE_LOG, f"{now()} | probe_start module={module} argv={argv}")

target_suffix = str(Path("tbot") / "main.py")
max_lines = 4000
trace_count = {"n": 0}

def tracer(frame, event, arg):
    try:
        code = frame.f_code
        filename = str(code.co_filename)
        if filename.endswith(target_suffix) and event == "line":
            if trace_count["n"] < max_lines:
                trace_count["n"] += 1
                wl(TRACE_LOG, f"{now()} | line={frame.f_lineno} func={code.co_name}")
    except Exception:
        pass
    return tracer

sys.argv = argv

try:
    sys.settrace(tracer)
    t0 = time.time()
    runpy.run_module(module, run_name="__main__")
    dt = time.time() - t0
    wl(PROBE_LOG, f"{now()} | module_returned elapsed_sec={dt:.3f}")
except SystemExit as e:
    dt = time.time() - t0
    code = e.code if hasattr(e, "code") else None
    wl(PROBE_LOG, f"{now()} | system_exit code={code} elapsed_sec={dt:.3f}")
    raise
except Exception:
    dt = time.time() - t0
    wl(PROBE_LOG, f"{now()} | exception elapsed_sec={dt:.3f}")
    wl(PROBE_LOG, traceback.format_exc())
    raise
finally:
    sys.settrace(None)
    wl(PROBE_LOG, f"{now()} | probe_stop traced_lines={trace_count['n']}")
