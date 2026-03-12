param(
  [ValidateSet('smoke','run')]
  [string]$Mode = 'smoke',

  [int]$Iters = 999999,

  [double]$Sleep = 0.5
)

$ErrorActionPreference='Stop'

$ROOT='C:\alpaca-bot\ORG_BOT_UNIFIED'
$CODE=Join-Path $ROOT 'code'
$RUNROOT=Join-Path $ROOT 'runtime\paper'
$PY=Join-Path $CODE '.venv\Scripts\python.exe'

if(!(Test-Path -LiteralPath $PY)){ throw "PY_NOT_FOUND=$PY" }
if(!(Test-Path -LiteralPath $RUNROOT)){ throw "RUNROOT_NOT_FOUND=$RUNROOT" }

Set-Location $ROOT

# Hard env bind (canonical)
$env:PYTHONPATH=$CODE
$env:TBOT_PROFILE='paper'
$env:TBOT_RUNROOT=$RUNROOT

# Optional: keep console readable
$env:PYTHONUNBUFFERED='1'

Write-Host ("[RUNBOOK] ROOT=" + $ROOT)
Write-Host ("[RUNBOOK] CODE=" + $CODE)
Write-Host ("[RUNBOOK] RUNROOT=" + $RUNROOT)
Write-Host ("[RUNBOOK] PY=" + $PY)
Write-Host ("[RUNBOOK] MODE=" + $Mode)

if($Mode -eq 'smoke'){
  & $PY -u -m tbot.main --smoke
  exit $LASTEXITCODE
}

# Mode=run
& $PY -u -m tbot.main --run --iters $Iters --sleep $Sleep
exit $LASTEXITCODE
