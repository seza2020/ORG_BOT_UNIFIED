$ErrorActionPreference="Stop"

$U="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $U "code"
$PAPER=Join-Path $CODE "tools\paper"
$SECRETS_LOADER=Join-Path $CODE "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"

$E_EXEC = Join-Path $PAPER "RUN_PAPER_EXECUTOR_TASK_V1.ps1"
$E_POLL = Join-Path $PAPER "RUN_PAPER_ORDER_POLL_TASK_V1.ps1"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$PDIR=Join-Path $U ("ops\patches\REBUILD_PAPER_TASK_SCRIPTS_" + $stamp)
$ADIR=Join-Path $U ("ops\audit\REBUILD_PAPER_TASK_SCRIPTS_" + $stamp)
New-Item -ItemType Directory -Force -Path $PDIR | Out-Null
New-Item -ItemType Directory -Force -Path $ADIR | Out-Null

function Ensure-SecretsOrFail {
  param([string]$Profile)

  if(!(Test-Path -LiteralPath $SECRETS_LOADER)){
    throw "SECRETS_LOADER_NOT_FOUND=$SECRETS_LOADER"
  }

  # We do NOT print/inspect secrets; only locate file existence.
  $cands = @(
    "C:\alpaca-bot\ORG_BOT_UNIFIED\secrets",
    "C:\alpaca-bot\secrets",
    "C:\alpaca-bot\org_bot_secrets"
  ) | Where-Object { Test-Path -LiteralPath $_ }

  $fname = "$Profile.keys.dpapi.json"
  $found = $null
  foreach($d in $cands){
    $p = Join-Path $d $fname
    if(Test-Path -LiteralPath $p){ $found = $p; break }
  }

  if(-not $found){
    throw ("MISSING_SECRETS_FILE: searched=" + ($cands -join ";") + " need=" + $fname)
  }

  # Prefer unified secrets dir. Copy file there if not already.
  $unifiedSecrets = "C:\alpaca-bot\ORG_BOT_UNIFIED\secrets"
  New-Item -ItemType Directory -Force -Path $unifiedSecrets | Out-Null
  $dst = Join-Path $unifiedSecrets $fname
  if(-not (Test-Path -LiteralPath $dst)){
    Copy-Item -LiteralPath $found -Destination $dst -Force
  }

  # Point runtime to unified root (and optionally secrets dir if loader supports it via env)
  $env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"
  $env:PYTHONPATH = $CODE
  $env:TBOT_SECRETS_DIR = $unifiedSecrets  # harmless if loader ignores
}

function Write-TaskScript {
  param(
    [Parameter(Mandatory=$true)][string]$TargetPath,
    [Parameter(Mandatory=$true)][ValidateSet("EXEC","POLL")][string]$Kind
  )

  Copy-Item -LiteralPath $TargetPath -Destination (Join-Path $PDIR ((Split-Path $TargetPath -Leaf) + ".bak")) -Force

  $body = @()
  $body += '$ErrorActionPreference="Stop"'
  $body += 'param('
  $body += '  [string]$Profile="paper",'
  $body += '  [string]$TBOT_ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED",'
  $body += '  [string]$RUNROOT="C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"'
  $body += ')'
  $body += ''
  $body += '$CODE = Join-Path $TBOT_ROOT "code"'
  $body += '$PAPER = Join-Path $CODE "tools\paper"'
  $body += '$SECRETS_LOADER = Join-Path $CODE "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"'
  $body += ''
  $body += '# ---- append logs (one folder per day) ----'
  $body += '$appendDir = Join-Path $RUNROOT ("logs\ops\_APPEND_" + (Get-Date -Format "yyyyMMdd"))'
  $body += 'New-Item -ItemType Directory -Force -Path $appendDir | Out-Null'
  if($Kind -eq "EXEC"){
    $body += '$OUT = Join-Path $appendDir "PAPER_EXEC_OUT_APPEND.txt"'
    $body += '$ERR = Join-Path $appendDir "PAPER_EXEC_ERR_APPEND.txt"'
    $body += '$DO  = Join-Path $PAPER "EXECUTE_PLAN_SELECTION_PAPER_V2.ps1"'
  } else {
    $body += '$OUT = Join-Path $appendDir "ORDER_POLL_OUT_APPEND.txt"'
    $body += '$ERR = Join-Path $appendDir "ORDER_POLL_ERR_APPEND.txt"'
    $body += '$DO  = Join-Path $PAPER "POLL_PAPER_ORDERS_V1.ps1"'
  }
  $body += ''
  $body += 'function WL([string]$s){ $ts=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Add-Content -LiteralPath $OUT -Value ("["+$ts+"] "+$s) }'
  $body += 'function WE([string]$s){ $ts=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Add-Content -LiteralPath $ERR -Value ("["+$ts+"] "+$s) }'
  $body += ''
  $body += 'try {'
  $body += '  $env:TBOT_ROOT = $TBOT_ROOT'
  $body += '  $env:PYTHONPATH = $CODE'
  $body += '  $env:RUNROOT = $RUNROOT'
  $body += '  $env:TBOT_SECRETS_DIR = Join-Path $TBOT_ROOT "secrets"'
  $body += ''
  $body += '  if(!(Test-Path -LiteralPath $SECRETS_LOADER)){ throw ("SECRETS_LOADER_NOT_FOUND=" + $SECRETS_LOADER) }'
  $body += '  $sf = Join-Path (Join-Path $TBOT_ROOT "secrets") ($Profile + ".keys.dpapi.json")'
  $body += '  if(!(Test-Path -LiteralPath $sf)){ throw ("MISSING_SECRETS_FILE=" + $sf) }'
  $body += ''
  $body += '  if(!(Test-Path -LiteralPath $DO)){ throw ("TASK_TARGET_NOT_FOUND=" + $DO) }'
  $body += '  WL ("RUN_START kind=' + $Kind + ' do=" + $DO)'
  $body += '  $o = & pwsh -NoProfile -ExecutionPolicy Bypass -File $DO 2>&1 | Out-String'
  $body += '  if($LASTEXITCODE -ne 0){ WE ("TASK_FAIL exit=" + $LASTEXITCODE); WE $o; throw ("TASK_FAILED_EXIT_" + $LASTEXITCODE) }'
  $body += '  WL ("TASK_OK")'
  $body += '} catch {'
  $body += '  WE ("EX=" + $_.Exception.Message)'
  $body += '  throw'
  $body += '}'

  Set-Content -LiteralPath $TargetPath -Value ($body -join "`r`n") -Encoding utf8
  Unblock-File -LiteralPath $TargetPath -ErrorAction SilentlyContinue
  "REBUILT=$TargetPath" | Out-Host
}

# Ensure secrets exist (copy to unified if needed)
Ensure-SecretsOrFail -Profile "paper"

# Rebuild scripts from scratch
Write-TaskScript -TargetPath $E_EXEC -Kind "EXEC"
Write-TaskScript -TargetPath $E_POLL -Kind "POLL"

"REBUILD_FROM_SCRATCH=OK" | Out-Host
"PATCH_DIR=$PDIR" | Out-Host
"AUDIT_DIR=$ADIR" | Out-Host
"NEXT=Run EXEC once + POLL once, then tail *_ERR_APPEND.txt under _APPEND_YYYYMMDD" | Out-Host
