param(
  [int]$Iters = 999999,
  [double]$Sleep = 15.0
)

$ErrorActionPreference="Stop"

$ROOT="C:\alpaca-bot\org_bot"
$PY="C:\Python313\python.exe"

Set-Location $ROOT

# Secrets
. C:\alpaca-bot\secrets\alpaca_env.ps1

# PYTHONPATH
$env:PYTHONPATH = $ROOT

# Feed default
if(-not $env:TBOT_DATA_FEED){ $env:TBOT_DATA_FEED="iex" }

# Logs
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$LOGS = Join-Path $ROOT "logs"
New-Item -ItemType Directory -Force -Path $LOGS | Out-Null

$ann  = Join-Path $LOGS ("ann_shadow_live_{0}.log" -f $ts)
$meta = Join-Path $LOGS ("meta_shadow_live_{0}.jsonl" -f $ts)

Write-Host ("[RUN] shadow live iters={0} sleep={1}" -f $Iters, $Sleep)
Write-Host ("[RUN] ann={0}" -f $ann)
Write-Host ("[RUN] meta={0}" -f $meta)

& $PY -u -m tbot.main --run --iters $Iters --sleep $Sleep --shadow --announce $ann --meta $meta
exit $LASTEXITCODE
