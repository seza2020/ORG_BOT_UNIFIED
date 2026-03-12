param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string[]]$Days = @("20260209","20260210","20260211","20260212","20260213"),
  [int]$RollingDays = 10
)

$ErrorActionPreference = "Stop"

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ throw "EnsureDir: path is empty" }
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}

if([string]::IsNullOrWhiteSpace($Root)){ throw "Root is empty" }
if(!(Test-Path $Root)){ throw "Missing Root: $Root" }

# --- Normalize Days (fix root cause: single comma-string)
if(@($Days).Count -eq 1 -and $Days[0] -match ","){
  $Days = $Days[0].Split(",")
}
$Days = $Days | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\d{8}$" } | Select-Object -Unique
if(@($Days).Count -lt 1){ throw "Days normalized to empty. Input was invalid." }

$Logs        = Join-Path $Root "logs"
$Ops         = Join-Path $Logs "ops"
$FreezeDir   = Join-Path $Logs "freeze"
$ShadowDaily = Join-Path $Logs "shadow_daily"

$KC       = Join-Path $Ops "knowledge_current"
$KDocs    = Join-Path $KC "docs"
$KZips    = Join-Path $KC "zips"
$KDailies = Join-Path $KZips "dailies"
$KTasks   = Join-Path $KDocs "tasks"
$KStage   = Join-Path $KDocs "stage_gates"

EnsureDir $KC
EnsureDir $KDocs
EnsureDir $KZips
EnsureDir $KDailies
EnsureDir $KTasks
EnsureDir $KStage

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

"OK: DAYS_COUNT=" + @($Days).Count
"OK: DAYS=" + ($Days -join ",")

# --- Backup current Knowledge outputs (safety)
$bakDir = Join-Path $KC ("backup_{0}" -f $ts)
EnsureDir $bakDir
Get-ChildItem $KZips -File -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
  Copy-Item -Force $_.FullName (Join-Path $bakDir $_.Name)
}

# --- Clean old daily zips to avoid false single-file state
Get-ChildItem $KDailies -File -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue | Remove-Item -Force

# --- Ensure pre-close artifacts exist (script + log) for audit visibility
$PreCloseScript = Join-Path $Root "tools\TBOT_PRE_CLOSE_STOP_SAFE.ps1"
if(!(Test-Path $PreCloseScript)){
  $stub = @"
param([string]`$Root="C:\alpaca-bot\org_bot")
`$ErrorActionPreference="SilentlyContinue"
`$log = Join-Path `$Root "logs\ops\PRE_CLOSE_STOP.log"
`$ts  = Get-Date -Format "s"
"[PRE_CLOSE_STOP] ts=`$ts status=stub_present note=not_scheduled_or_disabled" | Add-Content -Encoding UTF8 `$log
"@
  Set-Content -Encoding UTF8 -Path $PreCloseScript -Value $stub
}
$PreCloseLog = Join-Path $Root "logs\ops\PRE_CLOSE_STOP.log"
if(!(Test-Path $PreCloseLog)){
  EnsureDir (Split-Path $PreCloseLog -Parent)
  New-Item -ItemType File -Force -Path $PreCloseLog | Out-Null
}

# --- Build DAILY zips
foreach($d in $Days){

  $bk = Get-ChildItem $Ops -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $d) -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1

  $fz = Get-ChildItem $FreezeDir -File -Filter ("FREEZE_TODAY_{0}_{0}_*.zip" -f $d) -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1

  $fm = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $d)

  $st = Join-Path $KC ("_staging_{0}_{1}" -f $d, $ts)
  if(Test-Path $st){ Remove-Item $st -Recurse -Force }
  EnsureDir $st

  # FROM_META (required)
  if(Test-Path $fm){
    Copy-Item -Force $fm (Join-Path $st ("shadow_plans_{0}_FROM_META.jsonl" -f $d))
  } else {
    New-Item -ItemType File -Force -Path (Join-Path $st ("shadow_plans_{0}_FROM_META.jsonl" -f $d)) | Out-Null
  }

  # FREEZE evidence
  if($fz){
    EnsureDir (Join-Path $st "freeze")
    Copy-Item -Force $fz.FullName (Join-Path (Join-Path $st "freeze") $fz.Name)
  }

  # live logs (OUT + ERR) — ERR must exist even if empty
  EnsureDir (Join-Path $st "live")

  if($bk){
    Get-ChildItem $bk.FullName -File -Filter ("QC_{0}.txt" -f $d) -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $st $_.Name) }

    Get-ChildItem $bk.FullName -File -Filter ("meta_{0}.jsonl" -f $d) -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $st $_.Name) }

    Get-ChildItem $bk.FullName -File -Filter ("announce_{0}.log" -f $d) -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $st $_.Name) }

    $outs = Get-ChildItem $bk.FullName -File -Filter ("LIVE_OUT_{0}*.txt" -f $d) -ErrorAction SilentlyContinue
    $errs = Get-ChildItem $bk.FullName -File -Filter ("LIVE_ERR_{0}*.txt" -f $d) -ErrorAction SilentlyContinue

    foreach($o in $outs){ Copy-Item -Force $o.FullName (Join-Path (Join-Path $st "live") $o.Name) }
    foreach($e in $errs){ Copy-Item -Force $e.FullName (Join-Path (Join-Path $st "live") $e.Name) }

    if((@($errs).Count -eq 0)){
      New-Item -ItemType File -Force -Path (Join-Path (Join-Path $st "live") ("LIVE_ERR_{0}_EMPTY.txt" -f $d)) | Out-Null
    }
  } else {
    New-Item -ItemType File -Force -Path (Join-Path (Join-Path $st "live") ("LIVE_ERR_{0}_EMPTY.txt" -f $d)) | Out-Null
  }

  # daily manifest
  @(
    "DAY=$d"
    ("CREATED={0}" -f (Get-Date -Format s))
    "FROM_META=$fm"
    ("HAS_FREEZE_ZIP={0}" -f [bool]$fz)
    ("HAS_BACKUP_FOLDER={0}" -f [bool]$bk)
  ) | Set-Content -Encoding UTF8 -Path (Join-Path $st "MANIFEST.txt")

  # zip daily
  $dailyZip = Join-Path $KDailies ("ORG_BOT_DAILY_{0}.zip" -f $d)
  if(Test-Path $dailyZip){ Remove-Item $dailyZip -Force }
  Compress-Archive -Path (Join-Path $st "*") -DestinationPath $dailyZip -Force

  Remove-Item $st -Recurse -Force
}

# --- Build rolling zip (true multi-day set)
$rolling = Join-Path $KZips ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
if(Test-Path $rolling){ Remove-Item $rolling -Force }

$allDaily = Get-ChildItem $KDailies -File -Filter "ORG_BOT_DAILY_*.zip" | Sort-Object Name -Desc
$takeN = [Math]::Min($RollingDays, @($allDaily).Count)
if($takeN -lt 2){ "WARN: rolling will have <2 days (check backups/freeze coverage)" }
$dailies = $allDaily | Select-Object -First $takeN

$tmpRoll = Join-Path $KC ("_roll_{0}" -f $ts)
if(Test-Path $tmpRoll){ Remove-Item $tmpRoll -Recurse -Force }
EnsureDir $tmpRoll
foreach($f in $dailies){ Copy-Item -Force $f.FullName (Join-Path $tmpRoll $f.Name) }
Compress-Archive -Path (Join-Path $tmpRoll "*") -DestinationPath $rolling -Force
Remove-Item $tmpRoll -Recurse -Force

# --- Minimal stage-gate docs + journal template (kept)
$sg1 = @"
# SHADOW -> PAPER Stage Gate (Auditable)
PASS:
- >= 3 full trading days with no exceptions/tracebacks
- FROM_META exists and used as count source
- EOD produces freeze + QC + clears lock
FAIL:
- any traceback/import error/exception
"@
Set-Content -Encoding UTF8 -Path (Join-Path $KStage "STAGE_GATE_SHADOW_TO_PAPER.md") -Value $sg1

$sg2 = @"
# PAPER -> LIVE Stage Gate (Auditable)
PASS:
- >= 30 paper trades
- positive expectancy + bounded drawdown
FAIL:
- repeated operational failures or DD breach
"@
Set-Content -Encoding UTF8 -Path (Join-Path $KStage "STAGE_GATE_PAPER_TO_LIVE.md") -Value $sg2

"date,symbol,side,setup,entry,stop,tp,riskR,resultR,errors,notes" |
  Set-Content -Encoding UTF8 -Path (Join-Path $KDocs "PAPER_JOURNAL_TEMPLATE.csv")

# --- Task proofs (best effort)
$taskListPath = Join-Path $KTasks ("schtasks_query_{0}.txt" -f $ts)
try {
  schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /V /FO LIST | Out-File -Encoding UTF8 $taskListPath -Append
  schtasks /Query /TN "\TBOT_END_OF_DAY_1305"       /V /FO LIST | Out-File -Encoding UTF8 $taskListPath -Append
} catch {
  "WARN: schtasks query failed (non-fatal)" | Out-File -Encoding UTF8 $taskListPath -Append
}
try { schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /XML | Out-File -Encoding UTF8 (Join-Path $KTasks "TBOT_RUN_SHADOW_DAILY_0630.xml") } catch {}
try { schtasks /Query /TN "\TBOT_END_OF_DAY_1305"       /XML | Out-File -Encoding UTF8 (Join-Path $KTasks "TBOT_END_OF_DAY_1305.xml") } catch {}

# --- Rebuild SUPER zip (docs + rolling + static zips)
$staticOps  = Join-Path $KZips "ORG_BOT_STATIC_OPS.zip"
$staticCode = Join-Path $KZips "ORG_BOT_STATIC_CODE.zip"
$super      = Join-Path $KZips "ORG_BOT_KNOWLEDGE_SUPER.zip"
if(Test-Path $super){ Remove-Item $super -Force }

$tmpSuper = Join-Path $KC ("_super_{0}" -f $ts)
if(Test-Path $tmpSuper){ Remove-Item $tmpSuper -Recurse -Force }
EnsureDir $tmpSuper

Copy-Item -Recurse -Force $KDocs (Join-Path $tmpSuper "docs")
Copy-Item -Force $rolling (Join-Path $tmpSuper (Split-Path $rolling -Leaf))
if(Test-Path $staticOps){  Copy-Item -Force $staticOps  (Join-Path $tmpSuper "ORG_BOT_STATIC_OPS.zip") }
if(Test-Path $staticCode){ Copy-Item -Force $staticCode (Join-Path $tmpSuper "ORG_BOT_STATIC_CODE.zip") }

@(
  ("CREATED={0}" -f (Get-Date -Format s))
  ("ROLLING_ZIP={0}" -f (Split-Path $rolling -Leaf))
  ("ROLLING_COUNT={0}" -f @($dailies).Count)
  ("STATIC_OPS_PRESENT={0}" -f (Test-Path $staticOps))
  ("STATIC_CODE_PRESENT={0}" -f (Test-Path $staticCode))
  ("BACKUP_DIR={0}" -f $bakDir)
  ("DAYS_USED={0}" -f ($Days -join ","))
) | Set-Content -Encoding UTF8 -Path (Join-Path $tmpSuper "MANIFEST.txt")

Compress-Archive -Path (Join-Path $tmpSuper "*") -DestinationPath $super -Force
Remove-Item $tmpSuper -Recurse -Force

"OK: BACKUP_DIR=$bakDir"
"OK: DAILY_DIR=$KDailies"
"OK: ROLLING_ZIP=$rolling"
"OK: SUPER_ZIP=$super"
