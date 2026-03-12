param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [string]$Pwsh = "C:\Program Files\PowerShell\7\pwsh.exe",
  [string]$TaskPreflight = "TBOT_PAPER_PREFLIGHT_0629_SYSTEM",
  [string]$TaskRunner = "TBOT_RUN_SHADOW_DAILY_0630"
)

$ErrorActionPreference="Stop"

function Q([string]$s){ '"' + ($s -replace '"','\"') + '"' }

$pre = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_CANON_V1.ps1"
$run = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"

if(!(Test-Path $pre)){ throw "MISSING_PREFLIGHT=$pre" }
if(!(Test-Path $run)){ throw "MISSING_RUNNER=$run" }
if(!(Test-Path $Pwsh)){ throw "MISSING_PWSH=$Pwsh" }

# marker written by preflight when OK
$markerDir = Join-Path (Join-Path $RunRoot "logs") "ops"
New-Item -ItemType Directory -Force -Path $markerDir | Out-Null
$marker = Join-Path $markerDir "PREFLIGHT_OK.marker"

# 1) Write chain wrapper: only run if preflight marker is fresh
$chain = Join-Path $Root "tools\ops\PAPER_CHAIN_RUNNER_V1.ps1"
@"
param(
  [string]\$Root = $(Q $Root),
  [string]\$RunRoot = $(Q $RunRoot)
)
\$ErrorActionPreference="Stop"
\$L = Join-Path \$RunRoot "logs"
\$marker = Join-Path (Join-Path \$L "ops") "PREFLIGHT_OK.marker"
\$runner = Join-Path \$Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"

if(!(Test-Path \$marker)){
  Write-Host "[CHAIN] NO_MARKER -> block runner"
  exit 2
}

# freshness: must be within last 20 minutes
\$ageMin = ((Get-Date) - (Get-Item \$marker).LastWriteTime).TotalMinutes
if(\$ageMin -gt 20){
  Write-Host "[CHAIN] STALE_MARKER ageMin=\$ageMin -> block runner"
  exit 3
}

Write-Host "[CHAIN] OK -> launch runner"
& "$Pwsh" -NoProfile -ExecutionPolicy Bypass -File \$runner -Root \$Root -RunRoot \$RunRoot
exit \$LASTEXITCODE
"@ | Set-Content -Encoding UTF8 -LiteralPath $chain

Write-Host "WROTE_CHAIN=$chain"

# 2) Ensure Preflight task exists (SYSTEM @ 06:29)
# Create or update with exact TR
$trPre = "$(Q $Pwsh) -NoProfile -ExecutionPolicy Bypass -File $(Q $pre) -Root $(Q $Root) -RunRoot $(Q $RunRoot)"
$existsPre = (schtasks /query /tn $TaskPreflight 2>$null) -ne $null

if(-not $existsPre){
  schtasks /create /tn $TaskPreflight /sc daily /st 06:29 /ru SYSTEM /rl HIGHEST /f `
    /tr $trPre | Out-Null
  Write-Host "[OK] CREATED_PREFLIGHT_TASK=$TaskPreflight"
}else{
  schtasks /change /tn $TaskPreflight /tr $trPre | Out-Null
  Write-Host "[OK] UPDATED_PREFLIGHT_TASK_TR=$TaskPreflight"
}

# 3) Fix Runner task (User @ 06:30) to chain wrapper (not preflight)
$trRun = "$(Q $Pwsh) -NoProfile -ExecutionPolicy Bypass -File $(Q $chain) -Root $(Q $Root) -RunRoot $(Q $RunRoot)"
schtasks /change /tn $TaskRunner /tr $trRun | Out-Null
Write-Host "[OK] UPDATED_RUNNER_TASK_TR=$TaskRunner"

# 4) Harden: Preflight should write marker on success (append-safe)
# If preflight already writes it, ok; otherwise we add a tiny post-step hook by dropping a known hook file
$hook = Join-Path $Root "tools\ops\PAPER_PREFLIGHT_POST_OK_HOOK_V1.ps1"
@"
param([string]\$RunRoot=$(Q $RunRoot))
\$ErrorActionPreference="Stop"
\$markerDir = Join-Path (Join-Path \$RunRoot "logs") "ops"
New-Item -ItemType Directory -Force -Path \$markerDir | Out-Null
\$marker = Join-Path \$markerDir "PREFLIGHT_OK.marker"
"OK $(Get-Date -Format o)" | Set-Content -Encoding UTF8 -LiteralPath \$marker
Write-Host "[HOOK] WROTE_MARKER=\$marker"
"@ | Set-Content -Encoding UTF8 -LiteralPath $hook
Write-Host "WROTE_HOOK=$hook"

Write-Host ""
Write-Host "NEXT: Ensure preflight calls the hook on success."
Write-Host "If your PAPER_PREFLIGHT_CANON_V1 already writes marker, you can ignore the hook."
Write-Host ""

# 5) Show final task lines
schtasks /query /tn $TaskPreflight /v /fo LIST | findstr /i "TaskName Next Run Time Last Run Time Last Result Run As User Logon Mode Task To Run"
schtasks /query /tn $TaskRunner    /v /fo LIST | findstr /i "TaskName Next Run Time Last Run Time Last Result Run As User Logon Mode Task To Run"

Write-Host ""
Write-Host "GO: pipeline enforced (Preflight -> Marker -> Runner)"
