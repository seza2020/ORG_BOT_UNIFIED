$ErrorActionPreference="Stop"

$ROOT = 'C:\alpaca-bot\ORG_BOT_UNIFIED'
$CODE = Join-Path $ROOT 'code'
$RUNROOT = Join-Path $ROOT 'runtime\paper'
$OPSLOG = Join-Path $RUNROOT 'logs\ops'
New-Item -ItemType Directory -Force -Path $OPSLOG | Out-Null

$EXEC = 'C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\paper\RUN_PAPER_EXECUTOR_TASK_V1.ps1'
$POLL = 'C:\alpaca-bot\ORG_BOT_UNIFIED\code\tools\paper\RUN_PAPER_ORDER_POLL_TASK_V1.ps1'

function Patch-File([string]$Path){
  if(!(Test-Path -LiteralPath $Path)){ throw ("FILE_NOT_FOUND=" + $Path) }
  $raw = Get-Content -LiteralPath $Path -Raw -Encoding utf8
  if([string]::IsNullOrWhiteSpace($raw)){ throw ("FILE_EMPTY=" + $Path) }

  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $PDIR = Join-Path $ROOT ("ops\patches\RUNROOT_FIX_SAFE_" + $stamp)
  New-Item -ItemType Directory -Force -Path $PDIR | Out-Null
  Copy-Item $Path (Join-Path $PDIR (([IO.Path]::GetFileName($Path)) + ".bak")) -Force

  if($raw -match "PAPER_RUNROOT_FORCE_UNIFIED"){
    Write-Host ("ALREADY_PATCHED=" + $Path)
    Write-Host ("BACKUP_DIR=" + $PDIR)
    return
  }

  $inject = @()
  $inject += "# === PAPER_RUNROOT_FORCE_UNIFIED BEGIN ==="
  $inject += '$env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"'
  $inject += '$env:TBOT_CODE = "C:\alpaca-bot\ORG_BOT_UNIFIED\code"'
  $inject += '$env:RUNROOT   = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"'
  $inject += '$env:TBOT_RUNROOT = $env:RUNROOT'
  $inject += '$env:TBOT_LOG_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs"'
  $inject += '$env:TBOT_OPS_LOG  = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\ops"'
  $inject += "# === PAPER_RUNROOT_FORCE_UNIFIED END ==="
  $inject += ""
  $injectText = ($inject -join "`r`n")

  # Replace legacy literal paths if present
  $raw2 = $raw -replace "C:\\alpaca-bot\\org_bot_runtime\\paper","C:\\alpaca-bot\\ORG_BOT_UNIFIED\\runtime\\paper"

  # Prepend force block
  $raw2 = $injectText + "`r`n" + $raw2

  Set-Content -LiteralPath $Path -Value $raw2 -Encoding utf8
  Unblock-File -LiteralPath $Path -ErrorAction SilentlyContinue
  Write-Host ("PATCHED=" + $Path)
  Write-Host ("BACKUP_DIR=" + $PDIR)
}

Patch-File $EXEC
Patch-File $POLL

Write-Host "RUNROOT_FIXED_TO_UNIFIED_SAFE=OK"
Write-Host "NEXT=RERUN_EXECUTOR_AND_POLL_ONCE_AND_CONFIRM_WROTE_OUT_PATHS"
