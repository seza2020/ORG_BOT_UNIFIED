param()
$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $ROOT "code"
$PAPER=Join-Path $CODE "tools\paper"
$RUNROOT_DEFAULT=Join-Path $ROOT "runtime\paper"
$PY_DEFAULT=Join-Path $CODE ".venv\Scripts\python.exe"

$EXE2=Join-Path $PAPER "EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"
$EXE1=Join-Path $PAPER "EXECUTE_PLAN_SELECTION_PAPER_V1.ps1"

$targets=@()
if(Test-Path -LiteralPath $EXE2){ $targets += $EXE2 }
if(Test-Path -LiteralPath $EXE1){ $targets += $EXE1 }
if($targets.Count -eq 0){ throw "NO_TARGETS_FOUND in $PAPER" }

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$PDIR=Join-Path $ROOT ("ops\patches\STAGE8E_EXEC_WIRING_V3_" + $stamp)
$ADIR=Join-Path $ROOT ("ops\audit\STAGE8E_EXEC_WIRING_V3_" + $stamp)
New-Item -ItemType Directory -Force -Path $PDIR | Out-Null
New-Item -ItemType Directory -Force -Path $ADIR | Out-Null

function Insert-AfterFirstMatch {
  param(
    [Parameter(Mandatory=$true)][string[]]$Lines,
    [Parameter(Mandatory=$true)][string]$Pattern,
    [Parameter(Mandatory=$true)][string[]]$Block,
    [switch]$Required
  )
  $out=@()
  $done=$false
  for($i=0;$i -lt $Lines.Count;$i++){
    $out += $Lines[$i]
    if(-not $done -and ($Lines[$i] -match $Pattern)){
      $out += $Block
      $done=$true
    }
  }
  if($Required -and -not $done){ throw ("PATCHPOINT_NOT_FOUND=" + $Pattern) }
  return ,@($out)
}

foreach($EXE in $targets){
  Copy-Item -LiteralPath $EXE -Destination (Join-Path $PDIR ([IO.Path]::GetFileName($EXE)+".bak")) -Force
  $raw = Get-Content -LiteralPath $EXE -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ throw ("FILE_EMPTY=" + $EXE) }
  if($raw -match "STAGE8E_EXEC_WIRING_BEGIN"){ "SKIP_ALREADY_PATCHED=$EXE" | Out-Host; continue }

  $wire = @'
# === STAGE8E_EXEC_WIRING_BEGIN ===
try { if(-not $env:PYTHONPATH){ $env:PYTHONPATH = "C:\alpaca-bot\ORG_BOT_UNIFIED\code" } } catch {}

function STAGE8E-CallLedgerPy {
  param(
    [Parameter(Mandatory=$true)][string]$Action,
    [Parameter(Mandatory=$true)][string]$RunRoot,
    [Parameter(Mandatory=$true)][string]$Rid,
    [double]$RiskUsd = 0.0,
    [string]$Sid = "",
    [string]$Symbol = ""
  )
  try {
    $pyExe = $PY
    if([string]::IsNullOrWhiteSpace($pyExe)){ $pyExe = "C:\alpaca-bot\ORG_BOT_UNIFIED\code\.venv\Scripts\python.exe" }
    if(Test-Path -LiteralPath $pyExe){ $pyExe = (Resolve-Path -LiteralPath $pyExe).Path }

    $env:RUNROOT        = $RunRoot
    $env:STAGE8E_ACTION = $Action
    $env:STAGE8E_RID    = $Rid
    $env:STAGE8E_RISK   = [string]$RiskUsd
    $env:STAGE8E_SID    = $Sid
    $env:STAGE8E_SYM    = $Symbol

    $py = @"
import os
from tbot.runtime.risk_ledger_atomic import reserve_preaccept, commit_after_accept, release_reservation, reconcile_ttl
rr=os.environ["RUNROOT"]
try: reconcile_ttl(rr, ttl_sec=60)
except Exception: pass
action=os.environ.get("STAGE8E_ACTION","")
rid=os.environ.get("STAGE8E_RID","")
risk=float(os.environ.get("STAGE8E_RISK","0") or "0")
sid=os.environ.get("STAGE8E_SID","")
sym=os.environ.get("STAGE8E_SYM","")
if action=="reserve":
  ok, rsn, snap = reserve_preaccept(rr, risk, rid, sid=sid, symbol=sym); print("reserve", ok, rsn, snap)
elif action=="commit":
  ok, rsn, snap = commit_after_accept(rr, rid); print("commit", ok, rsn, snap)
elif action=="release":
  ok, rsn, snap = release_reservation(rr, rid); print("release", ok, rsn, snap)
elif action=="reconcile":
  try: reconcile_ttl(rr, ttl_sec=1); print("reconcile", True)
  except Exception as e: print("reconcile", False, str(e))
else:
  print("bad_action", action)
"@

    $out = & $pyExe @("-c", $py) 2>&1 | Out-String
    return @{ ok=$true; out=$out }
  } catch {
    return @{ ok=$false; out=$_.Exception.Message }
  }
}

try { STAGE8E-CallLedgerPy -Action "reconcile" -RunRoot ($env:RUNROOT ? $env:RUNROOT : "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper") -Rid "RID:RECON" | Out-Null } catch {}
# === STAGE8E_EXEC_WIRING_END ===
'@

  $lines = $raw -split "`r`n"
  $insertAt = 0
  if($lines.Count -gt 0 -and ($lines[0].TrimStart().ToLower().StartsWith("param("))){
    $close=-1; for($i=0;$i -lt $lines.Count;$i++){ if($lines[$i].Trim() -eq ")"){ $close=$i; break } }
    if($close -gt -1){ $insertAt = $close + 1 }
  }

  $out=@()
  for($i=0;$i -lt $lines.Count;$i++){ if($i -eq $insertAt){ $out += ($wire -split "`r`n") }; $out += $lines[$i] }
  if($insertAt -ge $lines.Count){ $out += ($wire -split "`r`n") }

  $reserveHook=@(
    "# === STAGE8E_RESERVE_BEFORE_SUBMIT BEGIN ===",
    "try {",
    "  $rr = $env:RUNROOT; if([string]::IsNullOrWhiteSpace($rr)){ $rr = `"`" }",
    "  $sym = `"`"; try { if($planObj.sym){ $sym=[string]$planObj.sym } } catch {}",
    "  $sid = `"`"; try { if($planObj.sid){ $sid=[string]$planObj.sid } } catch {}",
    "  $rid = `"`"; try { if($planObj.PSObject.Properties.Name -contains 'risk_rid'){ $rid=[string]$planObj.risk_rid } } catch {}",
    "  if([string]::IsNullOrWhiteSpace($rid)){ try { if($planObj.client_order_id){ $rid=[string]$planObj.client_order_id } } catch {} }",
    "  if([string]::IsNullOrWhiteSpace($rid)){ $rid=('RID:PAPER:' + (Get-Date -Format yyyyMMdd_HHmmss) + ':' + $sym) }",
    "  $risk=0.0; try { if($planObj.PSObject.Properties.Name -contains 'risk_usd'){ $risk=[double]$planObj.risk_usd } } catch { $risk=0.0 }",
    "  if($risk -gt 0){ $r = STAGE8E-CallLedgerPy -Action 'reserve' -RunRoot $rr -Rid $rid -RiskUsd $risk -Sid $sid -Symbol $sym }",
    "  try { $planObj | Add-Member -Force NoteProperty risk_rid $rid } catch {}",
    "} catch {}",
    "# === STAGE8E_RESERVE_BEFORE_SUBMIT END ==="
  )

  $commitHook=@(
    "# === STAGE8E_COMMIT_AFTER_SUBMIT BEGIN ===",
    "try {",
    "  $rr=$env:RUNROOT; if([string]::IsNullOrWhiteSpace($rr)){ $rr = `"`" }",
    "  $rid=`"`"; try { if($planObj.risk_rid){ $rid=[string]$planObj.risk_rid } } catch {}",
    "  if(-not [string]::IsNullOrWhiteSpace($rid)){ $r = STAGE8E-CallLedgerPy -Action 'commit' -RunRoot $rr -Rid $rid }",
    "} catch {}",
    "# === STAGE8E_COMMIT_AFTER_SUBMIT END ==="
  )

  $releaseHook=@(
    "# === STAGE8E_RELEASE_ON_ERROR BEGIN ===",
    "try {",
    "  $rr=$env:RUNROOT; if([string]::IsNullOrWhiteSpace($rr)){ $rr = `"`" }",
    "  $rid=`"`"; try { if($planObj.risk_rid){ $rid=[string]$planObj.risk_rid } } catch {}",
    "  if(-not [string]::IsNullOrWhiteSpace($rid)){ $r = STAGE8E-CallLedgerPy -Action 'release' -RunRoot $rr -Rid $rid }",
    "} catch {}",
    "# === STAGE8E_RELEASE_ON_ERROR END ==="
  )

  $dryHook=@(
    "# === STAGE8E_RELEASE_ON_DRYRUN BEGIN ===",
    "try {",
    "  $rr=$env:RUNROOT; if([string]::IsNullOrWhiteSpace($rr)){ $rr = `"`" }",
    "  $rid=`"`"; try { if($planObj.risk_rid){ $rid=[string]$planObj.risk_rid } } catch {}",
    "  if(-not [string]::IsNullOrWhiteSpace($rid)){ $r = STAGE8E-CallLedgerPy -Action 'release' -RunRoot $rr -Rid $rid }",
    "} catch {}",
    "# === STAGE8E_RELEASE_ON_DRYRUN END ==="
  )

  $out = Insert-AfterFirstMatch -Lines $out -Pattern "ConvertFrom-Json" -Block $reserveHook -Required
  $out = Insert-AfterFirstMatch -Lines $out -Pattern 'kind\s*=\s*"order_submitted"' -Block $commitHook -Required
  $out = Insert-AfterFirstMatch -Lines $out -Pattern 'kind\s*=\s*"order_error"' -Block $releaseHook -Required
  $out = Insert-AfterFirstMatch -Lines $out -Pattern 'kind\s*=\s*"dryrun_skip_submit"' -Block $dryHook

  ($out -join "`r`n") | Set-Content -LiteralPath $EXE -Encoding utf8
  Unblock-File -LiteralPath $EXE -ErrorAction SilentlyContinue
  ("PATCH_OK=" + $EXE) | Out-Host
}

("PATCH_DIR=" + $PDIR) | Out-Host
("AUDIT_DIR=" + $ADIR) | Out-Host
"NEXT=RUN_DRYRUN_SMOKE" | Out-Host
