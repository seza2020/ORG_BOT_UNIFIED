from __future__ import annotations
from pathlib import Path
import re, shutil, datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
ORCH = ROOT / r"tbot\runtime\orchestrator.py"

MARKER = "# HEARTBEAT_FILE_V1 (observability)"
ANCHOR_RE = re.compile(r"^\s*time\.sleep\(\s*sleep_sec\s*\)\s*$", re.M)

INJECT = r'''
        {marker}
        # Writes: <runroot>\state\heartbeat.json and <runroot>\state\pid.txt
        try:
            import os, json, tempfile
            from pathlib import Path as _P

            runroot = None
            try:
                mp = getattr(self, "meta_path", None) or getattr(self, "meta", None)
                if mp:
                    p = _P(str(mp)).resolve()
                    # expect ...\runroot\logs\meta.jsonl
                    if p.name.lower() == "meta.jsonl" and p.parent.name.lower() == "logs":
                        runroot = p.parent.parent
                    else:
                        # fallback: if ...\logs\something then parent of logs; else parent
                        runroot = p.parent.parent if p.parent.name.lower() == "logs" else p.parent
            except Exception:
                runroot = None

            if runroot is not None:
                state_dir = _P(runroot) / "state"
                state_dir.mkdir(parents=True, exist_ok=True)

                hb_path = state_dir / "heartbeat.json"
                pid_path = state_dir / "pid.txt"

                payload = {{
                    "ts_utc": __import__("datetime").datetime.utcnow().isoformat(timespec="seconds") + "Z",
                    "pid": os.getpid(),
                    "loop_i": int(i) if isinstance(i, int) or str(i).isdigit() else i,
                    "in_session": bool(getattr(st, "in_session", False)),
                    "pre_close": bool(getattr(st, "pre_close", False)),
                    "alpha_kill": bool(getattr(st, "alpha_kill", False)),
                    "portfolio_kill": bool(getattr(st, "portfolio_kill", False)),
                    "daily_r": float(getattr(st, "daily_r", 0.0) or 0.0),
                    "week_r": float(getattr(st, "week_r", 0.0) or 0.0),
                }}

                tmp = None
                try:
                    fd, tmp = tempfile.mkstemp(prefix="heartbeat_", suffix=".json", dir=str(state_dir))
                    with os.fdopen(fd, "w", encoding="utf-8") as f:
                        json.dump(payload, f)
                    os.replace(tmp, str(hb_path))
                finally:
                    try:
                        if tmp and os.path.exists(tmp):
                            os.remove(tmp)
                    except Exception:
                        pass

                try:
                    pid_path.write_text(str(os.getpid()), encoding="utf-8")
                except Exception:
                    pass
        except Exception:
            pass
'''.strip("\n")

def main():
    if not ORCH.exists():
        raise SystemExit(f"MISSING_ORCH={ORCH}")

    src = ORCH.read_text(encoding="utf-8", errors="strict")

    # If marker already present, do nothing
    if re.search(r"^\s*#\s*HEARTBEAT_FILE_V1\b", src, re.M):
        print("ALREADY_PRESENT=1")
        return

    m = ANCHOR_RE.search(src)
    if not m:
        raise SystemExit("ANCHOR_NOT_FOUND: cannot find line 'time.sleep(sleep_sec)'")

    # Backup
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    bak_dir = ROOT / "logs" / "ops" / "patches" / f"HEARTBEAT_FILE_V1_{stamp}"
    bak_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ORCH, bak_dir / "orchestrator.py")

    inject_text = INJECT.format(marker=MARKER)

    # Insert right BEFORE time.sleep(sleep_sec) to ensure it runs every loop
    start = m.start()
    out = src[:start] + inject_text + "\n" + src[start:]

    # Postcheck
    if not re.search(r"^\s*#\s*HEARTBEAT_FILE_V1\b", out, re.M):
        raise SystemExit("POSTCHECK_FAIL: marker missing after injection")

    ORCH.write_text(out, encoding="utf-8", newline="\n")
    print("PATCH_APPLIED=1")
    print(f"BKP_DIR={bak_dir}")

if __name__ == "__main__":
    main()
