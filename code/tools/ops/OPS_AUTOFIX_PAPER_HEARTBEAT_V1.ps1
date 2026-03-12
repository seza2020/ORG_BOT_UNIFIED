param(
  [string]$Root   = "C:\alpaca-bot\org_bot",
  [string]$RunRoot= "C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

function NowTag(){ (Get-Date -Format "yyyyMMdd_HHmmss") }
function EnsureDir([string]$p){ New-Item -ItemType Directory -Force -Path $p | Out-Null }
function WriteUtf8NoBom([string]$path,[string]$content){
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($path,$content,$utf8NoBom)
}
function BackupFile([string]$src,[string]$bkDir){
  EnsureDir $bkDir
  $dst = Join-Path $bkDir ((Split-Path $src -Leaf) + ".bak")
  Copy-Item -Force $src $dst
  return $dst
}

$tag = NowTag
$patchDir = Join-Path $Root "logs\ops\patches\AUTO_HEARTBEAT_ENVRUNROOT_V1_$tag"
EnsureDir $patchDir

$runner = Join-Path $Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$orch   = Join-Path $Root "tbot\runtime\orchestrator.py"
$opsDir = Join-Path $Root "tools\ops"

if(!(Test-Path -LiteralPath $runner)){ throw "MISSING_RUNNER=$runner" }
if(!(Test-Path -LiteralPath $orch)){ throw "MISSING_ORCH=$orch" }

"PATCH_DIR=$patchDir"
"RUNNER=$runner"
"ORCH=$orch"
"RUNROOT=$RunRoot"

# ------------------------------------------------------------
# (1) Runner: set TBOT_RUNROOT/TBOT_RUNTIME before python starts
# ------------------------------------------------------------
BackupFile $runner $patchDir | Out-Null
$rText = Get-Content -Raw -Encoding UTF8 $runner

if($rText -notmatch "AUTO_PATCH:\s*ENV_RUNROOT_V1"){
  $needle = 'STARTED:\s*PAPER_PROFILE_V1'
  if($rText -notmatch $needle){
    throw "RUNNER_ANCHOR_NOT_FOUND: cannot find STARTED: PAPER_PROFILE_V1"
  }

  $inject = @"
# ---- AUTO_PATCH: ENV_RUNROOT_V1 ----
`$env:TBOT_RUNROOT = `$RunRoot
`$env:TBOT_RUNTIME = `$RunRoot
# -----------------------------------
"@

  $rText2 = [regex]::Replace($rText, $needle, ($inject + "`n" + '$0'), 1)
  WriteUtf8NoBom $runner $rText2
  "OK: RUNNER patched TBOT_RUNROOT/TBOT_RUNTIME"
}else{
  "OK: RUNNER already patched (skip)"
}

# ------------------------------------------------------------
# (2) Orchestrator: deterministic heartbeat using env runroot
# ------------------------------------------------------------
BackupFile $orch $patchDir | Out-Null
$oText = Get-Content -Raw -Encoding UTF8 $orch

$hbAnchor = 'hb_path\s*=\s*state_dir\s*/\s*"heartbeat\.json"'
if($oText -notmatch $hbAnchor){
  throw "ORCH_HEARTBEAT_ANCHOR_NOT_FOUND"
}

if($oText -notmatch "AUTO_PATCH_ENV_RUNROOT_HEARTBEAT_V1"){
  $m = [regex]::Match($oText, "(?m)^(?<ind>\s*)$hbAnchor")
  if(!$m.Success){ throw "INDENT_DETECT_FAIL" }
  $ind = $m.Groups["ind"].Value

  $envBlock = @"
# ---- AUTO_PATCH_ENV_RUNROOT_HEARTBEAT_V1 ----
# Deterministic runroot: only from env (TBOT_RUNROOT/TBOT_RUNTIME)
try:
    from pathlib import Path as _P
    _rr = os.environ.get("TBOT_RUNROOT") or os.environ.get("TBOT_RUNTIME")
    if _rr:
        _rrp = _P(_rr).resolve()
        state_dir = _rrp / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
    else:
        try:
            _sd = _P(".").resolve()
            (_sd / "heartbeat_err.txt").write_text("RUNROOT_MISSING_ENV", encoding="utf-8")
        except Exception:
            pass
except Exception as _e:
    try:
        _rr = os.environ.get("TBOT_RUNROOT") or os.environ.get("TBOT_RUNTIME") or ""
        _sd = _P(_rr).resolve() / "state" if _rr else _P(".").resolve()
        _sd.mkdir(parents=True, exist_ok=True)
        (_sd / "heartbeat_err.txt").write_text("ENV_RUNROOT_PATCH_ERR:" + repr(_e), encoding="utf-8")
    except Exception:
        pass
# --------------------------------------------
"@

  $envBlockIndented = ($envBlock -split "`n" | ForEach-Object { if($_.Length -gt 0){ $ind + $_ } else { "" } }) -join "`n"
  $oText2 = [regex]::Replace($oText, "(?m)^$hbAnchor", ($envBlockIndented + "`n" + $ind + '$0'), 1)
  WriteUtf8NoBom $orch $oText2
  "OK: ORCH patched env-runroot heartbeat"
}else{
  "OK: ORCH already patched (skip)"
}

# ------------------------------------------------------------
# (3) Helper scripts: CLEAN_START + VERIFY + WATCHDOG LOOP
# ------------------------------------------------------------
EnsureDir $opsDir

$clean = Join-Path $opsDir "RUN_PAPER_CLEAN_START_V2.ps1"
@"
param(
  [string]\$Root   = "$Root",
  [string]\$RunRoot= "$RunRoot",
  [int]\$WarmupSec = 8,
  [int]\$Force     = 1
)
\$ErrorActionPreference="Stop"

function AgeSec([string]\$p){
  if(!(Test-Path -LiteralPath \$p)){ return \$null }
  return [int](([DateTime]::UtcNow-(Get-Item -LiteralPath \$p).LastWriteTimeUtc).TotalSeconds)
}

\$runner = Join-Path \$Root "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
if(!(Test-Path -LiteralPath \$runner)){ throw "MISSING_RUNNER=\$runner" }

\$state = Join-Path \$RunRoot "state"
\$lock  = Join-Path \$state "locks\RUN_PAPER_PROFILE.lock"
\$pidf  = Join-Path \$state "pid.txt"
\$hb    = Join-Path \$state "heartbeat.json"
\$touch = Join-Path \$state "hb_touch.txt"
\$err   = Join-Path \$state "heartbeat_err.txt"
\$meta  = Join-Path \$RunRoot "logs\meta.jsonl"

"=== CLEAN_START BEGIN ==="
"ROOT=\$Root"
"RUNROOT=\$RunRoot"
"RUNNER=\$runner"

Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { \$_.CommandLine -like "*-m tbot.main*" -and \$_.CommandLine -like "*org_bot_runtime\\paper*" } |
  ForEach-Object { "KILL PID=" + \$_.ProcessId; Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item -Force -ErrorAction SilentlyContinue \$lock,\$pidf,\$hb,\$touch,\$err | Out-Null
"STATE_CLEARED lock/pid/hb/touch/err"

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File \$runner -Force \$Force
"RUNNER_EXITCODE=\$LASTEXITCODE"

Start-Sleep -Seconds \$WarmupSec

\$bot = \$null
for(\$k=1;\$k -le 20;\$k++){
  \$bot = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { \$_.CommandLine -like "*-m tbot.main*" -and \$_.CommandLine -like "*org_bot_runtime\\paper*" } |
    Select-Object -First 1
  if(\$bot){ break }
  Start-Sleep -Seconds 1
}
if(\$bot){
  \$botPid = [int]\$bot.ProcessId
  New-Item -ItemType Directory -Force -Path \$state | Out-Null
  Set-Content -Encoding ASCII -LiteralPath \$pidf -Value \$botPid
  "PID_WRITTEN=\$botPid => \$pidf"
}else{
  "WARN: BOT_NOT_FOUND via WMI (pid not written)"
}

\$metaAge = AgeSec \$meta
\$hbAge   = AgeSec \$hb
"POST_WARMUP META_AGE_SEC=" + (\$metaAge ?? -1)
"POST_WARMUP HB_AGE_SEC=" + (\$hbAge ?? -1)

if(Test-Path -LiteralPath \$err){
  "`n--- heartbeat_err.txt ---"
  Get-Content -LiteralPath \$err -Tail 50
}
if(Test-Path -LiteralPath \$hb){
  "`n--- heartbeat.json ---"
  Get-Content -LiteralPath \$hb -Tail 5
}

"=== CLEAN_START END ==="
"@ | Set-Content -Encoding UTF8 -LiteralPath $clean

$verify = Join-Path $opsDir "VERIFY_PAPER_HEARTBEAT_V1.ps1"
@"
param([string]\$RunRoot="$RunRoot")
\$ErrorActionPreference="Stop"
function AgeSec([string]\$p){
  if(!(Test-Path -LiteralPath \$p)){ return \$null }
  return [int](([DateTime]::UtcNow-(Get-Item -LiteralPath \$p).LastWriteTimeUtc).TotalSeconds)
}
\$state = Join-Path \$RunRoot "state"
\$hb    = Join-Path \$state "heartbeat.json"
\$touch = Join-Path \$state "hb_touch.txt"
\$err   = Join-Path \$state "heartbeat_err.txt"
\$pidf  = Join-Path \$state "pid.txt"
\$meta  = Join-Path \$RunRoot "logs\meta.jsonl"

"RUNROOT=\$RunRoot"
"HB_EXISTS=" + (Test-Path \$hb)
"TOUCH_EXISTS=" + (Test-Path \$touch)
"ERR_EXISTS=" + (Test-Path \$err)
"PID_EXISTS=" + (Test-Path \$pidf)
"META_EXISTS=" + (Test-Path \$meta)

"HB_AGE="    + (AgeSec \$hb ?? -1)
"TOUCH_AGE=" + (AgeSec \$touch ?? -1)
"ERR_AGE="   + (AgeSec \$err ?? -1)
"META_AGE="  + (AgeSec \$meta ?? -1)

if(Test-Path \$pidf){ "PID=" + (Get-Content -Raw -LiteralPath \$pidf).Trim() }
if(Test-Path \$err){ "`n--- heartbeat_err.txt ---"; Get-Content -LiteralPath \$err -Tail 50 }
if(Test-Path \$hb){ "`n--- heartbeat.json ---"; Get-Content -LiteralPath \$hb -Tail 5 }
"@ | Set-Content -Encoding UTF8 -LiteralPath $verify

$wd = Join-Path $opsDir "WATCHDOG_META_LOOP_1MIN_V2.ps1"
@"
param(
  [string]\$Root="$Root",
  [string]\$RunRoot="$RunRoot",
  [int]\$EverySec=60
)
\$ErrorActionPreference="Stop"
"=== WATCHDOG_LOOP START ==="
"Root=\$Root"
"RunRoot=\$RunRoot"
"EverySec=\$EverySec"

while(\$true){
  try{
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path \$Root "tools\ops\WATCHDOG_META_STALL_AUTOFIX_V1.ps1") -Root \$Root -RunRoot \$RunRoot
  }catch{
    \$_ | Out-Host
  }
  Start-Sleep -Seconds \$EverySec
}
"@ | Set-Content -Encoding UTF8 -LiteralPath $wd

# ------------------------------------------------------------
# (4) python compile
# ------------------------------------------------------------
$py = Join-Path $Root ".venv\Scripts\python.exe"
if(Test-Path -LiteralPath $py){
  & $py -c "import py_compile; py_compile.compile(r'$orch', doraise=True); print('PY_COMPILE_OK')"
}else{
  "WARN: PY not found at $py (skip compile)"
}

"=== AUTOFIX DONE ==="
"NEXT_RUN_1: pwsh -NoProfile -ExecutionPolicy Bypass -File `"$clean`""
"NEXT_RUN_2: pwsh -NoProfile -ExecutionPolicy Bypass -File `"$verify`""
"NEXT_RUN_3: pwsh -NoProfile -ExecutionPolicy Bypass -File `"$wd`""
