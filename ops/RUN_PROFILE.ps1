param(
  [Parameter(Mandatory=$true)][ValidateSet("PAPER","SHADOW")][string]$Profile,
  [int]$Iters = 999999999,
  [double]$Sleep = 0.1,

  [int]$GateCooldownSec = 300,
  [int]$GateMaxPlansPerDay = 15,
  [double]$GateMinRr = 1.5,
  [double]$GateMinConf = 0.55,
  [double]$GateMaxRiskUsd = 500,

  [double]$ShadowRiskUsd = 50
)

$ErrorActionPreference="Stop"

function Die([string]$msg,[int]$code=1){
  Write-Output ("[RUN_PROFILE] FATAL: {0}" -f $msg)
  exit $code
}

$UnifiedRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$PythonExe   = Join-Path $UnifiedRoot ".venv\Scripts\python.exe"
if(!(Test-Path $PythonExe)){ Die "python.exe not found at $PythonExe" 11 }

$ProfilesDir = Join-Path $UnifiedRoot "configs\profiles"
$ProfilePath = Join-Path $ProfilesDir ("{0}.profile.json" -f $Profile.ToLower())
if(!(Test-Path $ProfilePath)){ Die "Profile JSON not found: $ProfilePath" 12 }

# RunRoot (strict unified)
$RunRoot = if($Profile -eq "PAPER"){ Join-Path $UnifiedRoot "runtime\paper" } else { Join-Path $UnifiedRoot "runtime\shadow" }
New-Item -ItemType Directory -Force -Path (Join-Path $RunRoot "logs")  | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $RunRoot "state") | Out-Null

# Secrets loader (strict unified)
$Loader = Join-Path $UnifiedRoot "ops\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path $Loader)){ Die "Unified secrets loader not found: $Loader" 13 }

$SecretRootVault = Join-Path $UnifiedRoot "ops\secrets\vault"
if(!(Test-Path $SecretRootVault)){ Die "Unified secrets vault not found: $SecretRootVault" 14 }

# Load secrets into env for this process
. $Loader -Profile $Profile -ProjectRoot $UnifiedRoot -RunRoot $RunRoot -SecretRoot $SecretRootVault | Out-Null

# ShadowPath (ONLY used in SHADOW)
$ShadowPath = Join-Path $RunRoot "logs\shadow_plans.jsonl"

# --- PYTHONPATH/CWD ENFORCE (tbot is under code/) ---
$CodeRoot = Join-Path $UnifiedRoot "code"
if(Test-Path (Join-Path $CodeRoot "tbot")){
  Set-Location $CodeRoot
  $env:PYTHONPATH = $CodeRoot
} else {
  Die "tbot package not found under $CodeRoot" 21
}
# --- /PYTHONPATH/CWD ENFORCE ---

# --- HARD ENV OVERRIDES (anti-contamination) ---
# Force canonical PYTHONPATH to unified code root (ignore user profile pollution)
$env:PYTHONPATH = $CodeRoot

# Force per-run log path inside RunRoot (do not inherit IBKR or other projects)
if([string]::IsNullOrWhiteSpace([string]$RunRoot)){
  throw "RunRoot missing (cannot set TBOT_FILELOG_PATH)"
}
$env:TBOT_FILELOG_PATH = (Join-Path $RunRoot "logs\bot_console_{date}.log")

# Force profile marker for observability/audit
if(-not [string]::IsNullOrWhiteSpace([string]$Profile)){
  $env:TBOT_PROFILE = $Profile
}
# --- /HARD ENV OVERRIDES ---

# Always call: python -u -m tbot.main ...
$args = @(
  "-u",
  "-m","tbot.main",
  "--run",
  "--iters",$Iters,
  "--sleep",$Sleep,
  "--gate_cooldown_sec",$GateCooldownSec,
  "--gate_max_plans_per_day",$GateMaxPlansPerDay,
  "--gate_min_rr",$GateMinRr,
  "--gate_min_conf",$GateMinConf,
  "--gate_max_risk_usd",$GateMaxRiskUsd
)

if($Profile -eq "SHADOW"){
  $args += @("--shadow","--shadow_risk_usd",$ShadowRiskUsd,"--shadow_path",$ShadowPath)
}

# Emit CMD to stdout + persist for audit (no regex needed later)
$cmdLine = ('[RUN_PROFILE] CMD: {0} {1}' -f $PythonExe, ($args -join ' '))
Write-Output $cmdLine

$OpsLogs = Join-Path $UnifiedRoot "ops\logs"
New-Item -ItemType Directory -Force -Path $OpsLogs | Out-Null
Set-Content -LiteralPath (Join-Path $OpsLogs ("LAST_CMD_{0}.txt" -f $Profile)) -Encoding UTF8 -Value $cmdLine

# Execute
& $PythonExe @args
exit $LASTEXITCODE



