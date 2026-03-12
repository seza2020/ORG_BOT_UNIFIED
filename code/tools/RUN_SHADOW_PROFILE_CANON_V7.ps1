param(
  [Parameter(Mandatory=$true)][string]$ProjectRoot,
  [Parameter(Mandatory=$false)][string]$RunRoot,
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

# -------- profile load --------
if(!(Test-Path $ProfilePath)){ throw ("MISSING_PROFILEPATH=" + $ProfilePath) }
$prof = Get-Content -Raw -Encoding UTF8 $ProfilePath | ConvertFrom-Json

# Resolve RunRoot from profile if not provided
if([string]::IsNullOrWhiteSpace($RunRoot)){
  if($prof.runroot){ $RunRoot=[string]$prof.runroot }
  elseif($prof.runtime){ $RunRoot=[string]$prof.runtime }
}
if([string]::IsNullOrWhiteSpace($RunRoot)){ throw "RUNROOT_EMPTY" }
if(([string]$RunRoot).ToLower() -notlike "*\shadow*"){ throw ("RUNROOT_NOT_SHADOW=" + $RunRoot) }

# -------- dirs/logs --------
$ops = Join-Path $RunRoot "logs\ops"
$logs= Join-Path $RunRoot "logs"
$ledgerDir = Join-Path $logs "ledger"
EnsureDir $ops; EnsureDir $logs; EnsureDir $ledgerDir

$ymd = (Get-Date).ToString("yyyyMMdd")
$ts  = (Get-Date).ToString("yyyyMMdd_HHmmss")

$stampOut = Join-Path $ops ("LIVE_OUT_{0}_{1}.txt" -f $ymd,$ts)
$stampErr = Join-Path $ops ("LIVE_ERR_{0}_{1}.txt" -f $ymd,$ts)
$liveOutLatest = Join-Path $ops ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
$liveErrLatest = Join-Path $ops ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)
$hb  = Join-Path $ops "HEARTBEAT_SHADOW_RUNNER.txt"
$pidf= Join-Path $RunRoot "PID"

"" | Set-Content -Encoding UTF8 -Path $stampOut
"" | Set-Content -Encoding UTF8 -Path $stampErr

# -------- stale PID / already running guard --------
try{
  if(Test-Path $pidf){
    $oldPid = 0
    try{ $oldPid = [int](Get-Content $pidf -ErrorAction SilentlyContinue | Select -First 1) } catch {}
    if($oldPid -gt 0){
      $p = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
      if($p -and $Force -ne 1){
        @(
          ("ts=" + (Get-Date).ToString("s")),
          "PROFILE=SHADOW",
          ("RUNROOT=" + $RunRoot),
          ("CORE_EXIT=ALREADY_RUNNING pid=" + $oldPid),
          ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID)))
        ) | Set-Content -Encoding UTF8 -Path $liveOutLatest
        "" | Set-Content -Encoding UTF8 -Path $liveErrLatest
        @(
          ("ts=" + (Get-Date).ToString("s")),
          ("ymd=" + $ymd),
          ("core_exit=ALREADY_RUNNING pid=" + $oldPid)
        ) | Set-Content -Encoding UTF8 -Path $hb
        exit 0
      }
      if(-not $p){ Remove-Item $pidf -Force -ErrorAction SilentlyContinue }
    }
  }
}catch{}

# -------- load secrets (SHADOW) --------
$ldr = Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1"
if(!(Test-Path $ldr)){ throw ("MISSING_LOADER=" + $ldr) }
. $ldr -Profile "SHADOW" -ProjectRoot $ProjectRoot -RunRoot $RunRoot | Out-Null

# enforce TBOT_PROFILE
$act = ([string]$env:TBOT_PROFILE).Trim().ToUpper()
if($act -ne "SHADOW"){ throw ("TBOT_PROFILE_MISMATCH expected=SHADOW actual=" + $act) }

# -------- IMPORTANT: ensure TBOT_SHADOW_PRICE_MODE is set LAST --------
# (اگر داخل پروفایل هم باشد، باز اینجا آخرین set می‌شود)
$mode = $null
try{ if($prof.TBOT_SHADOW_PRICE_MODE){ $mode=[string]$prof.TBOT_SHADOW_PRICE_MODE } }catch{}
if([string]::IsNullOrWhiteSpace($mode)){ $mode = [string]$env:TBOT_SHADOW_PRICE_MODE }
if(-not [string]::IsNullOrWhiteSpace($mode)){
  try{ Remove-Item Env:TBOT_SHADOW_PRICE_MODE -ErrorAction SilentlyContinue } catch {}
  $env:TBOT_SHADOW_PRICE_MODE = $mode  # LAST SET
}

# -------- build python command --------
$py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
if(!(Test-Path $py)){ $py = (Get-Command python.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($py)){ throw "PYTHON_NOT_FOUND" }

$meta    = Join-Path $logs "meta.jsonl"
$announce= Join-Path $logs "announce_shadow.log"

# gate defaults + profile gate overrides
$minRR=1.0; $minConf=0.0; $cool=45; $maxPlans=150; $maxRisk=500
try{
  if($prof.gate){
    if($prof.gate.min_rr){ $minRR=[double]$prof.gate.min_rr }
    if($prof.gate.min_confidence){ $minConf=[double]$prof.gate.min_confidence }
    if($prof.gate.cooldown_sec){ $cool=[int]$prof.gate.cooldown_sec }
    if($prof.gate.max_plans_per_day){ $maxPlans=[int]$prof.gate.max_plans_per_day }
    if($prof.gate.max_risk_usd){ $maxRisk=[double]$prof.gate.max_risk_usd }
  }
}catch{}

$argsList = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999","--sleep","0.25",
  "--meta",$meta,
  "--announce",$announce,
  "--ledger_dir",$ledgerDir,
  "--shadow",
  "--shadow_path",$RunRoot,
  "--gate_min_rr",[string]$minRR,
  "--gate_min_conf",[string]$minConf,
  "--gate_cooldown_sec",[string]$cool,
  "--gate_max_plans_per_day",[string]$maxPlans,
  "--gate_max_risk_usd",[string]$maxRisk
)

# -------- launch (non-blocking) --------
try{
  # stamp header
  @(
    ("ts=" + (Get-Date).ToString("s")),
    "PROFILE=SHADOW",
    ("RUNROOT=" + $RunRoot),
    ("PY=" + $py),
    ("ARGS=" + ($argsList -join " ")),
    ("KEY_ID_FINGERPRINT=" + (Finger ([string]$env:APCA_API_KEY_ID))),
    ("STAMP_OUT=" + $stampOut),
    ("STAMP_ERR=" + $stampErr)
  ) | Add-Content -Encoding UTF8 -Path $stampOut

  $proc = Start-Process -FilePath $py -ArgumentList $argsList -WorkingDirectory $ProjectRoot `
    -NoNewWindow -PassThru -RedirectStandardOutput $stampOut -RedirectStandardError $stampErr

  Start-Sleep -Seconds 2

  $p2 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
  if(-not $p2){
    # failed immediately -> dump err to latest, and log FAIL_START
    Add-Content -Encoding UTF8 -Path $stampOut -Value ("FAIL_START: python exited immediately pid=" + $proc.Id)
    Copy-Item $stampOut $liveOutLatest -Force
    Copy-Item $stampErr $liveErrLatest -Force

    # auto-heal once: if error mentions TBOT_SHADOW_PRICE_MODE, set it LAST again and retry once
    $errTxt = ""
    try{ $errTxt = Get-Content $stampErr -Raw -ErrorAction SilentlyContinue } catch {}
    if($errTxt -match 'TBOT_SHADOW_PRICE_MODE' -and $errTxt -match 'HARD_STOP'){
      try{
        if(-not [string]::IsNullOrWhiteSpace($mode)){
          Remove-Item Env:TBOT_SHADOW_PRICE_MODE -ErrorAction SilentlyContinue
          $env:TBOT_SHADOW_PRICE_MODE = $mode
        }
      }catch{}
      Add-Content -Encoding UTF8 -Path $stampOut -Value "AUTOHEAL_RETRY=1 reason=SHADOW_PRICE_MODE_HARDSTOP"
      $proc = Start-Process -FilePath $py -ArgumentList $argsList -WorkingDirectory $ProjectRoot `
        -NoNewWindow -PassThru -RedirectStandardOutput $stampOut -RedirectStandardError $stampErr
      Start-Sleep -Seconds 2
      $p2 = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
      if(-not $p2){
        Add-Content -Encoding UTF8 -Path $stampOut -Value ("FAIL_START_AFTER_RETRY pid=" + $proc.Id)
        Copy-Item $stampOut $liveOutLatest -Force
        Copy-Item $stampErr $liveErrLatest -Force
        @(
          ("ts=" + (Get-Date).ToString("s")),
          ("ymd=" + $ymd),
          ("core_exit=FAIL_START")
        ) | Set-Content -Encoding UTF8 -Path $hb
        exit 1
      }
    } else {
      @(
        ("ts=" + (Get-Date).ToString("s")),
        ("ymd=" + $ymd),
        ("core_exit=FAIL_START")
      ) | Set-Content -Encoding UTF8 -Path $hb
      exit 1
    }
  }

  # success
  Set-Content -Encoding UTF8 -Path $pidf -Value $proc.Id
  Copy-Item $stampOut $liveOutLatest -Force
  Copy-Item $stampErr $liveErrLatest -Force

  @(
    ("ts=" + (Get-Date).ToString("s")),
    ("ymd=" + $ymd),
    ("core_exit=LAUNCHED pid=" + $proc.Id)
  ) | Set-Content -Encoding UTF8 -Path $hb

  exit 0
}catch{
  try{
    ("WRAPPER_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $stampErr
    Copy-Item $stampOut $liveOutLatest -Force
    Copy-Item $stampErr $liveErrLatest -Force
  }catch{}
  exit 1
}
