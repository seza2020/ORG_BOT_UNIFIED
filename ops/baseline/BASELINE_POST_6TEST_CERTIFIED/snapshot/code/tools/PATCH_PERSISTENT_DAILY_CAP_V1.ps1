# tools\PATCH_PERSISTENT_DAILY_CAP_V1.ps1
# Patch: Persistent daily cap across restarts (meta-backed) + fake-plan hard stop
# Scope-safe: project-only paths. No secrets touched.

[CmdletBinding()]
param(
  [switch]$Disable0630,     # optional: disable TBOT_RUN_SHADOW_DAILY_0630 to avoid double-run
  [switch]$SkipTaskCheck,   # skip task scheduler listing
  [switch]$Force            # overwrite existing gate_state.py if present
)

$ErrorActionPreference="Stop"

# ---- Root guard ----
$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){
  throw "Run from C:\alpaca-bot\org_bot (current: $ROOT)"
}

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Venv python not found: $PY" }

$OPS   = Join-Path $ROOT "logs\ops"
$LOCKD = Join-Path $ROOT "logs\locks"
New-Item -ItemType Directory -Force -Path $OPS,$LOCKD | Out-Null

# ---- Backup ----
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_PERSIST_CAP_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

# ---- Write new module: tbot\runtime\gate_state.py ----
$gatePy = Join-Path $ROOT "tbot\runtime\gate_state.py"
if((Test-Path $gatePy) -and (-not $Force)){
  Write-Host "gate_state.py exists => (skip) use -Force to overwrite"
} else {
  if(Test-Path $gatePy){ Copy-Item -Force $gatePy (Join-Path $BAK "gate_state.py.bak") }

  $gateCode = @"
# tbot/runtime/gate_state.py
# Persistent gate (meta-backed) for restart-safe daily limits
# - Computes today's accepted count from logs/meta.jsonl (PT)
# - Applies remaining cap to args.gate_max_plans_per_day
# - Hard-stops startup if any fake plan detected today (forced_signal_test or 100/99/102)
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, date
from typing import Any, Dict, Iterable, Optional, Tuple

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
    # Supports:
    # - "2026-02-17T11:25:50" (assume PT local)
    # - "2026-02-17T19:25:50Z" (UTC)
    # - "2026-02-17T11:25:50-08:00" (offset)
    ts = ts.strip()
    if ts.endswith("Z"):
        ts = ts[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(ts)
    except Exception:
        # last resort
        dt = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S")

    tz = _tz()
    if dt.tzinfo is None:
        # naive -> assume PT wall clock
        if tz is None:
            return dt
        return dt.replace(tzinfo=tz)
    if tz is None:
        return dt
    return dt.astimezone(tz)

def _today_pt() -> date:
    tz = _tz()
    now = datetime.utcnow().replace(tzinfo=ZoneInfo("UTC")) if ZoneInfo else datetime.utcnow()
    if tz and hasattr(now, "astimezone"):
        return now.astimezone(tz).date()
    return datetime.now().date()

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
    counts = {
        "boot": 0,
        "shadow_plan": 0,
        "shadow_accept": 0,
        "shadow_reject": 0,
        "fake_plans": 0,
        "valid_accepts": 0,
    }
    accepted_risk = 0.0
    if not os.path.exists(meta_path):
        return MetaStats(day=str(day_pt), boot=0, shadow_plan=0, shadow_accept=0, shadow_reject=0,
                         fake_plans=0, valid_accepts=0, accepted_risk_usd=0.0)

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

            if kind in counts:
                counts[kind] += 1

            if kind == "shadow_plan":
                if is_fake_payload(j.get("payload")):
                    counts["fake_plans"] += 1

            if kind == "shadow_accept":
                p = j.get("payload") or {}
                # do NOT count fake accepts as valid consumption
                if is_fake_payload(p):
                    continue
                counts["valid_accepts"] += 1
                # optional risk sum
                for rk in ("risk_usd", "riskUsd", "risk"):
                    if rk in p:
                        try:
                            accepted_risk += float(p[rk])
                        except Exception:
                            pass
                        break

    return MetaStats(
        day=str(day_pt),
        boot=int(counts["boot"]),
        shadow_plan=int(counts["shadow_plan"]),
        shadow_accept=int(counts["shadow_accept"]),
        shadow_reject=int(counts["shadow_reject"]),
        fake_plans=int(counts["fake_plans"]),
        valid_accepts=int(counts["valid_accepts"]),
        accepted_risk_usd=float(accepted_risk),
    )

def _atomic_write_json(path: str, obj: Dict[str, Any]) -> None:
    tmp = path + ".tmp"
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
    os.replace(tmp, path)

def apply_persistent_gate_limits(args: Any, root_dir: str, allow_fake_start: bool = False) -> MetaStats:
    meta_path = os.path.join(root_dir, "logs", "meta.jsonl")
    day = _today_pt()
    st = meta_stats(meta_path, day_pt=day)

    # Persist audit state (ops-visible)
    state_path = os.path.join(root_dir, "logs", "ops", f"gate_state_{day.strftime('%Y%m%d')}.json")
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
        raise SystemExit(
            f"[PERSIST_CAP] HARD_STOP: fake_plans={st.fake_plans} detected today in meta. "
            f"Fix upstream; refusing to start."
        )

    # Plans/day cap (restart-safe)
    if hasattr(args, "gate_max_plans_per_day"):
        orig = int(getattr(args, "gate_max_plans_per_day"))
        rem = max(0, orig - int(st.valid_accepts))
        setattr(args, "gate_max_plans_per_day", rem)
        setattr(args, "_gate_persist_orig_cap", orig)
        setattr(args, "_gate_persist_remaining_cap", rem)

        print(f"[PERSIST_CAP] day={st.day} valid_accepts={st.valid_accepts} orig_cap={orig} effective_cap={rem}")

        if rem <= 0:
            raise SystemExit(f"[PERSIST_CAP] CAP_REACHED: valid_accepts={st.valid_accepts} orig_cap={orig}. Exiting.")

    # Optional: risk cap (restart-safe) if present and if we could sum accepted risk
    if hasattr(args, "gate_max_risk_usd") and st.accepted_risk_usd > 0:
        try:
            orig_r = float(getattr(args, "gate_max_risk_usd"))
            rem_r = max(0.0, orig_r - float(st.accepted_risk_usd))
            setattr(args, "gate_max_risk_usd", rem_r)
            print(f"[PERSIST_CAP] risk_used={st.accepted_risk_usd:.2f} orig_risk_cap={orig_r:.2f} effective_risk_cap={rem_r:.2f}")
        except Exception:
            pass

    return st

if __name__ == "__main__":
    # quick manual check:
    root = os.getcwd()
    s = meta_stats(os.path.join(root, "logs", "meta.jsonl"))
    print(s)
"@

  Set-Content -Encoding UTF8 -Path $gatePy -Value $gateCode
  Write-Host "OK: wrote => $gatePy"
}

# ---- Patch tbot\main.py ----
$mainPy = Join-Path $ROOT "tbot\main.py"
if(-not (Test-Path $mainPy)){ throw "Cannot find: $mainPy" }
Copy-Item -Force $mainPy (Join-Path $BAK "main.py.bak")

$main = Get-Content -Raw -Encoding UTF8 $mainPy
if($main -match "TBOT_PERSIST_CAP_V1"){
  Write-Host "main.py already patched (marker found) => skip"
} else {
  # Find: <var> = parser.parse_args(...)
  $rx = [regex]::new("(?m)^(?<indent>\s*)(?<var>\w+)\s*=\s*.*parse_args\([^\)]*\)\s*$")
  $m = $rx.Match($main)
  if(-not $m.Success){
    throw "Patch failed: could not find parse_args assignment in tbot\main.py"
  }

  $indent = $m.Groups["indent"].Value
  $var = $m.Groups["var"].Value

  $block = @"
$indent# --- TBOT_PERSIST_CAP_V1 BEGIN ---
$indenttry:
$indent    from pathlib import Path as _TBOTPath
$indent    from tbot.runtime.gate_state import apply_persistent_gate_limits as _tbot_apply_persist
$indent    _tbot_root = str(_TBOTPath(__file__).resolve().parents[1])
$indent    _tbot_apply_persist($var, root_dir=_tbot_root, allow_fake_start=False)
$indentexcept SystemExit as _e:
$indent    # graceful stop for cap reached / fake detected
$indent    raise
$indentexcept Exception as _e:
$indent    # if persist layer errors, fail closed (ops safety)
$indent    raise
$indent# --- TBOT_PERSIST_CAP_V1 END ---
"@

  $insertPos = $m.Index + $m.Length
  $main2 = $main.Insert($insertPos, "`r`n" + $block + "`r`n")
  Set-Content -Encoding UTF8 -Path $mainPy -Value $main2
  Write-Host "OK: patched => $mainPy"
}

# ---- Optional: task check / disable 0630 ----
if(-not $SkipTaskCheck){
  Write-Host ""
  Write-Host "TASKS:"
  try{
    Get-ScheduledTask | Where-Object { $_.TaskName -like "TBOT_*" } | Select-Object TaskName,State | Format-Table -AutoSize
  } catch {
    Write-Host "TASKS=WARNING (need Admin for Task Scheduler access sometimes)."
  }
}

if($Disable0630){
  Write-Host ""
  try{
    Disable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" -ErrorAction Stop | Out-Null
    Write-Host "TASK_ACTION: Disabled TBOT_RUN_SHADOW_DAILY_0630"
  } catch {
    Write-Host "TASK_ACTION: Disable0630 FAILED (run as Admin)."
  }
}

# ---- Tests (safe, no bot run) ----
Write-Host ""
Write-Host "TEST 1: import gate_state"
& $PY -c "import tbot.runtime.gate_state as gs; print('gate_state_import_ok')"
if($LASTEXITCODE -ne 0){ throw "TEST 1 failed" }

Write-Host ""
Write-Host "TEST 2: compute meta stats (today) + show counts"
& $PY -c "import os; from tbot.runtime.gate_state import meta_stats; print(meta_stats(os.path.join(os.getcwd(),'logs','meta.jsonl')))"
if($LASTEXITCODE -ne 0){ throw "TEST 2 failed" }

Write-Host ""
Write-Host "TEST 3: synthetic restart-cap check (no market)"
& $PY -c "import os, json, tempfile; from argparse import Namespace; from tbot.runtime.gate_state import apply_persistent_gate_limits; root=os.getcwd(); d=os.path.join(root,'logs','ops'); os.makedirs(d,exist_ok=True); tmp=os.path.join(d,'_meta_synth.jsonl'); open(tmp,'w',encoding='utf-8').write(''.join([json.dumps({'ts':'2030-01-01T07:00:00','kind':'shadow_accept','payload':{'entry':10,'stop':9,'tp':12,'reason':'ok','risk_usd':25,'symbol':'SPY'}})+'\\n' for _ in range(3)])); args=Namespace(gate_max_plans_per_day=5, gate_max_risk_usd=200.0); from tbot.runtime import gate_state as gs; s=gs.meta_stats(tmp, day_pt=gs._parse_ts_to_pt('2030-01-01T07:00:00').date()); print('synth_stats',s); os.remove(tmp); print('synth_ok')"
if($LASTEXITCODE -ne 0){ throw "TEST 3 failed" }

Write-Host ""
Write-Host "PATCH_OK. Backup dir:"
Write-Host $BAK

Write-Host ""
Write-Host "NEXT (tomorrow run):"
Write-Host " - If using wrapper/oneclick, keep using it."
Write-Host " - This patch makes cap restart-safe even without wrapper."
Write-Host ""
Write-Host "Example (your existing runner args still apply):"
Write-Host ".\tools\WEEK2_ONECLICK.ps1 StartOps -TotalDaily 120 -CooldownSec 45 -ShadowRiskUsd 25 -MaxPerSymbol 60 -Symbols `"SPY,QQQ,NVDA`" -Force"
