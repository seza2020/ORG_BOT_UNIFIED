param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath
)
$ErrorActionPreference="Stop"

function Fail([string]$msg){
  Write-Host "PRECHECK_FAIL: $msg"
  exit 91
}

if(!(Test-Path -LiteralPath $ProjectRoot)){ Fail "ProjectRoot missing: $ProjectRoot" }
if(!(Test-Path -LiteralPath $ProfilePath)){ Fail "ProfilePath missing: $ProfilePath" }

$prof = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
$runroot = [string]$prof.runroot
$secrets = [string]$prof.secrets_ps1

if([string]::IsNullOrWhiteSpace($runroot)){ Fail "profile.runroot missing" }
if([string]::IsNullOrWhiteSpace($secrets)){ Fail "profile.secrets_ps1 missing" }

# Canon runroot must exist (create structure if needed)
New-Item -ItemType Directory -Force $runroot | Out-Null
New-Item -ItemType Directory -Force (Join-Path $runroot "logs") | Out-Null
New-Item -ItemType Directory -Force (Join-Path $runroot "logs\ops") | Out-Null

# Python venv sanity
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path -LiteralPath $py)){ Fail "python venv not found: $py" }

# Ensure TBOT_RUNROOT (if set) matches profile.runroot
if($env:TBOT_RUNROOT -and ($env:TBOT_RUNROOT -ne $runroot)){
  Fail "TBOT_RUNROOT mismatch. env=$($env:TBOT_RUNROOT) profile=$runroot"
}

# Ensure filelog path is under runroot if provided
if($env:TBOT_FILELOG_PATH){
  if($env:TBOT_FILELOG_PATH -notlike "$runroot*"){
    Fail "TBOT_FILELOG_PATH must be under runroot. got=$($env:TBOT_FILELOG_PATH) runroot=$runroot"
  }
}

Write-Host "PRECHECK_PASS: runroot=$runroot"
exit 0
