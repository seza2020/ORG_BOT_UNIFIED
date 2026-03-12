$ErrorActionPreference="Stop"

# STAGE8E_BASELINE_PATCH.ps1
# Purpose:
# - Verify Atomic Risk Ledger primitives work in the active runtime (RUNROOT)
# - Produce auditable output under ops\audit
# - NO regex heavy patching here, just smoke/verify to keep it stable.

function Resolve-PyExe {
  param([string]$Preferred)

  try {
    if(-not [string]::IsNullOrWhiteSpace($Preferred)){
      $p=[string]$Preferred
      if(Test-Path -LiteralPath $p){ return (Resolve-Path -LiteralPath $p).Path }
      return $p
    }
  } catch {}

  try {
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if($cmd){ return $cmd.Source }
  } catch {}

  return $null
}

$ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE = Join-Path $ROOT "code"

# RUNROOT can be overridden by env, default to paper
$RUNROOT = $env:RUNROOT
if([string]::IsNullOrWhiteSpace($RUNROOT)){
  $RUNROOT = Join-Path $ROOT "runtime\paper"
}

# Python can be overridden by env PY, default to venv python
$PY = $env:PY
if([string]::IsNullOrWhiteSpace($PY)){
  $PY = Join-Path $CODE ".venv\Scripts\python.exe"
}

$pyExe = Resolve-PyExe $PY
if([string]::IsNullOrWhiteSpace($pyExe)){ throw "PY_RESOLVE_FAILED=$PY" }
if(!(Test-Path -LiteralPath $RUNROOT)){ throw "RUNROOT_NOT_FOUND=$RUNROOT" }

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR = Join-Path $ROOT ("ops\audit\STAGE8E_BASELINE_VERIFY_" + $stamp)
New-Item -ItemType Directory -Force -Path $ADIR | Out-Null

# Ensure env for python
$env:PYTHONPATH = $CODE
$env:RUNROOT = $RUNROOT

# Python verify (atomic ledger reserve/commit/release + ledger json sanity)
$verify = @'
import os, json, time
from tbot.runtime.risk_ledger_atomic import reserve_preaccept, commit_after_accept, release_reservation, reconcile_ttl

rr = os.environ["RUNROOT"]
# small ttl so reconcile is meaningful
reconcile_ttl(rr, ttl_sec=1)

ok, rsn, snap = reserve_preaccept(rr, 1.0, "RID:VERIFY:1", sid="TEST", symbol="TEST")
print("reserve1", ok, rsn, snap)

ok2, rsn2, snap2 = commit_after_accept(rr, "RID:VERIFY:1")
print("commit1", ok2, rsn2, snap2)

ok3, rsn3, snap3 = reserve_preaccept(rr, 1.0, "RID:VERIFY:2", sid="TEST", symbol="TEST")
print("reserve2", ok3, rsn3, snap3)

ok4, rsn4, snap4 = release_reservation(rr, "RID:VERIFY:2")
print("release2", ok4, rsn4, snap4)

lp = os.path.join(rr, "state","risk","risk_ledger.json")
j = json.load(open(lp,"r",encoding="utf-8"))
print("ledger", j.get("date"), j.get("used_risk"), j.get("reserved_risk"), len(j.get("reservations",{})), len(j.get("commits",[])))
'@

$out = & $pyExe @("-c", $verify) 2>&1 | Out-String
$out | Set-Content (Join-Path $ADIR "verify_python.txt") -Encoding utf8
if($LASTEXITCODE -ne 0){ throw "VERIFY_PY_FAILED EXIT=$LASTEXITCODE AUDIT_DIR=$ADIR" }

$LEDGER = Join-Path $RUNROOT "state\risk\risk_ledger.json"
if(!(Test-Path -LiteralPath $LEDGER)){ throw "LEDGER_NOT_FOUND=$LEDGER" }

$j = Get-Content -LiteralPath $LEDGER -Raw | ConvertFrom-Json
if([double]$j.reserved_risk -ne 0){ throw "FAIL_RESERVED_NOT_ZERO=$($j.reserved_risk) AUDIT_DIR=$ADIR" }

$resCount = 0
try { $resCount = ($j.reservations.PSObject.Properties | Measure-Object).Count } catch { $resCount = 0 }
if($resCount -ne 0){ throw "FAIL_RESERVATIONS_NOT_EMPTY COUNT=$resCount AUDIT_DIR=$ADIR" }

Write-Host "STAGE8E_BASELINE_VERIFY=PASS"
Write-Host ("RUNROOT=" + $RUNROOT)
Write-Host ("PY=" + $pyExe)
Write-Host ("AUDIT_DIR=" + $ADIR)
