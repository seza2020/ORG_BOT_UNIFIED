import shutil, re
from pathlib import Path
from datetime import datetime

ROOT = Path(r"C:\alpaca-bot\org_bot")
path = ROOT/"tbot"/"runtime"/"orchestrator.py"
if not path.exists():
    raise SystemExit(f"ERROR: not found: {path}")

txt = path.read_text(encoding="utf-8", errors="ignore")

marker = "ORCH_RISK_LEDGER_GATE_SNAPSHOT_B1"
if marker in txt:
    print("SKIP: already patched:", marker)
    raise SystemExit(0)

needle = 'ev = make_event(level="INFO", kind="heartbeat", payload=heartbeat)'
i = txt.find(needle)
if i == -1:
    print("FAIL: heartbeat anchor not found")
    raise SystemExit(2)

# insert right after the heartbeat event creation line (after its newline)
line_end = txt.find("\n", i)
if line_end == -1:
    print("FAIL: could not find end of heartbeat line")
    raise SystemExit(3)
insert_pos = line_end + 1

block = r'''
        # --- ORCH_RISK_LEDGER_GATE_SNAPSHOT_B1 (observability-only) ---
        try:
            from tbot.runtime.risk_ledger import RiskLedger

            rr = (os.getenv("TBOT_RUNROOT") or "").strip() or "."
            _scope = str(os.getenv("TBOT_ENV", "") or "GLOBAL").strip() or "GLOBAL"
            _run_id = str(os.getenv("TBOT_RUN_ID","") or "")

            # Best-effort extraction of gate metrics (defensive: many builds differ)
            _plans_used = None
            _plans_left = None
            _risk_used = None
            _risk_left = None
            _cool_left = None
            _cap_hit = None
            _cap_usd = None

            # Try: gate object
            g = locals().get("gate", None)
            if g is not None:
                try:
                    _plans_used = getattr(g, "_plans_today", None)
                    _cap_usd = getattr(getattr(g, "cfg", None), "max_risk_per_day_usd", None)
                    if _cap_usd is None:
                        _cap_usd = getattr(getattr(g, "cfg", None), "max_risk_usd", None)
                except Exception:
                    pass
                try:
                    _risk_used = getattr(g, "_risk_today", None)
                except Exception:
                    pass
                try:
                    _cool_left = getattr(g, "_cooldown_left_sec", None)
                except Exception:
                    pass

            # Try: stats object
            stt = locals().get("stats", None)
            if stt is not None:
                try:
                    if _plans_used is None:
                        _plans_used = getattr(stt, "shadow_accept", None)
                except Exception:
                    pass

            # Try: args caps
            a = locals().get("args", None)
            if a is not None:
                try:
                    if _cap_usd is None:
                        _cap_usd = getattr(a, "gate_max_risk_per_day_usd", None)
                except Exception:
                    pass
                try:
                    _max_plans = getattr(a, "gate_max_plans_per_day", None)
                    if _max_plans is not None and _plans_used is not None:
                        _plans_left = int(_max_plans) - int(_plans_used)
                except Exception:
                    pass

            # Derive risk_left if possible
            try:
                if (_cap_usd is not None) and (_risk_used is not None):
                    _risk_left = float(_cap_usd) - float(_risk_used)
            except Exception:
                pass

            # Cap hit if possible
            try:
                if (_plans_left is not None) and (int(_plans_left) <= 0):
                    _cap_hit = True
            except Exception:
                pass
            try:
                if (_risk_left is not None) and (float(_risk_left) <= 0.0):
                    _cap_hit = True
            except Exception:
                pass

            _rl = RiskLedger(runroot=rr, scope=_scope)

            # Prefer lifecycle helper methods if present
            if hasattr(_rl, "on_gate_snapshot"):
                _rl.on_gate_snapshot(
                    day=_rl._day() if hasattr(_rl, "_day") else None,
                    scope=_scope,
                    run_id=_run_id,
                    plans_used=_plans_used,
                    plans_left=_plans_left,
                    risk_used_usd=_risk_used,
                    risk_left_usd=_risk_left,
                    cooldown_left_sec=_cool_left,
                    cap_hit=_cap_hit,
                    cap_usd=_cap_usd,
                )
            else:
                # fallback: emit_event if it exists
                if hasattr(_rl, "emit_event"):
                    _rl.emit_event(
                        "gate_snapshot",
                        day=_rl._day() if hasattr(_rl, "_day") else None,
                        scope=_scope,
                        run_id=_run_id,
                        plans_used=_plans_used,
                        plans_left=_plans_left,
                        risk_used_usd=_risk_used,
                        risk_left_usd=_risk_left,
                        cooldown_left_sec=_cool_left,
                        cap_hit=_cap_hit,
                        cap_usd=_cap_usd,
                    )
        except Exception:
            pass
        # --- /ORCH_RISK_LEDGER_GATE_SNAPSHOT_B1 ---
'''

# backup
stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
bak = ROOT/"logs"/"ops"/"patches"/f"ORCH_RISK_LEDGER_GATE_SNAPSHOT_B1_{stamp}"
bak.mkdir(parents=True, exist_ok=True)
shutil.copy2(path, bak/"orchestrator.py")

txt2 = txt[:insert_pos] + block + txt[insert_pos:]
path.write_text(txt2, encoding="utf-8")

print("PATCHED:", path)
print("BACKUP_DIR:", bak)
