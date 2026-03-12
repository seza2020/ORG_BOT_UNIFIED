# tbot/runtime/gate_state.py
# Persistent gate (meta-backed) for restart-safe daily limits
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, date
from typing import Any, Dict, Optional

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None  # type: ignore

_TZ_NAME = "America/Los_Angeles"

@dataclass(frozen=True)
class MetaStats:
    day: str
    boot: int
    shadow_plan: int
    shadow_accept: int
    shadow_reject: int
    fake_plans: int
    valid_accepts: int
    accepted_risk_usd: float

def _tz():
    if ZoneInfo is None:
        return None
    return ZoneInfo(_TZ_NAME)

def _parse_ts_to_pt(ts: str) -> datetime:
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    dt = datetime.fromisoformat(ts) if "T" in ts else datetime.strptime(ts, "%Y-%m-%d %H:%M:%S")
    tz = _tz()
    if dt.tzinfo is None:
        # naive => assume PT wall clock
        if tz is None:
            return dt
        return dt.replace(tzinfo=tz)
    if tz is None:
        return dt
    return dt.astimezone(tz)

def _today_pt() -> date:
    tz = _tz()
    if ZoneInfo is None or tz is None:
        return datetime.now().date()
    now_utc = datetime.utcnow().replace(tzinfo=ZoneInfo("UTC"))
    return now_utc.astimezone(tz).date()

def _get(d: Any, k: str, default=None):
    if isinstance(d, dict):
        return d.get(k, default)
    return getattr(d, k, default)

def is_fake_payload(payload: Any) -> bool:
    if not payload:
        return False
    reason = str(_get(payload, "reason", "") or "")
    if "forced_signal_test" in reason:
        return True
    try:
        e = float(_get(payload, "entry"))
        s = float(_get(payload, "stop"))
        t = float(_get(payload, "tp"))
        if abs(e - 100.0) < 1e-6 and abs(s - 99.0) < 1e-6 and abs(t - 102.0) < 1e-6:
            return True
    except Exception:
        return False
    return False

def meta_stats(meta_path: str, day_pt: Optional[date] = None) -> MetaStats:
    if day_pt is None:
        day_pt = _today_pt()

    boot = plan = acc = rej = fake = valid = 0
    risk_sum = 0.0

    if not os.path.exists(meta_path):
        return MetaStats(str(day_pt), 0, 0, 0, 0, 0, 0, 0.0)

    with open(meta_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                j = json.loads(line)
            except Exception:
                continue
            kind = j.get("kind")
            ts = j.get("ts")
            if not kind or not ts:
                continue
            try:
                t_pt = _parse_ts_to_pt(str(ts))
            except Exception:
                continue
            if t_pt.date() != day_pt:
                continue

            if kind == "boot":
                boot += 1
            elif kind == "shadow_plan":
                plan += 1
                if is_fake_payload(j.get("payload")):
                    fake += 1
            elif kind == "shadow_accept":
                acc += 1
                p = j.get("payload") or {}
                if is_fake_payload(p):
                    # do not consume cap for fake
                    continue
                valid += 1
                for rk in ("risk_usd", "riskUsd", "risk"):
                    if rk in p:
                        try:
                            risk_sum += float(p[rk])
                        except Exception:
                            pass
                        break
            elif kind == "shadow_reject":
                rej += 1

    return MetaStats(str(day_pt), boot, plan, acc, rej, fake, valid, float(risk_sum))

def _atomic_write_json(path: str, obj: Dict[str, Any]) -> None:
    tmp = path + ".tmp"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
    os.replace(tmp, path)

def apply_persistent_gate_limits(args: Any, root_dir: str, allow_fake_start: bool = False, day_pt: Optional[date] = None) -> MetaStats:
    if day_pt is None:
        day_pt = _today_pt()

    meta_path = os.path.join(root_dir, "logs", "meta.jsonl")
    st = meta_stats(meta_path, day_pt=day_pt)
    # --- TBOT_POLICY_LOCKS_V1 BEGIN ---
    import os as _os

    # ---- BOOT_GUARD_AUDIT_V1 (persistent + daily reset UTC) ----
    # Source of truth: <runroot>\state\boot_guard.json
    # Audit: <runroot>\logs\ops\BOOT_GUARD_AUDIT_YYYYMMDD.log
    from datetime import datetime, timezone
    from pathlib import Path as _P
    import json as _json

    _max_boots = int((_os.getenv("TBOT_MAX_BOOTS_PER_DAY","3") or "3").strip())
    _allow_over = (_os.getenv("TBOT_ALLOW_BOOT_OVERRUN","0") == "1")

    _runroot = _os.getenv("TBOT_RUNROOT") or _os.getenv("TBOT_RUNTIME")
    _rr = _P(str(_runroot)).resolve() if _runroot else None

    def _audit_line(rr, s):
        try:
            ops = rr / "logs" / "ops"
            ops.mkdir(parents=True, exist_ok=True)
            day = datetime.now(timezone.utc).date().isoformat().replace("-","")
            ap = ops / f"BOOT_GUARD_AUDIT_{day}.log"
            ap.write_text((ap.read_text(encoding="utf-8") if ap.exists() else "") + s + "\n", encoding="utf-8")
        except Exception:
            pass

    if _rr is not None:
        sd = _rr / "state"
        sd.mkdir(parents=True, exist_ok=True)
        bp = sd / "boot_guard.json"
        today = datetime.now(timezone.utc).date().isoformat()
        data = {"day": today, "boots": 0}
        # ---- BOOT_GUARD_UPTIME_V1 BEGIN ----
        # If previous start crashed quickly, do not count it as a boot.
        # This prevents "attempt-based" brick during debugging / flaky startups.
        _min_up = int((_os.getenv("TBOT_BOOT_MIN_UPTIME_SEC","90") or "90").strip())
        _now_ts = int(datetime.now(timezone.utc).timestamp())
        try:
            _prev_ts = int(data.get("last_start_utc", 0) or 0)
            _prev_pid = int(data.get("last_pid", 0) or 0)
            # If we are starting again too soon, rollback the previous boot consumption (best-effort)
            if _prev_ts > 0 and (_now_ts - _prev_ts) < _min_up and int(data.get("boots",0) or 0) > 0:
                data["boots"] = int(data.get("boots",0) or 0) - 1
                _audit_line(_rr, f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} ROLLBACK quick_restart dt={_now_ts-_prev_ts}s prev_pid={_prev_pid} min_uptime={_min_up}s boots_now={data['boots']}")
        except Exception:
            pass
        data["last_start_utc"] = _now_ts
        try:
            data["last_pid"] = int(_os.getpid())
        except Exception:
            pass
        # ---- BOOT_GUARD_UPTIME_V1 END ----
        try:
            if bp.exists():
                data = _json.loads(bp.read_text(encoding="utf-8") or "{}") or data
        except Exception:
            data = {"day": today, "boots": 0}
        # ---- BOOT_GUARD_UPTIME_V1 BEGIN ----
        # If previous start crashed quickly, do not count it as a boot.
        # This prevents "attempt-based" brick during debugging / flaky startups.
        _min_up = int((_os.getenv("TBOT_BOOT_MIN_UPTIME_SEC","90") or "90").strip())
        _now_ts = int(datetime.now(timezone.utc).timestamp())
        try:
            _prev_ts = int(data.get("last_start_utc", 0) or 0)
            _prev_pid = int(data.get("last_pid", 0) or 0)
            # If we are starting again too soon, rollback the previous boot consumption (best-effort)
            if _prev_ts > 0 and (_now_ts - _prev_ts) < _min_up and int(data.get("boots",0) or 0) > 0:
                data["boots"] = int(data.get("boots",0) or 0) - 1
                _audit_line(_rr, f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} ROLLBACK quick_restart dt={_now_ts-_prev_ts}s prev_pid={_prev_pid} min_uptime={_min_up}s boots_now={data['boots']}")
        except Exception:
            pass
        data["last_start_utc"] = _now_ts
        try:
            data["last_pid"] = int(_os.getpid())
        except Exception:
            pass
        # ---- BOOT_GUARD_UPTIME_V1 END ----

        if data.get("day") != today:
            _audit_line(_rr, f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} RESET day={data.get('day')} -> {today} boots=0")
            data = {"day": today, "boots": 0}
        # ---- BOOT_GUARD_UPTIME_V1 BEGIN ----
        # If previous start crashed quickly, do not count it as a boot.
        # This prevents "attempt-based" brick during debugging / flaky startups.
        _min_up = int((_os.getenv("TBOT_BOOT_MIN_UPTIME_SEC","90") or "90").strip())
        _now_ts = int(datetime.now(timezone.utc).timestamp())
        try:
            _prev_ts = int(data.get("last_start_utc", 0) or 0)
            _prev_pid = int(data.get("last_pid", 0) or 0)
            # If we are starting again too soon, rollback the previous boot consumption (best-effort)
            if _prev_ts > 0 and (_now_ts - _prev_ts) < _min_up and int(data.get("boots",0) or 0) > 0:
                data["boots"] = int(data.get("boots",0) or 0) - 1
                _audit_line(_rr, f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} ROLLBACK quick_restart dt={_now_ts-_prev_ts}s prev_pid={_prev_pid} min_uptime={_min_up}s boots_now={data['boots']}")
        except Exception:
            pass
        data["last_start_utc"] = _now_ts
        try:
            data["last_pid"] = int(_os.getpid())
        except Exception:
            pass
        # ---- BOOT_GUARD_UPTIME_V1 END ----

                # --- BOOT_GUARD_NO_INFLATE_V1 BEGIN ---
        # Compute would_boot first; do not inflate boots on HARD_STOP.
        try:
            _cur_boot = int(data.get("boots", 0) or 0)
        except Exception:
            _cur_boot = 0
        would_boot = _cur_boot + 1

        if would_boot >= _max_boots and not _allow_over:
            _audit_line(_rr, f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} HARD_STOP would_boot={would_boot} max_boots={_max_boots} allow_over={int(_allow_over)} runroot={str(_rr)} path={str(bp)}")
            raise SystemExit(f"[BOOT_GUARD] HARD_STOP: boots_today={would_boot} >= max_boots={_max_boots}. Day non-auditable; refusing to start. runroot={str(_rr)} path={str(bp)}")

        data["boots"] = would_boot
        # --- BOOT_GUARD_NO_INFLATE_V1 END ---

        try:
            bp.write_text(_json.dumps(data), encoding="utf-8")
        except Exception:
            pass

        try:
            st.boot = int(data["boots"])
        except Exception:
            pass

        _audit_line(_rr, f"{datetime.now(timezone.utc).isoformat(timespec='seconds')} BOOT boots_today={data['boots']} max_boots={_max_boots} allow_over={int(_allow_over)}")
        # BOOT_GUARD_NO_INFLATE_V1: check moved before write
# ---- END BOOT_GUARD_AUDIT_V1 ----

    _min_cd = int((_os.getenv("TBOT_MIN_COOLDOWN_SEC","20") or "20").strip())
    _allow_cd0 = (_os.getenv("TBOT_ALLOW_COOLDOWN_0","0") == "1")
    if hasattr(args, "gate_cooldown_sec"):
        _cd = int(getattr(args, "gate_cooldown_sec"))
        if _cd == 0 and not _allow_cd0:
            raise SystemExit("[COOLDOWN] HARD_STOP: gate_cooldown_sec=0 is not allowed for tuning (set TBOT_ALLOW_COOLDOWN_0=1 only for research).")
        if _cd < _min_cd and _os.getenv("TBOT_ALLOW_LOW_COOLDOWN","0") != "1":
            raise SystemExit(f"[COOLDOWN] HARD_STOP: gate_cooldown_sec={_cd} < min={_min_cd}.")
    # --- TBOT_POLICY_LOCKS_V1 END ---
    state_path = os.path.join(root_dir, "logs", "ops", f"gate_state_{day_pt.strftime('%Y%m%d')}.json")
    _atomic_write_json(state_path, {
        "day": st.day,
        "tz": _TZ_NAME,
        "boot": st.boot,
        "shadow_plan": st.shadow_plan,
        "shadow_accept": st.shadow_accept,
        "shadow_reject": st.shadow_reject,
        "fake_plans": st.fake_plans,
        "valid_accepts": st.valid_accepts,
        "accepted_risk_usd": st.accepted_risk_usd,
        "note": "persistent-cap-v1 meta-backed",
    })

    if st.fake_plans > 0 and not allow_fake_start:
        raise SystemExit(f"[PERSIST_CAP] HARD_STOP: fake_plans={st.fake_plans} detected today. Refusing to start.")

    if hasattr(args, "gate_max_plans_per_day"):
        orig = int(getattr(args, "gate_max_plans_per_day"))
        if st.valid_accepts > orig:
            raise SystemExit(f"[PERSIST_CAP] HARD_STOP: meta valid_accepts={st.valid_accepts} > orig_cap={orig}. Cap integrity broken.")
        rem = max(0, orig - int(st.valid_accepts))
        setattr(args, "gate_max_plans_per_day", rem)
        setattr(args, "_gate_persist_orig_cap", orig)
        setattr(args, "_gate_persist_remaining_cap", rem)
        print(f"[PERSIST_CAP] day={st.day} valid_accepts={st.valid_accepts} orig_cap={orig} effective_cap={rem}")
        if rem <= 0:
            raise SystemExit(f"[PERSIST_CAP] CAP_REACHED: valid_accepts={st.valid_accepts} orig_cap={orig}. Exiting.")
    # P0_2_RISK_BUDGET_SPLIT_V1
    # IMPORTANT: gate_max_risk_usd is a per-trade cap (legacy). Do NOT mutate it across restarts.
    # If a daily budget is configured, we may compute an effective remaining daily budget.
    if hasattr(args, "gate_max_risk_per_day_usd") and getattr(args, "gate_max_risk_per_day_usd") is not None and st.accepted_risk_usd > 0:
        try:
            orig_day = float(getattr(args, "gate_max_risk_per_day_usd"))
            rem_day = max(0.0, orig_day - float(st.accepted_risk_usd))
            setattr(args, "gate_max_risk_per_day_usd", rem_day)
            print(f"[PERSIST_CAP] risk_used={st.accepted_risk_usd:.2f} orig_day_budget={orig_day:.2f} effective_day_budget={rem_day:.2f}")
        except Exception:
            pass
    # P0_2_GATE_STATE_NO_MUTATE_PER_TRADE removed per-trade cap mutation across restarts (legacy gate_max_risk_usd)
        except Exception:
            pass

    return st




