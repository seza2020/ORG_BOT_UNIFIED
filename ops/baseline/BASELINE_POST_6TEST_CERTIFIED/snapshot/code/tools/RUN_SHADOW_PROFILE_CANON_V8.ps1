param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath,
  [int]$Force = 0,
  [int]$ForceSimInSession = 1
)
$ErrorActionPreference="Stop"

function EnsureDir([string]$p){ if(!(Test-Path $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Finger([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $n=$s.Length
  ($s.Substring(0,[Math]::Min(4,$n)) + "****" + $s.Substring([Math]::Max(0,$n-4)))
}

# ----- paths -----
$ops = Join-Path $RunRoot "logs\ops"
$log = Join-Path $RunRoot "logs"
EnsureDir $ops; EnsureDir $log

$ymd = (Get-Date).ToString("yyyyMMdd")
$ts  = Get-Date -Format "yyyyMMdd_HHmmss"

$stampOut = Join-Path $ops ("LIVE_OUT_{0}_{1}.txt" -f $ymd,$ts)
$stampErr = Join-Path $ops ("LIVE_ERR_{0}_{1}.txt" -f $ymd,$ts)
$liveOutLatest = Join-Path $ops ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
$liveErrLatest = Join-Path $ops ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)

$hb   = Join-Path $ops "HEARTBEAT_SHADOW_RUNNER.txt"
$pidf = Join-Path $RunRoot "PID"

# ----- load profile -----
if(!(Test-Path $ProfilePath)){ throw ("MISSING_PROFILEPATH=" + $ProfilePath) }
$prof = Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json

# resolve RunRoot from profile if needed
if([string]::IsNullOrWhiteSpace($RunRoot)){
  if($prof.runroot){ $RunRoot=[string]$prof.runroot }
  elseif($prof.runtime){ $RunRoot=[string]$prof.runtime }
}
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_EMPTY" }

# enforce shadow runroot
if(([string]$RunRoot).ToLower() -notlike "*\shadow*"){ throw ("RUNROOT_NOT_SHADOW=" + $RunRoot) }

# ----- load secrets (no key printing) -----
$ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
. $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# ----- python path -----
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path $py)){ $py="python" }

# ----- stale/running PID handling -----
if((Test-Path $pidf) -and $Force -ne 1){
  $pidTxt = (Get-Content $pidf -ErrorAction SilentlyContinue | Select-Object -First 1)
  $pid = 0
  [int]::TryParse([string]$pidTxt, [ref]$pid) | Out-Null
  if($pid -gt 0){
    try{
      $p = Get-Process -Id $pid -ErrorAction Stop
      # still running -> don't start new
      @(
        ("ts=" + (Get-Date).ToString("s")),
        "core_exit=BLOCK_ALREADY_RUNNING",
        ("pid=" + $pid),
        ("key_id_fingerprint=" + (Finger ([string]$env:APCA_API_KEY_ID)))
      ) | Set-Content -Encoding UTF8 -Path $hb
      "BLOCK: already running pid=$pid" | Set-Content -Encoding UTF8 -Path $stampOut
      Copy-Item $stampOut $liveOutLatest -Force
      "" | Set-Content -Encoding UTF8 -Path $stampErr
      Copy-Item $stampErr $liveErrLatest -Force
      exit 0
    } catch {
      # stale pid -> clear
      Remove-Item $pidf -Force -ErrorAction SilentlyContinue
      "STALE_LOCK_CLEARED" | Set-Content -Encoding UTF8 -Path $stampOut
      "" | Set-Content -Encoding UTF8 -Path $stampErr
    }
  }
} else {
  Remove-Item $pidf -Force -ErrorAction SilentlyContinue
}

# ----- build args from profile (safe defaults) -----
$meta     = Join-Path $RunRoot "logs\meta.jsonl"
$announce = Join-Path $RunRoot "logs\announce_shadow.log"
$ledger   = Join-Path $RunRoot "logs\ledger"
EnsureDir $ledger

$minRR  = "1"
$minConf= "0"
$cdSec  = "45"
$maxPlans="150"
$maxRisk="500"

try{
  if($prof.gate){
    if($prof.gate.min_rr){ $minRR = [string]$prof.gate.min_rr }
    if($prof.gate.min_confidence){ $minConf = [string]$prof.gate.min_confidence }
    if($prof.gate.cooldown_sec){ $cdSec = [string]$prof.gate.cooldown_sec }
    if($prof.gate.max_plans_per_day){ $maxPlans = [string]$prof.gate.max_plans_per_day }
  }
  if($prof.risk){
    if($prof.risk.per_day_usd){ $maxRisk = [string]$prof.risk.per_day_usd }
  }
} catch {}

# NOTE: tbot expects --shadow_path VALUE (not positional path)
$argList = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999","--sleep","0.25",
  "--meta",$meta,
  "--announce",$announce,
  "--ledger_dir",$ledger,
  "--shadow",
  "--shadow_path",$RunRoot,
  "--gate_min_rr",$minRR,
  "--gate_min_conf",$minConf,
  "--gate_cooldown_sec",$cdSec,
  "--gate_max_plans_per_day",$maxPlans,
  "--gate_max_risk_usd",$maxRisk
)

if($ForceSimInSession -eq 1){
  $argList += @("--sim_in_session","1")
}

# stamp header
@(
  ("ts=" + (Get-Date).ToString("s")),
  ("PROFILE=SHADOW"),
  ("RUNROOT=" + $RunRoot),
  ("PY=" + $py),
  ("ARGS=" + ($argList -join " ")),
  ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID))),
  ("STAMP_OUT=" + $stampOut),
  ("STAMP_ERR=" + $stampErr)
) | Set-Content -Encoding UTF8 -Path $stampOut
"" | Set-Content -Encoding UTF8 -Path $stampErr

# start + detect correctly
try{
  $proc = Start-Process -FilePath $py -ArgumentList $argList -WorkingDirectory $ProjectRoot -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 900

  if($proc.HasExited){
    Add-Content -Encoding UTF8 -Path $stampOut -Value ("EXITED_IMMEDIATELY exitcode=" + $proc.ExitCode + " pid=" + $proc.Id)
    Copy-Item $stampOut $liveOutLatest -Force
    Copy-Item $stampErr $liveErrLatest -Force

    @(
      ("ts=" + (Get-Date).ToString("s")),
      ("ymd=" + $ymd),
      ("core_exit=EXITED_IMMEDIATELY exitcode=" + $proc.ExitCode),
      ("pid=" + $proc.Id)
    ) | Set-Content -Encoding UTF8 -Path $hb
    exit 0
  }

  Set-Content -Encoding UTF8 -Path $pidf -Value $proc.Id
  @(
    ("ts=" + (Get-Date).ToString("s")),
    ("ymd=" + $ymd),
    ("core_exit=LAUNCHED pid=" + $proc.Id)
  ) | Set-Content -Encoding UTF8 -Path $hb

  Add-Content -Encoding UTF8 -Path $stampOut -Value ("LAUNCHED pid=" + $proc.Id)
  Copy-Item $stampOut $liveOutLatest -Force
  Copy-Item $stampErr $liveErrLatest -Force
  exit 0
}catch{
  Add-Content -Encoding UTF8 -Path $stampErr -Value ("WRAPPER_EXC=" + $_.Exception.Message)
  Copy-Item $stampOut $liveOutLatest -Force
  Copy-Item $stampErr $liveErrLatest -Force
  @(
    ("ts=" + (Get-Date).ToString("s")),
    ("ymd=" + $ymd),
    ("core_exit=WRAPPER_EXC")
  ) | Set-Content -Encoding UTF8 -Path $hb
  exit 0
}
