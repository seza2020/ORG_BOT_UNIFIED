param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath
)

$ErrorActionPreference="Stop"
$ROOT = $ProjectRoot
$PY   = Join-Path $ROOT ".venv\Scripts\python.exe"
if(!(Test-Path -LiteralPath $PY)){ throw "Missing python venv: $PY" }

$prof = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$RunRoot = [string]$prof.runroot
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_MISSING_IN_PROFILE" }
if(!(Test-Path -LiteralPath $RunRoot)){ throw "Missing RunRoot: $RunRoot" }

# Canonical env under runroot (kills TBOT_FILELOG_PATH drift)
$env:TBOT_RUNROOT = $RunRoot
$env:TBOT_RUNTIME = $RunRoot
$env:TBOT_FILELOG_PATH = Join-Path $RunRoot 'logs\bot_console_{date}.log'

# Force python to print tracebacks on fatal errors
$env:PYTHONFAULTHANDLER = "1"

$Logs = Join-Path $RunRoot "logs"
$Ops  = Join-Path $Logs "ops"
New-Item -ItemType Directory -Force -Path $Logs,$Ops | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$rep = Join-Path $Ops ("FOREGROUND_DIAG_{0}.txt" -f $ts)

$a = $prof.args
$Meta    = Join-Path $Logs "meta.jsonl"
$Ann     = Join-Path $Logs "announce.log"
$Ledger  = Join-Path $Logs "trades"
$ShadowP = Join-Path $Logs "shadow_plans.jsonl"

$argList = @("-u","-m","tbot.main","--run",
  "--iters",[string]$a.iters,
  "--sleep",[string]$a.sleep,
  "--meta",$Meta,
  "--announce",$Ann,
  "--ledger_dir",$Ledger
)
if([bool]$a.shadow){
  $argList += @("--shadow","--shadow_path",$ShadowP)
}
$argList += @(
  "--gate_min_rr",[string]$a.gate_min_rr,
  "--gate_min_conf",[string]$a.gate_min_conf,
  "--gate_cooldown_sec",[string]$a.gate_cooldown_sec,
  "--gate_max_plans_per_day",[string]$a.gate_max_plans_per_day,
  "--gate_max_risk_per_trade_usd",[string]$a.gate_max_risk_per_trade_usd,
  "--gate_max_risk_per_day_usd",[string]$a.gate_max_risk_per_day_usd
)

"REPORT=$rep" | Out-File -LiteralPath $rep -Encoding utf8
"CMD=$PY $($argList -join ' ')" | Out-File -LiteralPath $rep -Encoding utf8 -Append

& $PY @argList *>&1 | Tee-Object -FilePath $rep
$code = $LASTEXITCODE
"EXITCODE=$code" | Tee-Object -FilePath $rep -Append

if($code -ne 0){
  "`n=== TAIL(200) ===" | Tee-Object -FilePath $rep -Append
  Get-Content -LiteralPath $rep -Tail 200
  exit $code
}

"OK=1" | Tee-Object -FilePath $rep -Append
exit 0