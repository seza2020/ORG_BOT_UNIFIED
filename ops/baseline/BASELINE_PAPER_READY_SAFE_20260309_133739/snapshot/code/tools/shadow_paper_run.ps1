# File: tools/shadow_paper_run.ps1
param(
  [int]$Iters = 600,
  [double]$Sleep = 1.0,
  [string]$Symbols = "SPY,QQQ,IWM,NVDA,AAPL",
  [double]$GateMinConf = 0.0,
  [double]$RiskUsd = 250.0
)

$ErrorActionPreference = "Stop"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path (Resolve-Path ".\logs").Path ("shadow_paper_" + $ts)
New-Item -ItemType Directory -Force $outDir | Out-Null

$meta = Join-Path $outDir "meta.jsonl"
$ann  = Join-Path $outDir "announce.log"
$shadow = Join-Path $outDir "shadow_plans.jsonl"

"OUTDIR=$outDir"
"META=$meta"
"ANN=$ann"
"SHADOW=$shadow"
"SYMBOLS=$Symbols"

# Run in session override for testing stability (remove later for live clock)
python -m tbot.main --run `
  --iters $Iters `
  --sleep $Sleep `
  --meta $meta `
  --announce $ann `
  --shadow `
  --shadow_path $shadow `
  --gate_min_conf $GateMinConf `
  --risk_usd $RiskUsd `
  --sim_in_session 1 `
  --sim_pre_close 0

"EXITCODE(run)=$LASTEXITCODE"

python .\tools\scorecard_daily.py --meta $meta
"EXITCODE(scorecard)=$LASTEXITCODE"
