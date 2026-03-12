param(
  [string]$ProjectRoot,
  [string]$RunRoot
)

$ErrorActionPreference = "Stop"

# --- Canonical roots (self-heal) ---
if([string]::IsNullOrWhiteSpace($ProjectRoot)){
  try{
    # ...\ORG_BOT_UNIFIED\code\tools\paper -> root is 3 parents up
    $ProjectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
  } catch {}
}
if([string]::IsNullOrWhiteSpace($ProjectRoot)){
  $ProjectRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED"
}
if([string]::IsNullOrWhiteSpace($RunRoot)){
  $RunRoot = Join-Path $ProjectRoot "runtime\paper"
}

$CODE   = Join-Path $ProjectRoot "code"
$LOGDIR = Join-Path $RunRoot "logs"
$OPSLOG = Join-Path $LOGDIR "ops"

New-Item -ItemType Directory -Force -Path $OPSLOG | Out-Null

# --- Env hard bind ---
Set-Location $CODE
$env:PYTHONPATH    = $CODE
$env:TBOT_ROOT     = $ProjectRoot
$env:TBOT_CODE     = $CODE
$env:TBOT_RUNROOT  = $RunRoot
$env:TBOT_LOG_ROOT = $LOGDIR
$env:TBOT_OPS_LOG  = $OPSLOG

# --- Secrets loader (canonical) ---
$ldr = Join-Path $ProjectRoot "code\tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path -LiteralPath $ldr)){
  throw "MISSING_LOADER=$ldr"
}

# Load PAPER profile secrets (no secret output)
& $ldr -Profile "PAPER" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# --- (Optional) call actual poll logic if you have it in another script ---
# If you later want this file to do more than secrets+env, wire it here.
# For now, we exit 0 so RUN_PAPER_ORDER_POLL_TASK_V1 can stay stable.

exit 0
