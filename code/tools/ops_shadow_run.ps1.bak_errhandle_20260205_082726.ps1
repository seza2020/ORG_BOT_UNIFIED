param(
  [int]$iters = 240,
  [double]$sleep = 0.25,
  [double]$gate_min_rr = 1.0,
  [double]$gate_min_conf = 0.0,
  [int]$gate_cooldown_sec = 300,
  [int]$gate_max_plans_per_day = 20,
  [double]$gate_max_risk_usd = 500.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

cd C:\alpaca-bot\org_bot
New-Item -ItemType Directory -Force -Path .\logs\ops | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

$outRun  = "C:\alpaca-bot\org_bot\logs\ops\RUN_{0}.txt"      -f $ts
$outEnv  = "C:\alpaca-bot\org_bot\logs\ops\ENV_{0}.txt"      -f $ts
$outComp = "C:\alpaca-bot\org_bot\logs\ops\PYCOMPILE_{0}.txt" -f $ts
$outGrep = "C:\alpaca-bot\org_bot\logs\ops\GREP_{0}.txt"     -f $ts
$outKpi  = "C:\alpaca-bot\org_bot\logs\ops\KPI_{0}.txt"      -f $ts

$announceLog = "C:\alpaca-bot\org_bot\logs\announce.log"
$shadowJsonl = "C:\alpaca-bot\org_bot\logs\shadow_plans.jsonl"

function Tail-File([string]$dst,[string]$src,[int]$n){
  if (Test-Path $src) {
    "" | Add-Content -LiteralPath $dst -Encoding UTF8
    ("=== TAIL {0} : {1} ===" -f $n, $src) | Add-Content -LiteralPath $dst -Encoding UTF8
    Get-Content -LiteralPath $src -Tail $n -ErrorAction SilentlyContinue | Add-Content -LiteralPath $dst -Encoding UTF8
  }
}

function Grep-Lines([string]$dst,[string]$src,[string[]]$patterns,[int]$tailN){
  if (!(Test-Path $src)) { return }
  $data = Get-Content -LiteralPath $src -Tail $tailN -ErrorAction SilentlyContinue
  $hit = foreach ($line in $data) {
    foreach ($p in $patterns) {
      if ($line -match $p) { $line; break }
    }
  }
  $hit | Set-Content -LiteralPath $dst -Encoding UTF8
}

function Build-Kpi([string]$dst,[string]$src){
  if (!(Test-Path $src)) { return }
  $data = Get-Content -LiteralPath $src -ErrorAction SilentlyContinue
  $k = [ordered]@{
    boot          = ($data | Select-String -Pattern "boot\s+\{" -AllMatches).Matches.Count
    regime        = ($data | Select-String -Pattern "regime\s+\{" -AllMatches).Matches.Count
    core_context  = ($data | Select-String -Pattern "core_context\s+\{" -AllMatches).Matches.Count
    alpha_mode    = ($data | Select-String -Pattern "alpha_mode\s+\{" -AllMatches).Matches.Count
    signal_fire   = ($data | Select-String -Pattern "signal_fire" -AllMatches).Matches.Count
    signal_skip   = ($data | Select-String -Pattern "signal_skip" -AllMatches).Matches.Count
    s01_signal    = ($data | Select-String -Pattern "strategy_result\s+\{'sid': 'S01'.*returned': 'SIGNAL'" -AllMatches).Matches.Count
    s11_signal    = ($data | Select-String -Pattern "strategy_result\s+\{'sid': 'S11'.*returned': 'SIGNAL'" -AllMatches).Matches.Count
    shadow_accept = ($data | Select-String -Pattern "shadow_accept" -AllMatches).Matches.Count
    shadow_reject = ($data | Select-String -Pattern "shadow_reject" -AllMatches).Matches.Count
    shadow_plan   = ($data | Select-String -Pattern "shadow_plan" -AllMatches).Matches.Count
    cooldown      = ($data | Select-String -Pattern "cooldown_active" -AllMatches).Matches.Count
  }
  ($k.GetEnumerator() | ForEach-Object { "{0}={1}" -f $_.Key, $_.Value }) | Set-Content -LiteralPath $dst -Encoding UTF8
}

# 1) ENV snapshot
@(
  "TIME=$ts"
  "PWD=$(Get-Location)"
  ""
  "TBOT_ENABLE_S01_LOGIC=$env:TBOT_ENABLE_S01_LOGIC"
  "TBOT_S01_MIN_STRENGTH=$env:TBOT_S01_MIN_STRENGTH"
  "TBOT_ENABLE_S11_MVP=$env:TBOT_ENABLE_S11_MVP"
  ""
) | Set-Content -LiteralPath $outEnv -Encoding UTF8

# 2) PYCOMPILE snapshot (add more files if you want)
@(
  "python -m py_compile .\tbot\strategies\s01_core.py"
  "python -m py_compile .\tbot\strategies\s11_alpha.py"
  "python -m py_compile .\tbot\runtime\orchestrator.py"
) | Set-Content -LiteralPath $outComp -Encoding UTF8
python -m py_compile .\tbot\strategies\s01_core.py 2>&1 | Add-Content -LiteralPath $outComp -Encoding UTF8
python -m py_compile .\tbot\strategies\s11_alpha.py 2>&1 | Add-Content -LiteralPath $outComp -Encoding UTF8
python -m py_compile .\tbot\runtime\orchestrator.py 2>&1 | Add-Content -LiteralPath $outComp -Encoding UTF8

# 3) RUN
$cmd = @(
  "python","-m","tbot.main",
  "--run",
  "--iters","$iters",
  "--sleep","$sleep",
  "--shadow",
  "--gate_min_rr","$gate_min_rr",
  "--gate_min_conf","$gate_min_conf",
  "--gate_cooldown_sec","$gate_cooldown_sec",
  "--gate_max_plans_per_day","$gate_max_plans_per_day",
  "--gate_max_risk_usd","$gate_max_risk_usd"
)

("CMD: " + ($cmd -join " ")) | Set-Content -LiteralPath $outRun -Encoding UTF8

$exe  = $cmd[0]
$args = @($cmd[1..($cmd.Count-1)])

& $exe @args 2>&1 | Tee-Object -FilePath $outRun | Out-Null

# 4) Tail key logs into RUN file
Tail-File $outRun $announceLog 200
Tail-File $outRun $shadowJsonl 60

# 5) Grep highlights
$patterns = @(
  "boot\s+\{",
  "regime\s+\{",
  "core_context\s+\{",
  "alpha_mode\s+\{",
  "signal_fire",
  "signal_skip",
  "strategy_result\s+\{'sid': 'S01'",
  "strategy_result\s+\{'sid': 'S11'",
  "shadow_accept",
  "shadow_reject",
  "shadow_plan",
  "cooldown_active",
  "TBOT_ENABLE_S01_LOGIC",
  "TBOT_S01_MIN_STRENGTH",
  "TBOT_ENABLE_S11_MVP"
)
Grep-Lines $outGrep $outRun $patterns 600

# 6) KPI summary
Build-Kpi $outKpi $outRun

"OUT_RUN=$outRun"
"OUT_ENV=$outEnv"
"OUT_PYCOMPILE=$outComp"
"OUT_GREP=$outGrep"
"OUT_KPI=$outKpi"
