param(
  [string]$ProjectRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED",
  [string]$RunRoot     = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper",
  [int]$MaxOrdersPerDay = 1,
  [int]$MaxOrdersPerRun = 1,
  [int]$DefaultQty      = 1,
  [int]$DryRun          = 1
)

$ErrorActionPreference="Stop"

# --- Canonical env bind (PS7-safe) ---
Set-Location (Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED" "code")
$env:PYTHONPATH    = (Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED" "code")
$env:TBOT_ROOT     = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$env:TBOT_CODE     = (Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED" "code")
$env:TBOT_RUNROOT  = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"
$env:TBOT_LOG_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs"
$env:TBOT_OPS_LOG  = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\ops"

New-Item -ItemType Directory -Force -Path $env:TBOT_OPS_LOG | Out-Null

# --- Daily logs (append) ---
$day = Get-Date -Format "yyyyMMdd"
$OUT = Join-Path $env:TBOT_OPS_LOG ("EXECSEL_OUT_{0}.txt" -f $day)
$ERR = Join-Path $env:TBOT_OPS_LOG ("EXECSEL_ERR_{0}.txt" -f $day)
New-Item -ItemType File -Force -Path $OUT | Out-Null
New-Item -ItemType File -Force -Path $ERR | Out-Null

function WL([string]$s){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  ("[{0}] {1}" -f $ts, $s) | Add-Content -LiteralPath $OUT -Encoding utf8
}
function WLE([string]$s){
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  ("[{0}] {1}" -f $ts, $s) | Add-Content -LiteralPath $ERR -Encoding utf8
}

WL "EXECSEL_V2_CANON_START"
WL ("CWD=" + (Get-Location))
WL ("ProjectRoot=" + $ProjectRoot)
WL ("RunRoot=" + $RunRoot)
WL ("DryRun=" + $DryRun)

# --- Hard bind ProjectRoot/RunRoot if empty ---
if([string]::IsNullOrWhiteSpace($ProjectRoot)){ $ProjectRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED" }
if([string]::IsNullOrWhiteSpace($RunRoot)){ $RunRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper" }

# --- Load secrets (silent) ---
try{
  $ldr = Join-Path $ProjectRoot "code\tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
  if(Test-Path -LiteralPath $ldr){
    & $ldr -Profile "PAPER" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null
    WL "SECRETS_LOADED_OK"
  } else {
    WLE ("SECRETS_LOADER_MISSING=" + $ldr)
  }
} catch {
  WLE ("SECRETS_LOAD_FAIL=" + $_.Exception.Message)
}

# --- DRY RUN SAFE EXIT (for stability today) ---
if([int]$DryRun -eq 1){
  WL "DRYRUN=1 -> SKIP_PLAN_SELECTION (STABILITY_MODE)"
  exit 0
}

# --- Attempt to call V1 implementation if present ---
try{
  $v1 = Join-Path $ProjectRoot "code\tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V1.ps1"
  if(Test-Path -LiteralPath $v1){
    WL ("FALLBACK_TO_V1=" + $v1)
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $v1 
      -ProjectRoot $ProjectRoot -RunRoot $RunRoot -MaxOrdersPerDay $MaxOrdersPerDay -MaxOrdersPerRun $MaxOrdersPerRun -DefaultQty $DefaultQty -DryRun 0 
      1>> $OUT 2>> $ERR
    WL "V1_DONE"
    exit 0
  } else {
    WLE ("V1_MISSING=" + $v1)
    exit 3
  }
} catch {
  WLE ("V1_CALL_FAIL=" + $_.Exception.Message)
  exit 4
}
