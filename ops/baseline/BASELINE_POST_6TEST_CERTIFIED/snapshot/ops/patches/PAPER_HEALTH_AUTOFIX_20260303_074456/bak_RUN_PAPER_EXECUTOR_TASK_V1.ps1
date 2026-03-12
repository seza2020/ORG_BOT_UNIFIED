$env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"
param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\\alpaca-bot\\ORG_BOT_UNIFIED\\runtime\\paper",
  [int]$MaxOrdersPerDay=1,
  [int]$MaxOrdersPerRun=1,
  [int]$DefaultQty=1,
  [int]$DryRun=1
)
# === LOG_APPEND_MODE_V2_SAFE BEGIN ===
$__APPEND_DIR = Join-Path "C:\alpaca-bot\ORG_BOT_UNIFIED" ("runtime\paper\logs\ops\_APPEND_" + (Get-Date -Format "yyyyMMdd"))
New-Item -ItemType Directory -Force -Path $__APPEND_DIR | Out-Null
$__OUT = Join-Path $__APPEND_DIR "PAPER_EXEC_OUT_APPEND.txt"
$__ERR = Join-Path $__APPEND_DIR "PAPER_EXEC_ERR_APPEND.txt"
# === LOG_APPEND_MODE_V2_SAFE END ===

# === PAPER_RUNROOT_FORCE_UNIFIED BEGIN ===
$env:TBOT_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$env:TBOT_CODE = "C:\alpaca-bot\ORG_BOT_UNIFIED\code"
$env:RUNROOT   = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper"
$env:TBOT_RUNROOT = $env:RUNROOT
$env:TBOT_LOG_ROOT = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs"
$env:TBOT_OPS_LOG  = "C:\alpaca-bot\ORG_BOT_UNIFIED\runtime\paper\logs\ops"
# === PAPER_RUNROOT_FORCE_UNIFIED END ===

$ErrorActionPreference="Stop"
$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $ops ("PAPER_EXEC_OUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("PAPER_EXEC_ERR_{0}.txt" -f $ts)

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
  -File (Join-Path $ProjectRoot "tools\paper\EXECUTE_PLAN_SELECTION_PAPER_V2.ps1") `
  -ProjectRoot $ProjectRoot -RunRoot $RunRoot -MaxOrdersPerDay $MaxOrdersPerDay -MaxOrdersPerRun $MaxOrdersPerRun -DefaultQty $DefaultQty -DryRun $DryRun `
  1> $out 2> $err

"WROTE_OUT=$out"
"WROTE_ERR=$err"





