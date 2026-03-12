$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\ORG_BOT_UNIFIED"
$CODE=Join-Path $ROOT "code"
$RUNROOT=Join-Path $ROOT "runtime\paper"
$OPSLOG=Join-Path $RUNROOT "logs\ops"

New-Item -ItemType Directory -Force -Path $OPSLOG | Out-Null

function Patch-File([string]$Path){
  if(!(Test-Path -LiteralPath $Path)){ throw "FILE_NOT_FOUND=$Path" }

  $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ throw "FILE_EMPTY=$Path" }

  # backup
  $pd = "C:\alpaca-bot\ORG_BOT_UNIFIED\ops\patches\RUNROOT_FIX_20260303_063330"
  New-Item -ItemType Directory -Force -Path $pd | Out-Null
  Copy-Item $Path (Join-Path $pd ([IO.Path]::GetFileName($Path)+".bak")) -Force

  # If script already has a runroot block, do not double-inject
  if($raw -match "PAPER_RUNROOT_FORCE_UNIFIED"){
    Write-Host ("ALREADY_PATCHED=" + $Path)
    return
  }

  # Force env + runroot at top
  $inject = @(
    "# === PAPER_RUNROOT_FORCE_UNIFIED BEGIN ===",
    "$env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"",
    "$env:TBOT_CODE = "C:\alpaca-bot\ORG_BOT_UNIFIED\code"",
    "$env:RUNROOT   = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"",
    "$env:TBOT_RUNROOT = $env:RUNROOT",
    "$env:TBOT_LOG_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs"",
    "$env:TBOT_OPS_LOG   = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\ops"",
    "# === PAPER_RUNROOT_FORCE_UNIFIED END ===",
    ""
  ) -join "
"

  # Replace any legacy org_bot_runtime paper path literals
  $raw2 = $raw -replace "C:\\alpaca-bot\\org_bot_runtime\\paper", "C:\\alpaca-bot\\ORG_BOT_UNIFIED\\runtime\\paper"

  # Prepend inject
  $raw2 = $inject + $raw2

  Set-Content -LiteralPath $Path -Value $raw2 -Encoding utf8
  Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue

  Write-Host ("PATCHED=" + $Path)
  Write-Host ("BACKUP_DIR=" + $pd)
}

Patch-File "C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\paper\RUN_PAPER_EXECUTOR_TASK_V1.ps1"
Patch-File "C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\paper\RUN_PAPER_ORDER_POLL_TASK_V1.ps1"

Write-Host "RUNROOT_FIXED_TO_UNIFIED=OK"
Write-Host "NEXT=RERUN_EXECUTOR_AND_POLL_ONCE_AND_CONFIRM_WROTE_OUT_PATHS"
