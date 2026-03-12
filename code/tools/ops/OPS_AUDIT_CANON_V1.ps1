$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
$OUTDIR=Join-Path $ROOT "logs\ops\audit"
New-Item -ItemType Directory -Force $OUTDIR | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$NOTE = Join-Path $OUTDIR ("OPS_AUDIT_NOTE_" + $ts + ".txt")

@"
OPS_AUDIT_CANON_V1
Timestamp: $(Get-Date)
ROOT=$ROOT
Host=$env:COMPUTERNAME
User=$env:USERNAME
"@ | Set-Content -Encoding UTF8 $NOTE

function Add-Note([string]$s){ Add-Content -Encoding UTF8 $NOTE $s }
function Add-Header([string]$h){
  Add-Note ""
  Add-Note ("="*90)
  Add-Note $h
  Add-Note ("="*90)
}
function Run([string]$title, [scriptblock]$sb){
  Add-Note ""
  Add-Note ("--- " + $title + " ---")
  try {
    $out = & $sb 2>&1 | Out-String
    if([string]::IsNullOrWhiteSpace($out)){ $out="(no output)" }
    Add-Note $out.TrimEnd()
    Add-Note ("RESULT: OK")
  } catch {
    Add-Note ("RESULT: FAIL :: " + $_.Exception.Message)
    Add-Note (($_ | Out-String).TrimEnd())
  }
}

Add-Header "0) BASIC ENV / VERSIONS"
Run "PowerShell version" { $PSVersionTable | Format-List | Out-String }
Run "OS info" { Get-CimInstance Win32_OperatingSystem | Select Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime | Format-List | Out-String }

$PY = Join-Path $ROOT ".venv\Scripts\python.exe"
Run "Python path exists" { Test-Path $PY }
Run "Python version" { & $PY -V }

Add-Header "1) GIT / WORKTREE SANITY"
Run "Git status (if repo)" { if(Test-Path (Join-Path $ROOT ".git")){ git -C $ROOT status --porcelain=v1 } else { "NO_GIT_DIR" } }
Run "Git branch / commit (if repo)" { if(Test-Path (Join-Path $ROOT ".git")){ git -C $ROOT rev-parse --abbrev-ref HEAD; git -C $ROOT rev-parse HEAD } else { "NO_GIT_DIR" } }

Add-Header "2) PROFILES / ENV (NO SECRETS PRINT)"
$paperProf = Join-Path $ROOT "tools\profiles\paper.profile.json"
$shadowProf = Join-Path $ROOT "tools\profiles\shadow.profile.json"
Run "paper.profile.json exists" { Test-Path $paperProf }
Run "shadow.profile.json exists" { Test-Path $shadowProf }

Run "paper.profile.json key audit (non-secret keys only)" {
  $p = Get-Content -Raw $paperProf | ConvertFrom-Json
  $keys = @($p.env.PSObject.Properties | % Name) | Sort-Object
  "ENV_KEYS=" + ($keys -join ",")
  "TBOT_PROFILE=" + $p.env.TBOT_PROFILE
  "TBOT_ENV=" + $p.env.TBOT_ENV
  "TBOT_FILELOG_PATH=" + $p.env.TBOT_FILELOG_PATH
  "TBOT_EOD_FREEZE_REQUIRED=" + $p.env.TBOT_EOD_FREEZE_REQUIRED
  "TBOT_QC_MUST_PASS_BEFORE_START=" + $p.env.TBOT_QC_MUST_PASS_BEFORE_START
  "TBOT_KILL_ON_CONFIG_INVALID=" + $p.env.TBOT_KILL_ON_CONFIG_INVALID
  "TBOT_ENFORCE_SINGLE_INSTANCE=" + $p.env.TBOT_ENFORCE_SINGLE_INSTANCE
  "TBOT_KILL_ON_PRICE_SYNTHETIC=" + $p.env.TBOT_KILL_ON_PRICE_SYNTHETIC
  "TBOT_GATE_MAX_PLANS_PER_DAY=" + $p.env.TBOT_GATE_MAX_PLANS_PER_DAY
  "TBOT_GATE_COOLDOWN_SEC=" + $p.env.TBOT_GATE_COOLDOWN_SEC
  "TBOT_GATE_MAX_RISK_USD=" + $p.env.TBOT_GATE_MAX_RISK_USD
  "TBOT_GATE_MAX_RISK_PER_DAY_USD=" + $p.env.TBOT_GATE_MAX_RISK_PER_DAY_USD
}

Run "Search for TBOT_ENV mis-assignments in tools (risky overrides)" {
  rg -n --hidden -S "TBOT_ENV\s*=\s*`"?PAPER`"?|TBOT_ENV\s*=\s*`"?SHADOW`"?" $ROOT
}

Add-Header "3) LAUNCHERS / RUNNERS PARSE + MARKERS"
$targets=@(
  (Join-Path $ROOT "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"),
  (Join-Path $ROOT "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"),
  (Join-Path $ROOT "tools\shadow_run.ps1")
)

Run "Launcher files exist" { $targets | % { $_ + " :: " + (Test-Path $_) } }

Run "PowerShell AST parse (launchers)" {
  foreach($t in $targets){
    $null=[System.Management.Automation.Language.Parser]::ParseFile($t,[ref]$null,[ref]$null)
    "PS_PARSE_OK: $t"
  }
}

Run "Session guard markers" {
  foreach($t in $targets){
    $c=(Select-String -Path $t -Pattern "SESSION_GUARD_RTH_V1" -AllMatches).Matches.Count
    "$t :: SESSION_GUARD_MARKERS=$c"
  }
}

Add-Header "4) PYTHON ENTRYPOINT / API COMPAT (run_loop signature)"
Run "py_compile tbot/main.py" { & $PY -m py_compile (Join-Path $ROOT "tbot\main.py"); "EXIT=" + $LASTEXITCODE }

Run "Inspect run_loop signature vs main kwargs" {
  $code=@"
import inspect
from tbot.runtime.orchestrator import run_loop
sig=str(inspect.signature(run_loop))
print("RUN_LOOP_SIGNATURE=", sig)
print("PARAMS=", list(inspect.signature(run_loop).parameters.keys()))
"@
  & $PY -u -c $code
}

Run "Search for kwargs passed into run_loop (tbot/main.py)" {
  rg -n "rc\s*=\s*run_loop\(" (Join-Path $ROOT "tbot\main.py")
  rg -n "gate_max_risk_per_trade_usd|gate_max_risk_per_day_usd|gate_max_risk_usd" (Join-Path $ROOT "tbot\main.py")
}

Add-Header "5) CORE SAFETY POLICIES (hard stops, single instance, price safety, config invalid)"
Run "Search kill-switch / hard-stop markers" {
  rg -n --hidden -S "KILL_ON_|HARD_STOP|SystemExit|PERSIST_CAP|BOOT_GUARD|PRICE_SYNTHETIC|QC_MUST_PASS" (Join-Path $ROOT "tbot") |
    Select-Object -First 200
}

Add-Header "6) EOD / FREEZE / EVIDENCE (Paper)"
$paperRR="C:\alpaca-bot\org_bot_runtime\paper"
Run "Paper RunRoot exists" { Test-Path $paperRR }
Run "Paper logs tree (top)" { Get-ChildItem (Join-Path $paperRR "logs") -ErrorAction SilentlyContinue | Select Name,LastWriteTime,Length | Format-Table -AutoSize | Out-String }

Run "bot_console logs present" {
  $p = Join-Path $paperRR "logs"
  Get-ChildItem $p -Filter "bot_console_*.log" -ErrorAction SilentlyContinue |
    Sort LastWriteTime -Descending |
    Select -First 10 Name,LastWriteTime,Length | Format-Table -AutoSize | Out-String
}

Run "freeze backups present" {
  Get-ChildItem (Join-Path $ROOT "logs\ops") -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue |
    Sort LastWriteTime -Descending |
    Select -First 10 Name,LastWriteTime | Format-Table -AutoSize | Out-String
}

Add-Header "DONE"
Add-Note ("NOTE_PATH=" + $NOTE)
Write-Host ("WROTE_NOTE=" + $NOTE)
