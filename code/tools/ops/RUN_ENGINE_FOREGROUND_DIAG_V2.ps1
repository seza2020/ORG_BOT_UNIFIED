param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath
)

$ErrorActionPreference="Stop"

if([string]::IsNullOrWhiteSpace($ProjectRoot)){ throw "ProjectRoot is empty" }
if([string]::IsNullOrWhiteSpace($ProfilePath)){ throw "ProfilePath is empty" }
if(!(Test-Path -LiteralPath $ProfilePath)){ throw "ProfilePath not found: $ProfilePath" }
if(!(Test-Path -LiteralPath $ProjectRoot)){ throw "ProjectRoot not found: $ProjectRoot" }

$prof = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$RunRoot = [string]$prof.runroot
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_MISSING_IN_PROFILE" }
if(!(Test-Path -LiteralPath $RunRoot)){ throw "RunRoot not found: $RunRoot" }

$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path -LiteralPath $py)){ throw "PY_MISSING: $py" }

$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $ops ("FOREGROUND_STDOUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("FOREGROUND_STDERR_{0}.txt" -f $ts)

# args (same as runner)
$a = $prof.args
$meta   = Join-Path $RunRoot "logs\meta.jsonl"
$ann    = Join-Path $RunRoot "logs\announce.log"
$ledger = Join-Path $RunRoot "logs\trades"
$shadowP= Join-Path $RunRoot "logs\shadow_plans.jsonl"

$args = @("-u","-m","tbot.main","--run",
  "--iters",[string]$a.iters,
  "--sleep",[string]$a.sleep,
  "--meta",$meta,
  "--announce",$ann,
  "--ledger_dir",$ledger
)
if([bool]$a.shadow){
  $args += @("--shadow","--shadow_path",$shadowP)
}
$args += @(
  "--gate_min_rr",[string]$a.gate_min_rr,
  "--gate_min_conf",[string]$a.gate_min_conf,
  "--gate_cooldown_sec",[string]$a.gate_cooldown_sec,
  "--gate_max_plans_per_day",[string]$a.gate_max_plans_per_day,
  "--gate_max_risk_per_trade_usd",[string]$a.gate_max_risk_per_trade_usd,
  "--gate_max_risk_per_day_usd",[string]$a.gate_max_risk_per_day_usd
)

"RUNROOT=$RunRoot" | Out-File -Encoding utf8 $out
"PY=$py"           | Out-File -Encoding utf8 $out -Append
("ARGS=" + ($args -join " ")) | Out-File -Encoding utf8 $out -Append

& $py @args 1>>$out 2>>$err
$code = $LASTEXITCODE
"EXITCODE=$code" | Out-File -Encoding utf8 $out -Append

"STDOUT=$out"
"STDERR=$err"
"EXITCODE=$code"

"=== STDERR TAIL(200) ==="
if(Test-Path -LiteralPath $err){ Get-Content -LiteralPath $err -Tail 200 } else { "NO_STDERR_FILE" }

"=== STDOUT TAIL(200) ==="
if(Test-Path -LiteralPath $out){ Get-Content -LiteralPath $out -Tail 200 } else { "NO_STDOUT_FILE" }

exit $code