param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$true)][string]$RunRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath,
  [int]$Force = 0
)
$ErrorActionPreference="Stop"

function EnsureDir([string]$p){ if($p){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Finger([string]$s){
  if([string]::IsNullOrWhiteSpace($s)){ return "" }
  $n=$s.Length
  $a=$s.Substring(0,[Math]::Min(4,$n))
  $b=$s.Substring([Math]::Max(0,$n-4))
  return ($a + "****" + $b)
}

# RUN_SHADOW_PROFILE_CANON_V4 (direct python launcher; never hangs; always exits 0)

if(!(Test-Path $ProfilePath)){ throw ("MISSING_PROFILEPATH=" + $ProfilePath) }
$prof = Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json

if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_EMPTY" }
if(([string]$RunRoot).ToLower() -notlike "*\shadow*"){ throw ("RUNROOT_NOT_SHADOW=" + $RunRoot) }

$ops = Join-Path $RunRoot "logs\ops"
EnsureDir $ops

$ymd = (Get-Date).ToString("yyyyMMdd")
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")

$loLatest = Join-Path $ops ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
$leLatest = Join-Path $ops ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)
$loStamp  = Join-Path $ops ("LIVE_OUT_{0}_{1}.txt" -f $ymd,$ts)
$leStamp  = Join-Path $ops ("LIVE_ERR_{0}_{1}.txt" -f $ymd,$ts)

$hb   = Join-Path $ops "HEARTBEAT_SHADOW_RUNNER.txt"
$pidf = Join-Path $RunRoot "PID"

# load secrets for SHADOW (sets APCA_* and TBOT_PROFILE, but prints masked only)
$ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
. $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# enforce TBOT_PROFILE
$act = ([string]$env:TBOT_PROFILE).Trim().ToUpper()
if($act -ne "SHADOW"){ throw ("TBOT_PROFILE_MISMATCH expected=SHADOW actual=" + $act) }

# single instance check by PID file
if(Test-Path $pidf){
  $oldPid = 0
  try{ $oldPid = [int]((Get-Content $pidf -ErrorAction SilentlyContinue | Select -First 1).Trim()) } catch {}
  if($oldPid -gt 0){
    $p = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
    if($p -and $Force -ne 1){
      @(
        ("ts=" + (Get-Date).ToString("s")),
        "PROFILE=SHADOW",
        ("RUNROOT=" + $RunRoot),
        ("BLOCK=already_running pid=" + $oldPid),
        ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID)))
      ) | Set-Content -Encoding UTF8 -Path $loLatest
      "" | Set-Content -Encoding UTF8 -Path $leLatest
      exit 0
    }
    if($p -and $Force -eq 1){
      try{ Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue } catch {}
    }
  }
}

# determine python
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path $py)){ $py="python" }

# pick args from profile if present (fallback to safe observed defaults)
$iters = 999999
$sleep = 0.25
$min_rr = 1.0
$min_conf = 0.0
$cooldown = 45
$max_plans = 150
$max_risk = 500

try{
  if($prof.args){
    if($prof.args.iters){ $iters=[int]$prof.args.iters }
    if($prof.args.sleep){ $sleep=[double]$prof.args.sleep }
    if($prof.args.gate_min_rr){ $min_rr=[double]$prof.args.gate_min_rr }
    if($prof.args.gate_min_conf){ $min_conf=[double]$prof.args.gate_min_conf }
    if($prof.args.gate_cooldown_sec){ $cooldown=[int]$prof.args.gate_cooldown_sec }
    if($prof.args.gate_max_plans_per_day){ $max_plans=[int]$prof.args.gate_max_plans_per_day }
    if($prof.args.gate_max_risk_usd){ $max_risk=[double]$prof.args.gate_max_risk_usd }
  }
} catch {}

# IMPORTANT: root/state must be RunRoot -> last positional arg is RunRoot (replaces old "-.")
$pyArgs = @(
  "-u","-m","tbot.main",
  "--run",
  "--iters",$iters,
  "--sleep",$sleep,
  "--shadow",
  "--gate_min_rr",$min_rr,
  "--gate_min_conf",$min_conf,
  "--gate_cooldown_sec",$cooldown,
  "--gate_max_plans_per_day",$max_plans,
  "--gate_max_risk_usd",$max_risk,
  "$RunRoot"
) -join " "

# preface log
@(
  ("ts=" + (Get-Date).ToString("s")),
  "PROFILE=SHADOW",
  ("RUNROOT=" + $RunRoot),
  ("PY=" + $py),
  ("ARGS=" + $pyArgs),
  ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID)))
) | Set-Content -Encoding UTF8 -Path $loLatest
"" | Set-Content -Encoding UTF8 -Path $leLatest

# launch DETACHED python (never hangs)
$proc = Start-Process -FilePath $py -ArgumentList $pyArgs -WorkingDirectory $ProjectRoot `
  -RedirectStandardOutput $loStamp -RedirectStandardError $leStamp -PassThru

# update latest pointers by copying (so Latest always exists)
Copy-Item $loStamp $loLatest -Force
Copy-Item $leStamp $leLatest -Force

# write PID + heartbeat
Set-Content -Encoding UTF8 -Path $pidf -Value $proc.Id
@(
  ("ts=" + (Get-Date).ToString("s")),
  ("ymd=" + $ymd),
  ("core_exit=LAUNCHED pid=" + $proc.Id)
) | Set-Content -Encoding UTF8 -Path $hb

exit 0
