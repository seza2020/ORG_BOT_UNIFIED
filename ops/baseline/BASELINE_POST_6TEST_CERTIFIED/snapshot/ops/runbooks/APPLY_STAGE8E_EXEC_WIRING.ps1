# APPLY_STAGE8E_EXEC_WIRING.ps1
# Purpose: Wire Atomic Risk Ledger (Stage8E) into Paper EXEC layer deterministically
# Safe: no nested here-strings, no regex-with-quote nightmares, line-based patching

$ErrorActionPreference = "Stop"

$ROOT  = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE  = Join-Path $ROOT "code"
$PAPER = Join-Path $CODE "tools\paper"
$EXE   = Join-Path $PAPER "EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"

if(!(Test-Path -LiteralPath $EXE)){
  throw "EXECUTE_PLAN_SELECTION_PAPER_V2_NOT_FOUND=$EXE"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$PATCH_DIR = Join-Path $ROOT ("ops\patches\STAGE8E_EXEC_WIRING_" + $stamp)
$AUDIT_DIR = Join-Path $ROOT ("ops\audit\STAGE8E_EXEC_WIRING_" + $stamp)
New-Item -ItemType Directory -Force -Path $PATCH_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $AUDIT_DIR | Out-Null

Copy-Item $EXE (Join-Path $PATCH_DIR "EXECUTE_PLAN_SELECTION_PAPER_V2.ps1.bak") -Force

$lines = Get-Content -LiteralPath $EXE -Encoding utf8
if(-not $lines -or $lines.Count -eq 0){
  throw "TARGET_EMPTY_OR_UNREADABLE=$EXE"
}

# Idempotent
if($lines -join "`n" | Select-String -SimpleMatch "STAGE8E_EXEC_WIRING_BEGIN" -Quiet){
  Write-Host "ALREADY_PATCHED=TRUE"
  Write-Host "EXE=$EXE"
  Write-Host "PATCH_DIR=$PATCH_DIR"
  Write-Host "AUDIT_DIR=$AUDIT_DIR"
  exit 0
}

function Insert-AfterFirstMatch([string[]]$inLines, [string]$pattern, [string[]]$block, [switch]$Optional){
  $out = New-Object System.Collections.Generic.List[string]
  $done = $false
  foreach($ln in $inLines){
    $out.Add($ln)
    if(-not $done -and ($ln -match $pattern)){
      foreach($b in $block){ $out.Add($b) }
      $done = $true
    }
  }
  if(-not $done -and -not $Optional){
    throw "PATCH_POINT_NOT_FOUND pattern=[$pattern]"
  }
  return ,$out.ToArray()
}

# ---------------------------------------------------------
# 1) Insert wiring block near top (after Param() if exists)
# ---------------------------------------------------------
$insertAt = 0
if($lines.Count -gt 0 -and ($lines[0].TrimStart().ToLower().StartsWith("param("))){
  $close = -1
  for($i=0;$i -lt $lines.Count;$i++){
    if($lines[$i].Trim() -eq ")"){ $close=$i; break }
  }
  if($close -gt -1){ $insertAt = $close + 1 } else { $insertAt = 0 }
}

$wiring = @(
  "# ================================",
  "# STAGE8E_EXEC_WIRING_BEGIN",
  "# ================================",
  "",
  '$STAGE8E_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"',
  '$STAGE8E_CODE = Join-Path $STAGE8E_ROOT "code"',
  '$env:PYTHONPATH = $STAGE8E_CODE',
  "",
  "function STAGE8E-GetPyExe {",
  "  param([string]`$p)",
  "  try {",
  "    if([string]::IsNullOrWhiteSpace(`$p)){ return `$null }",
  "    `$pp = [string]`$p",
  "    if(Test-Path -LiteralPath `$pp){ return (Resolve-Path -LiteralPath `$pp).Path }",
  "    return `$pp",
  "  } catch { return `$null }",
  "}",
  "",
  "function STAGE8E-CallLedger {",
  "  param(",
  "    [Parameter(Mandatory=`$true)][ValidateSet('reserve','commit','release')][string]`$Action,",
  "    [Parameter(Mandatory=`$true)][string]`$Rid,",
  "    [double]`$RiskUsd = 0",
  "  )",
  "  try {",
  "    `$PY = Join-Path `$STAGE8E_CODE '.venv\Scripts\python.exe'",
  "    `$pyExe = STAGE8E-GetPyExe `$PY",
  "    if([string]::IsNullOrWhiteSpace(`$pyExe)){ throw ('PY_NOT_FOUND=' + `$PY) }",
  "    `$env:RUNROOT = Join-Path `$STAGE8E_ROOT 'runtime\paper'",
  "    `$env:RID = `$Rid",
  "    `$env:RISK = [string]`$RiskUsd",
  "    `$env:ACT = `$Action",
  "",
  "    `$py = @(",
  "      'import os',",
  "      'from tbot.runtime.risk_ledger_atomic import reserve_preaccept, commit_after_accept, release_reservation',",
  "      ""rr = os.environ['RUNROOT']"",",
  "      ""rid = os.environ['RID']"",",
  "      ""risk = float(os.environ.get('RISK','0') or '0')"",",
  "      ""act = os.environ['ACT']"",",
  "      ""if act=='reserve':"",",
  "      ""    print(reserve_preaccept(rr, risk, rid))"",",
  "      ""elif act=='commit':"",",
  "      ""    print(commit_after_accept(rr, rid))"",",
  "      ""elif act=='release':"",",
  "      ""    print(release_reservation(rr, rid))"",",
  "      ""else:"",",
  "      ""    print('bad_action')""",
  "    ) -join ""`n""",
  "",
  "    & `$pyExe @('-c', `$py) 2>&1 | Out-Null",
  "  } catch {",
  "    Write-Host ('STAGE8E_LEDGER_ERR=' + `$_.Exception.Message)",
  "  }",
  "}",
  "",
  "# ================================",
  "# STAGE8E_EXEC_WIRING_END",
  "# ================================",
  ""
)

$out = New-Object System.Collections.Generic.List[string]
for($i=0;$i -lt $lines.Count;$i++){
  if($i -eq $insertAt){
    foreach($w in $wiring){ $out.Add($w) }
  }
  $out.Add($lines[$i])
}
if($insertAt -ge $lines.Count){
  foreach($w in $wiring){ $out.Add($w) }
}
$lines = $out.ToArray()

# ---------------------------------------------------------
# 2) Add hooks AFTER first occurrence of these event lines:
#    - kind="order_submitted" => commit
#    - kind="order_error" => release
#    - kind="dryrun_skip_submit" => release (best-effort)
# ---------------------------------------------------------

$commitHook = @(
  "# === STAGE8E_COMMIT_AFTER_SUBMIT BEGIN ===",
  "try {",
  "  if(`$planObj -and (`$planObj.PSObject.Properties.Name -contains 'risk_rid')){",
  "    `$rid = [string]`$planObj.risk_rid",
  "    if(-not [string]::IsNullOrWhiteSpace(`$rid)){",
  "      STAGE8E-CallLedger -Action 'commit' -Rid `$rid | Out-Null",
  "    }",
  "  }",
  "} catch {}",
  "# === STAGE8E_COMMIT_AFTER_SUBMIT END ==="
)

$releaseHook = @(
  "# === STAGE8E_RELEASE_ON_ERROR BEGIN ===",
  "try {",
  "  if(`$planObj -and (`$planObj.PSObject.Properties.Name -contains 'risk_rid')){",
  "    `$rid = [string]`$planObj.risk_rid",
  "    if(-not [string]::IsNullOrWhiteSpace(`$rid)){",
  "      STAGE8E-CallLedger -Action 'release' -Rid `$rid | Out-Null",
  "    }",
  "  }",
  "} catch {}",
  "# === STAGE8E_RELEASE_ON_ERROR END ==="
)

$dryHook = @(
  "# === STAGE8E_RELEASE_ON_DRYRUN BEGIN ===",
  "try {",
  "  if(`$planObj -and (`$planObj.PSObject.Properties.Name -contains 'risk_rid')){",
  "    `$rid = [string]`$planObj.risk_rid",
  "    if(-not [string]::IsNullOrWhiteSpace(`$rid)){",
  "      STAGE8E-CallLedger -Action 'release' -Rid `$rid | Out-Null",
  "    }",
  "  }",
  "} catch {}",
  "# === STAGE8E_RELEASE_ON_DRYRUN END ==="
)

# IMPORTANT: patterns match both `"order_submitted"` or `'order_submitted'` styles safely enough
$lines = Insert-AfterFirstMatch $lines 'kind\s*=\s*["'']order_submitted["'']' $commitHook
$lines = Insert-AfterFirstMatch $lines 'kind\s*=\s*["'']order_error["'']'     $releaseHook
$lines = Insert-AfterFirstMatch $lines 'kind\s*=\s*["'']dryrun_skip_submit["'']' $dryHook -Optional

# ---------------------------------------------------------
# 3) Write back
# ---------------------------------------------------------
$lines | Set-Content -LiteralPath $EXE -Encoding utf8
Unblock-File -LiteralPath $EXE -ErrorAction SilentlyContinue

# Audit head
($lines | Select-Object -First 220) | Set-Content (Join-Path $AUDIT_DIR "patched_head_220.txt") -Encoding utf8

Write-Host "STAGE8E_EXEC_PATCH_APPLIED=OK"
Write-Host "EXE=$EXE"
Write-Host "PATCH_DIR=$PATCH_DIR"
Write-Host "AUDIT_DIR=$AUDIT_DIR"
Write-Host "NEXT=RUN_PAPER_DIAG_PIPELINE (dryrun) سپس اگر fail شد: PASTE AUDIT_DIR\patched_head_220.txt"