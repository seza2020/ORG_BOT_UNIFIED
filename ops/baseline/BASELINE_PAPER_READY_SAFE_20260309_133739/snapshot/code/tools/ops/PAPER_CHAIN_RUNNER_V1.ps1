param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper"
)

$ErrorActionPreference="Stop"

# CHAIN_MARKER_GATE_V1
if([string]::IsNullOrWhiteSpace($RunRoot) -or !(Test-Path $RunRoot)){
  $RunRoot = "C:\alpaca-bot\org_bot_runtime\paper"
}

$opsDir = Join-Path (Join-Path $RunRoot "logs") "ops"
New-Item -ItemType Directory -Force -Path $opsDir | Out-Null

$mark = Join-Path $opsDir "PREFLIGHT_OK.marker"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$auditDir = Join-Path (Join-Path $Root "logs") "ops\audit"
New-Item -ItemType Directory -Force -Path $auditDir | Out-Null
$log = Join-Path $auditDir ("PAPER_CHAIN_RUNNER_" + $ts + ".log")

"TS_LOCAL=$([DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss"))" | Tee-Object -FilePath $log -Append | Out-Host
"ROOT=$Root"   | Tee-Object -FilePath $log -Append | Out-Host
"RUNROOT=$RunRoot" | Tee-Object -FilePath $log -Append | Out-Host
"MARKER=$mark" | Tee-Object -FilePath $log -Append | Out-Host

if(!(Test-Path $mark)){
  "[STANDBY] NO_MARKER (Preflight not completed or marker missing). Exiting 0." | Tee-Object -FilePath $log -Append | Out-Host
  exit 0
}

# Consume marker (atomic-ish): rename marker so it cannot be reused
$consumed = Join-Path $opsDir ("PREFLIGHT_OK.consumed_" + $ts + ".marker")
Move-Item -Force -LiteralPath $mark -Destination $consumed
"[OK] MARKER_CONSUMED=$consumed" | Tee-Object -FilePath $log -Append | Out-Host

# Run the actual Paper runner (canonical)
$runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
if(!(Test-Path $runner)){
  "[NO_GO] RUNNER_MISSING=$runner" | Tee-Object -FilePath $log -Append | Out-Host
  exit 2
}
"[RUN] $runner" | Tee-Object -FilePath $log -Append | Out-Host

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $runner -Root $Root -RunRoot $RunRoot *>> $log 2>&1
$ec = $LASTEXITCODE
"RUNNER_EXITCODE=$ec" | Tee-Object -FilePath $log -Append | Out-Host

if($ec -ne 0){
  "[NO_GO] RUNNER_FAILED (see log)" | Tee-Object -FilePath $log -Append | Out-Host
  exit $ec
}

"[GO] CHAIN_OK" | Tee-Object -FilePath $log -Append | Out-Host
exit 0
