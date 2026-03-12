# tools\PATCH_PERSISTENT_DAILY_CAP_V2.ps1
# Patch: Persistent daily cap across restarts (meta-backed) + fake-plan fail-closed
# Scope-safe: project-only paths. No secrets touched.

[CmdletBinding()]
param(
  [switch]$Disable0630,
  [switch]$SkipTaskCheck,
  [switch]$Force
)

$ErrorActionPreference="Stop"

$ROOT = (Get-Location).Path
if($ROOT -ne "C:\alpaca-bot\org_bot"){ throw "Run from C:\alpaca-bot\org_bot (current: $ROOT)" }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
if(-not (Test-Path $PY)){ throw "Venv python not found: $PY" }

$OPS = Join-Path $ROOT "logs\ops"
New-Item -ItemType Directory -Force -Path $OPS | Out-Null

$ts  = Get-Date -Format "yyyyMMdd_HHmmss"
$BAK = Join-Path $OPS ("PATCH_PERSIST_CAP_{0}" -f $ts)
New-Item -ItemType Directory -Force -Path $BAK | Out-Null

# -------------------------
# 1) Write tbot/runtime/gate_state.py
# -------------------------
$gatePy = Join-Path $ROOT "tbot\runtime\gate_state.py"
if((Test-Path $gatePy) -and (-not $Force)){
  Write-Host "gate_state.py exists => skip (use -Force to overwrite)"
} else {
  if(Test-Path $gatePy){ Copy-Item -Force $gatePy (Join-Path $BAK "gate_state.py.bak") }

  $gateCode = @"
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
        rem = max(0, orig - int(st.valid_accepts))
        setattr(args, "gate_max_plans_per_day", rem)
        setattr(args, "_gate_persist_orig_cap", orig)
        setattr(args, "_gate_persist_remaining_cap", rem)
        print(f"[PERSIST_CAP] day={st.day} valid_accepts={st.valid_accepts} orig_cap={orig} effective_cap={rem}")
        if rem <= 0:
            raise SystemExit(f"[PERSIST_CAP] CAP_REACHED: valid_accepts={st.valid_accepts} orig_cap={orig}. Exiting.")

    if hasattr(args, "gate_max_risk_usd") and st.accepted_risk_usd > 0:
        try:
            orig_r = float(getattr(args, "gate_max_risk_usd"))
            rem_r = max(0.0, orig_r - float(st.accepted_risk_usd))
            setattr(args, "gate_max_risk_usd", rem_r)
            print(f"[PERSIST_CAP] risk_used={st.accepted_risk_usd:.2f} orig_risk_cap={orig_r:.2f} effective_risk_cap={rem_r:.2f}")
        except Exception:
            pass

    return st
"@

  Set-Content -Encoding UTF8 -Path $gatePy -Value $gateCode
  Write-Host "OK: wrote => $gatePy"
}

# -------------------------
# 2) Patch tbot/main.py after parse_args
# -------------------------
$mainPy = Join-Path $ROOT "tbot\main.py"
if(-not (Test-Path $mainPy)){ throw "Cannot find: $mainPy" }
Copy-Item -Force $mainPy (Join-Path $BAK "main.py.bak")

$lines = Get-Content -Encoding UTF8 $mainPy
$marker = "TBOT_PERSIST_CAP_V1"
if($lines -match $marker){
  Write-Host "main.py already patched (marker found) => skip"
} else {
  $idx = -1; $indent = ""; $var = ""
  for($i=0; $i -lt $lines.Count; $i++){
    if($lines[$i] -match '^\s*(\w+)\s*=\s*.*\bparse_args\('){
      $idx = $i
      $var = $matches[1]
      $indent = ($lines[$i] -replace '^(\s*).*','$1')
      break
    }
  }
  if($idx -lt 0){ throw "Patch failed: could not find a line like: args = ...parse_args(...)" }

  $blockLines = @(
    "${indent}# --- ${marker} BEGIN ---",
    "${indent}try:",
    "${indent}    import os as _TBOTos",
    "${indent}    from pathlib import Path as _TBOTPath",
    "${indent}    from tbot.runtime.gate_state import apply_persistent_gate_limits as _tbot_apply_persist",
    "${indent}    _tbot_root = str(_TBOTPath(__file__).resolve().parents[1])",
    "${indent}    _allow_fake = _TBOTos.getenv('TBOT_ALLOW_FAKE_START','0') == '1'",
    "${indent}    _tbot_apply_persist(${var}, root_dir=_tbot_root, allow_fake_start=_allow_fake)",
    "${indent}except SystemExit:",
    "${indent}    raise",
    "${indent}except Exception:",
    "${indent}    # fail-closed if persist layer errors",
    "${indent}    raise",
    "${indent}# --- ${marker} END ---"
  )

  $newLines = @()
  $newLines += $lines[0..$idx]
  $newLines += ""
  $newLines += $blockLines
  $newLines += ""
  if($idx+1 -le $lines.Count-1){ $newLines += $lines[($idx+1)..($lines.Count-1)] }

  Set-Content -Encoding UTF8 -Path $mainPy -Value $newLines
  Write-Host "OK: patched => $mainPy (var=$var)"
}

# -------------------------
# 3) Optional: Task check / disable 0630
# -------------------------
if(-not $SkipTaskCheck){
  Write-Host ""
  Write-Host "TASKS:"
  try{
    Get-ScheduledTask | Where-Object { $_.TaskName -like "TBOT_*" } | Select-Object TaskName,State | Format-Table -AutoSize
  } catch {
    Write-Host "TASKS=WARNING (run as Admin if needed)."
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

# -------------------------
# 4) Tests (no bot run)
# -------------------------
Write-Host ""
Write-Host "TEST 1: import gate_state"
& $PY -c "import tbot.runtime.gate_state as gs; print('gate_state_import_ok')"
if($LASTEXITCODE -ne 0){ throw "TEST 1 failed" }

Write-Host ""
Write-Host "TEST 2: meta_stats(today)"
& $PY -c "import os; from tbot.runtime.gate_state import meta_stats; print(meta_stats(os.path.join(os.getcwd(),'logs','meta.jsonl')))"
if($LASTEXITCODE -ne 0){ throw "TEST 2 failed" }

Write-Host ""
Write-Host "TEST 3: py_compile patched files"
& $PY -m py_compile "tbot\main.py" "tbot\runtime\gate_state.py"
if($LASTEXITCODE -ne 0){ throw "TEST 3 failed" }

Write-Host ""
Write-Host "TEST 4: synthetic remaining-cap logic"
& $PY -c "import os, json, tempfile; from argparse import Namespace; from datetime import date; from tbot.runtime.gate_state import apply_persistent_gate_limits; tmp=tempfile.mkdtemp(); os.makedirs(os.path.join(tmp,'logs'),exist_ok=True); mp=os.path.join(tmp,'logs','meta.jsonl'); day=date(2030,1,1); lines=[]; 
for i in range(3): lines.append(json.dumps({'ts':'2030-01-01T07:00:00','kind':'shadow_accept','payload':{'entry':10,'stop':9,'tp':12,'reason':'ok','risk_usd':25,'symbol':'SPY'}})); 
open(mp,'w',encoding='utf-8').write('\\n'.join(lines)+'\\n'); 
args=Namespace(gate_max_plans_per_day=5, gate_max_risk_usd=200.0); 
apply_persistent_gate_limits(args, root_dir=tmp, allow_fake_start=True, day_pt=day); 
print('effective_cap', args.gate_max_plans_per_day); 
assert args.gate_max_plans_per_day==2; 
print('synth_ok')"
if($LASTEXITCODE -ne 0){ throw "TEST 4 failed" }

Write-Host ""
Write-Host "PATCH_OK. Backup dir:"
Write-Host $BAK
Write-Host ""
Write-Host "NOTE:"
Write-Host " - Persistent cap is now restart-safe because remaining cap is computed from meta at every start."
Write-Host " - If fake plans exist today, start will HARD_STOP unless TBOT_ALLOW_FAKE_START=1."
Write-Host ""
Write-Host "Next run example (tomorrow):"
Write-Host ".\tools\WEEK2_ONECLICK.ps1 StartOps -TotalDaily 120 -CooldownSec 45 -ShadowRiskUsd 25 -MaxPerSymbol 60 -Symbols `"SPY,QQQ,NVDA`" -Force"
