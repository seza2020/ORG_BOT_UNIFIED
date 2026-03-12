import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"orchestrator.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore")
if "ORCH_RISK_LEDGER_LIFECYCLE_B1_V1" in txt:
    print("SKIP: already patched (marker found)")
    raise SystemExit(0)

stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"ORCH_RISK_LEDGER_LIFECYCLE_B1_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"orchestrator.py")

anchor = 'ev = make_event(level="INFO", kind="heartbeat", payload=heartbeat)'
i = txt.find(anchor)
if i == -1:
    print("FAIL: heartbeat anchor not found")
    raise SystemExit(2)

hook = r'''
        # --- ORCH_RISK_LEDGER_LIFECYCLE_B1_V1 (observability-only) ---
        try:
            import os as _os, json as _json
            from tbot.runtime.risk_ledger import RiskLedger as _RiskLedger

            _rr = (_os.getenv("TBOT_RUNROOT") or "").strip() or "."
            _scope = str(_os.getenv("TBOT_ENV","") or "GLOBAL").strip() or "GLOBAL"
            _run_id = str(_os.getenv("TBOT_RUN_ID","") or "").strip() or ""

            _rl = _RiskLedger(runroot=_rr, scope=_scope)

            # Persistent lifecycle state (restart-safe within same day)
            _st_path = _os.path.join(_rr, "state", "risk_ledger_lifecycle.json")
            _os.makedirs(_os.path.dirname(_st_path), exist_ok=True)

            try:
                with open(_st_path, "r", encoding="utf-8") as _f:
                    _st = _json.load(_f) or {}
            except Exception:
                _st = {}

            _in_sess = bool(heartbeat.get("in_session", False))
            _prev_in_sess = _st.get("last_in_session", None)
            _started = bool(_st.get("run_started", False))

            if not _started:
                _rl.on_run_start(run_id=_run_id or None, note="live")
                _st["run_started"] = True

            if (_prev_in_sess is None):
                # first observation
                if _in_sess:
                    _rl.on_session_start(session="RTH", note="live")
            else:
                if (not bool(_prev_in_sess)) and _in_sess:
                    _rl.on_session_start(session="RTH", note="live")
                if bool(_prev_in_sess) and (not _in_sess):
                    _rl.on_session_end(session="RTH", note="live")

            # gate snapshot (best-effort; do not assume attributes exist)
            try:
                _plans_used = getattr(gate, "_plans_today", None)
                _max_plans = getattr(getattr(gate, "cfg", None), "max_plans_per_day", None)
                _plans_left = None
                if (_plans_used is not None) and (_max_plans is not None):
                    try:
                        _plans_left = int(_max_plans) - int(_plans_used)
                    except Exception:
                        _plans_left = None

                _risk_used = getattr(gate, "_risk_today", None)
                _max_day = getattr(getattr(gate, "cfg", None), "max_risk_per_day_usd", None)
                _risk_left = None
                if (_risk_used is not None) and (_max_day is not None):
                    try:
                        _risk_left = float(_max_day) - float(_risk_used)
                    except Exception:
                        _risk_left = None

                _cap_hit = False
                try:
                    if (_plans_left is not None) and (_plans_left <= 0):
                        _cap_hit = True
                    if (_risk_left is not None) and (_risk_left <= 0):
                        _cap_hit = True
                except Exception:
                    pass

                _rl.on_gate_snapshot(
                    plans_used=_plans_used,
                    plans_left=_plans_left,
                    risk_used_usd=_risk_used,
                    risk_left_usd=_risk_left,
                    cooldown_left_sec=None,
                    cap_hit=bool(_cap_hit),
                    cap_usd=float(_max_day) if _max_day is not None else None,
                    note="live",
                )
            except Exception:
                pass

            _st["last_in_session"] = bool(_in_sess)
            try:
                with open(_st_path, "w", encoding="utf-8") as _f:
                    _f.write(_json.dumps(_st, ensure_ascii=False))
            except Exception:
                pass
        except Exception:
            pass
        # --- /ORCH_RISK_LEDGER_LIFECYCLE_B1_V1 ---
'''

txt2 = txt[:i] + hook + txt[i:]
path.write_text(txt2, encoding="utf-8")
print("PATCHED:", path)
print("BACKUP_DIR:", bak)
