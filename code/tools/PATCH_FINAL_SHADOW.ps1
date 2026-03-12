#requires -Version 7.0
$ErrorActionPreference = "Stop"

$Root = "C:\alpaca-bot\org_bot"
$Tools = Join-Path $Root "tools"
$Logs  = Join-Path $Root "logs"
$Ops   = Join-Path $Logs "ops"
$BkTop = Join-Path $Logs "backups"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BK    = Join-Path $BkTop ("SNAPSHOT_{0}" -f $Stamp)

New-Item -ItemType Directory -Force $Tools,$Logs,$Ops,$BkTop,$BK | Out-Null

Write-Host ("BACKUP SNAPSHOT: {0}" -f $BK)

# ---- Files to backup (if exist)
$files = @(
  (Join-Path $Root "tbot\runtime\shadow_pricing.py"),
  (Join-Path $Root "tbot\runtime\orchestrator.py"),
  (Join-Path $Root "tools\run_shadow.ps1")
)
foreach ($f in $files) {
  if (Test-Path $f) {
    Copy-Item $f -Destination (Join-Path $BK (Split-Path $f -Leaf)) -Force
  }
}

# ---- Rewrite shadow_pricing.py (clean + robust)
$SP = Join-Path $Root "tbot\runtime\shadow_pricing.py"

$spSrc = @"
from __future__ import annotations

import os
from typing import Any, Optional, Tuple

def _env_float(name: str, default: float) -> float:
    v = os.getenv(name)
    if v is None or v == "":
        return float(default)
    try:
        return float(v)
    except Exception:
        return float(default)

def _env_str(name: str, default: str) -> str:
    v = os.getenv(name)
    return v if v not in (None, "") else default

def compute_shadow_prices(last: float, side: str, stop_pct: float, rr: float) -> Tuple[float, float, float]:
    # stop_pct: e.g. 0.003 (0.3%)
    side_u = (side or "").upper()
    entry = float(last)

    if side_u == "LONG":
        stop = entry * (1.0 - stop_pct)
        tp   = entry * (1.0 + stop_pct * rr)
    else:
        # default SHORT
        stop = entry * (1.0 + stop_pct)
        tp   = entry * (1.0 - stop_pct * rr)

    return float(entry), float(stop), float(tp)

def _extract_last(symbol: Optional[str], obj: Any) -> Optional[float]:
    if obj is None:
        return None

    # dict forms
    if isinstance(obj, dict):
        # direct
        for k in ("last", "price", "close", "mid"):
            if k in obj:
                try:
                    return float(obj[k])
                except Exception:
                    pass

        # nested by symbol
        if symbol and symbol in obj:
            try:
                return _extract_last(symbol, obj[symbol])
            except Exception:
                return None

        return None

    # attribute forms
    for attr in ("last", "price", "close", "mid"):
        if hasattr(obj, attr):
            try:
                return float(getattr(obj, attr))
            except Exception:
                pass

    # method forms
    for m in ("get_last", "last_price", "get_price"):
        if hasattr(obj, m):
            try:
                val = getattr(obj, m)(symbol) if symbol else getattr(obj, m)()
                return float(val)
            except Exception:
                pass

    return None

def price_shadow_plan(plan: Any, *args: Any, **kwargs: Any) -> Any:
    # Must exist because orchestrator imports it.
    # We duck-type: plan has .symbol .side and we set .entry/.stop/.tp if we can.
    try:
        symbol = kwargs.get("symbol", None) or getattr(plan, "symbol", None)
        side   = kwargs.get("side", None)   or getattr(plan, "side", None)

        price_mode = _env_str("TBOT_SHADOW_PRICE_MODE", "last").lower()
        stop_pct   = _env_float("TBOT_SHADOW_STOP_PCT", 0.003)
        rr         = _env_float("TBOT_SHADOW_RR", 2.0)

        # try multiple sources for last
        last = None

        # explicit kw
        last = kwargs.get("last", None) or kwargs.get("px", None) or kwargs.get("price", None)
        if last is not None:
            try:
                last = float(last)
            except Exception:
                last = None

        # plan fields
        if last is None:
            for attr in ("last", "price", "entry"):
                if hasattr(plan, attr):
                    try:
                        v = float(getattr(plan, attr))
                        if v > 0:
                            last = v
                            break
                    except Exception:
                        pass

        # market/snapshot passed in kwargs
        if last is None:
            for k in ("market", "snapshot", "snap", "market_snapshot", "prices"):
                if k in kwargs:
                    last = _extract_last(symbol, kwargs[k])
                    if last is not None:
                        break

        # args may contain a market object/dict
        if last is None and args:
            for a in args:
                last = _extract_last(symbol, a)
                if last is not None:
                    break

        if last is None:
            return plan

        entry, stop, tp = compute_shadow_prices(last=last, side=side or "SHORT", stop_pct=stop_pct, rr=rr)

        # apply
        try:
            setattr(plan, "entry", float(entry))
            setattr(plan, "stop", float(stop))
            setattr(plan, "tp", float(tp))
        except Exception:
            pass

        return plan
    except Exception:
        return plan
"@

Set-Content -LiteralPath $SP -Value $spSrc -Encoding UTF8

# ---- Rewrite tools\run_shadow.ps1 (no parse errors, fixes PYTHONPATH/cwd)
$Run = Join-Path $Root "tools\run_shadow.ps1"

$runSrc = @"
#requires -Version 7.0
param(
  [int]`$Iters = 999999,
  [double]`$Sleep = 0.25,
  [int]`$SimInSession = 1,
  [int]`$SimPreClose = 0,
  [int]`$GateMaxPlansPerDay = 9999,
  [int]`$GateCooldownSec = 5
)

`$ErrorActionPreference = "Stop"

`$Root = "C:\alpaca-bot\org_bot"
`$OpsDir = Join-Path `$Root "logs\ops"
New-Item -ItemType Directory -Force `$OpsDir | Out-Null

# kill stale python for this bot
Get-Process python -ErrorAction SilentlyContinue | Stop-Process -Force

Set-Location `$Root

# ensure imports work even if cwd changes
`$env:PYTHONPATH = `$Root

# load Alpaca keys
. "C:\alpaca-bot\secrets\alpaca_env.ps1"

# shadow pricing env
`$env:TBOT_SHADOW_PRICE_MODE = "last"
`$env:TBOT_SHADOW_STOP_PCT   = "0.003"
`$env:TBOT_SHADOW_RR         = "2.0"

# optional S01 enable
if (-not `$env:TBOT_ENABLE_S01_LOGIC) { `$env:TBOT_ENABLE_S01_LOGIC = "1" }

`$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
`$Out   = Join-Path `$OpsDir ("LIVE_OUT_{0}.txt" -f `$Stamp)

Write-Host "RUNNING SHADOW..."
Write-Host ("OUT={0}" -f `$Out)

`$Meta = Join-Path `$Root "logs\meta.jsonl"
`$Ann  = Join-Path `$Root "logs\announce.log"

`$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not `$py) { `$py = "C:\Python313\python.exe" }

`$args = @(
  "-m","tbot.main",
  "--run",
  "--iters", "`$Iters",
  "--sleep", "`$Sleep",
  "--shadow",
  "--meta", "`$Meta",
  "--announce", "`$Ann",
  "--sim_in_session", "`$SimInSession",
  "--sim_pre_close", "`$SimPreClose",
  "--gate_max_plans_per_day", "`$GateMaxPlansPerDay",
  "--gate_cooldown_sec", "`$GateCooldownSec"
)

& `$py @args 2>&1 | Tee-Object -FilePath `$Out
"@

Set-Content -LiteralPath $Run -Value $runSrc -Encoding UTF8

# ---- Compile check
$py = (Get-Command python -ErrorAction SilentlyContinue).Source
if (-not $py) { $py = "C:\Python313\python.exe" }

& $py -m py_compile (Join-Path $Root "tbot\runtime\shadow_pricing.py") | Out-Null
& $py -m py_compile (Join-Path $Root "tbot\runtime\orchestrator.py") | Out-Null

Write-Host "PATCH OK"
Write-Host ("RUN SCRIPT: {0}" -f $Run)
