param(
  [int]$Iters = 1,
  [double]$Sleep = 0.1
)

$ErrorActionPreference="Stop"

function Pass([string]$m){ Write-Output ("PASS: " + $m) }
function Fail([string]$m){ Write-Output ("FAIL: " + $m); exit 2 }

$UnifiedRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OpsDir      = Join-Path $UnifiedRoot "ops"
$RunProfile  = Join-Path $OpsDir "RUN_PROFILE.ps1"
$WrapP       = Join-Path $OpsDir "task_wrappers\ORG_UNIFIED_PAPER_RUN.ps1"
$WrapS       = Join-Path $OpsDir "task_wrappers\ORG_UNIFIED_SHADOW_RUN.ps1"
$TaskLogDir  = Join-Path $UnifiedRoot "runtime\logs\tasks"

$Required = @($RunProfile,$WrapP,$WrapS)
$missing = @()
foreach($p in $Required){ if(!(Test-Path $p)){ $missing += $p } }
if($missing.Count -gt 0){
  "MISSING_FILES=" + ($missing -join "; ")
  Fail "FILES_MISSING"
}
New-Item -ItemType Directory -Force -Path $TaskLogDir | Out-Null
Pass "FILES_EXIST"

function Get-RunProfileOut([string]$Profile,[int]$I,[double]$S){
  $rp = $RunProfile
  $pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"
  $out = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $rp -Profile $Profile -Iters $I -Sleep $S 2>&1
  # normalize to string lines (critical)
  return @($out | ForEach-Object { [string]$_ })
}

function Extract-CmdLine([string[]]$Lines){
  if(!$Lines){ return "" }
  $hits = $Lines | Where-Object { $_ -match '\[RUN_PROFILE\].*CMD\:' }
  if(!$hits){ return "" }
  return ($hits | Select-Object -Last 1)
}

$outP = Get-RunProfileOut -Profile "PAPER"  -I $Iters -S $Sleep
$outS = Get-RunProfileOut -Profile "SHADOW" -I $Iters -S $Sleep

$pCmd = Extract-CmdLine -Lines $outP
$sCmd = Extract-CmdLine -Lines $outS

"PAPER_CMD_LINE=" + $pCmd
"SHADOW_CMD_LINE=" + $sCmd

if([string]::IsNullOrWhiteSpace($pCmd)){ Fail "PAPER_CMD_EMPTY" }
if([string]::IsNullOrWhiteSpace($sCmd)){ Fail "SHADOW_CMD_EMPTY" }

# Policy gates
if($pCmd -match '\s--shadow\b'){ Fail "PAPER_HAS_SHADOW_FLAG" }
if($pCmd -match 'shadow_path'){ Fail "PAPER_HAS_SHADOW_PATH" }
if($pCmd -notmatch '\-m\s+tbot\.main'){ Fail "PAPER_MISSING_ENTRYPOINT" }

if($sCmd -notmatch '\s--shadow\b'){ Fail "SHADOW_MISSING_SHADOW_FLAG" }
if($sCmd -notmatch 'shadow_path'){ Fail "SHADOW_MISSING_SHADOW_PATH" }
if($sCmd -notmatch '\-m\s+tbot\.main'){ Fail "SHADOW_MISSING_ENTRYPOINT" }

Pass "CMD_POLICY_OK"
exit 0
