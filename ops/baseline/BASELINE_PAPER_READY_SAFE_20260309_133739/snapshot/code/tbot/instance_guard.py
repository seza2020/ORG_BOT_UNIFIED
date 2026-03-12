import os
import sys
import time

LOCK_FILE = r"C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\state\locks\tbot_instance.lock"

def acquire():
    if os.path.exists(LOCK_FILE):
        try:
            with open(LOCK_FILE) as f:
                pid = int(f.read().strip())
            if pid and pid != os.getpid():
                try:
                    os.kill(pid, 0)
                    print("TBOT_INSTANCE_ALREADY_RUNNING PID=", pid)
                    sys.exit(100)
                except:
                    pass
        except:
            pass

    with open(LOCK_FILE,"w") as f:
        f.write(str(os.getpid()))

def release():
    try:
        if os.path.exists(LOCK_FILE):
            os.remove(LOCK_FILE)
    except:
        pass
