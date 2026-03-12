import subprocess
import multiprocessing
import traceback
import os
import sys
from datetime import datetime

LOG=r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\spawn_trace.log"

def log(msg):
    with open(LOG,"a",encoding="utf8") as f:
        f.write(f"{datetime.now()} | {msg}\n")

# --- subprocess hook ---

_real_popen=subprocess.Popen

def traced_popen(*a,**k):
    log("SUBPROCESS POPEN CALLED")
    log("ARGS="+str(a))
    log("KW="+str(k))
    log("STACK:\n"+ "".join(traceback.format_stack()))
    return _real_popen(*a,**k)

subprocess.Popen=traced_popen

# --- multiprocessing hook ---

_real_start=multiprocessing.Process.start

def traced_start(self,*a,**k):
    log("MULTIPROCESS START")
    log("PROCESS="+str(self))
    log("STACK:\n"+ "".join(traceback.format_stack()))
    return _real_start(self,*a,**k)

multiprocessing.Process.start=traced_start

log("SPAWN TRACER ACTIVE")

import runpy
runpy.run_module("tbot.main",run_name="__main__")
