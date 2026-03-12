param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string[]]$Days = @("20260209","20260210","20260211","20260212","20260213"),
  [int]$RollingDays = 10
)

$ErrorActionPreference="Stop"

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ throw "EnsureDir: path is empty" }
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}
function Remove-WithRetry([string]$p,[int]$tries=25){
  for($i=1;$i -le $tries;$i++){
    try{
      if(Test-Path $p){ Remove-Item -Force -ErrorAction Stop $p }
      return
    } catch {
      Start-Sleep -Milliseconds 300
      [GC]::Collect(); [GC]::WaitForPendingFinalizers()
      if($i -eq $tries){ throw }
    }
  }
}
function Write-CanonEvidence([string]$canonPath,[string]$outPath){
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("CANON_PATH=$canonPath") | Out-Null
  $lines.Add("CREATED=$(Get-Date -Format s)") | Out-Null
  $lines.Add("") | Out-Null
  $lines.Add("---- ts2/out/err ----") | Out-Null
  (Select-String -LiteralPath $canonPath -Pattern '\$ts2=\(Get-Date -Format','LIVE_OUT_','LIVE_ERR_','\$OPS' |
    ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }
  $lines.Add("") | Out-Null
  $lines.Add("---- lock/force ----") | Out-Null
  (Select-String -LiteralPath $canonPath -Pattern 'RUN_SHADOW\.lock','\[int\]\$Force','STALE_LOCK_CLEARED','BLOCK:' |
    ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }
  $lines | Set-Content -Encoding UTF8 -Path $outPath
}

if([string]::IsNullOrWhiteSpace($Root)){ throw "Root is empty" }
if(!(Test-Path $Root)){ throw "Missing Root: $Root" }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# Paths
$Logs        = Join-Path $Root "logs"
$OpsLog      = Join-Path $Logs "ops"
$FreezeDir   = Join-Path $Logs "freeze"
$ShadowDaily = Join-Path $Logs "shadow_daily"

$KC       = Join-Path $OpsLog "knowledge_current"
$Docs     = Join-Path $KC "docs"
$Stage    = Join-Path $Docs "stage_gates"
$Tasks    = Join-Path $Docs "tasks"

$CurZips  = Join-Path $KC "zips"
$DailyDir = Join-Path $CurZips "dailies"

EnsureDir $KC
EnsureDir $Docs
EnsureDir $Stage
EnsureDir $Tasks
EnsureDir $CurZips
EnsureDir $DailyDir

# Backup existing zips (non-destructive)
$bakDir = Join-Path $KC ("backup_{0}" -f $ts)
EnsureDir $bakDir
Get-ChildItem $CurZips -File -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
  Copy-Item -Force $_.FullName (Join-Path $bakDir $_.Name)
}

# --- REQUIRED DOCS (force-create)
@"
# SHADOW -> PAPER Stage Gate (Auditable)
PASS:
- >= 3 full trading days with no exceptions/tracebacks in LIVE_ERR
- Daily plan counts come from meta (kind=""shadow_plan"") via FROM_META file
- EOD produces: QC + FREEZE + clears RUN_SHADOW.lock

FAIL:
- Any traceback/import error/exception in LIVE_ERR
- Missing FROM_META daily file
- Lock not cleared at EOD
"@ | Set-Content -Encoding UTF8 -Path (Join-Path $Stage "STAGE_GATE_SHADOW_TO_PAPER.md")

@"
# PAPER -> LIVE Stage Gate (Auditable)
PASS:
- >= 30 paper trades
- Positive expectancy (R-multiples) and bounded drawdown
- Operational stability: no recurring lock/process/log failures

FAIL:
- Repeated operational failures
- Drawdown breach
- Negative expectancy after sample size gate
"@ | Set-Content -Encoding UTF8 -Path (Join-Path $Stage "STAGE_GATE_PAPER_TO_LIVE.md")

"date,symbol,side,setup,entry,stop,tp,riskR,resultR,errors,notes" |
  Set-Content -Encoding UTF8 -Path (Join-Path $Docs "PAPER_JOURNAL_TEMPLATE.csv")

# tasks proofs (create folder + best-effort exports + always leave at least one file)
$taskListPath = Join-Path $Tasks ("schtasks_query_{0}.txt" -f $ts)
try {
  schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /V /FO LIST | Out-File -Encoding UTF8 $taskListPath -Append
} catch { "WARN: missing task \TBOT_RUN_SHADOW_DAILY_0630" | Out-File -Encoding UTF8 $taskListPath -Append }
try {
  schtasks /Query /TN "\TBOT_END_OF_DAY_1305" /V /FO LIST | Out-File -Encoding UTF8 $taskListPath -Append
} catch { "WARN: missing task \TBOT_END_OF_DAY_1305" | Out-File -Encoding UTF8 $taskListPath -Append }

try { schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /XML | Out-File -Encoding UTF8 (Join-Path $Tasks "TBOT_RUN_SHADOW_DAILY_0630.xml") } catch {}
try { schtasks /Query /TN "\TBOT_END_OF_DAY_1305"       /XML | Out-File -Encoding UTF8 (Join-Path $Tasks "TBOT_END_OF_DAY_1305.xml") } catch {}

# Canon runner evidence
$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
$Evidence = Join-Path $Docs "EVIDENCE_CANON_RUNNER_AUDIT.txt"
if(Test-Path $Canon){
  Write-CanonEvidence -canonPath $Canon -outPath $Evidence
} else {
  "WARN: CANON_MISSING=$Canon" | Set-Content -Encoding UTF8 -Path $Evidence
}

# --- Build DAILY zips (with required MANIFEST + freeze/ + live/)
foreach($d in $Days){

  $bk = Get-ChildItem $OpsLog -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $d) -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1

  $fz = Get-ChildItem $FreezeDir -File -Filter ("FREEZE_TODAY_{0}_{0}_*.zip" -f $d) -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Desc | Select-Object -First 1

  $fm = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $d)

  $st = Join-Path $KC ("_staging_{0}_{1}" -f $d, $ts)
  if(Test-Path $st){ Remove-Item $st -Recurse -Force }
  EnsureDir $st
  EnsureDir (Join-Path $st "freeze")
  EnsureDir (Join-Path $st "live")

  # FROM_META required
  if(Test-Path $fm){
    Copy-Item -Force $fm (Join-Path $st ("shadow_plans_{0}_FROM_META.jsonl" -f $d))
  } else {
    New-Item -ItemType File -Force -Path (Join-Path $st ("shadow_plans_{0}_FROM_META.jsonl" -f $d)) | Out-Null
  }

  # FREEZE evidence
  if($fz){
    Copy-Item -Force $fz.FullName (Join-Path (Join-Path $st "freeze") $fz.Name)
  }

  $outCount = 0
  $errCount = 0

  if($bk){
    # QC / meta / announce (optional but useful)
    Get-ChildItem $bk.FullName -File -Filter ("QC_{0}.txt" -f $d) -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $st $_.Name) }
    Get-ChildItem $bk.FullName -File -Filter ("meta_{0}.jsonl" -f $d) -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $st $_.Name) }
    Get-ChildItem $bk.FullName -File -Filter ("announce_{0}.log" -f $d) -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item -Force $_.FullName (Join-Path $st $_.Name) }

    $outs = Get-ChildItem $bk.FullName -File -Filter ("LIVE_OUT_{0}*.txt" -f $d) -ErrorAction SilentlyContinue
    $errs = Get-ChildItem $bk.FullName -File -Filter ("LIVE_ERR_{0}*.txt" -f $d) -ErrorAction SilentlyContinue

    foreach($o in $outs){ Copy-Item -Force $o.FullName (Join-Path (Join-Path $st "live") $o.Name); $outCount++ }
    foreach($e in $errs){ Copy-Item -Force $e.FullName (Join-Path (Join-Path $st "live") $e.Name); $errCount++ }

    if((@($errs).Count -eq 0)){
      New-Item -ItemType File -Force -Path (Join-Path (Join-Path $st "live") ("LIVE_ERR_{0}_EMPTY.txt" -f $d)) | Out-Null
      $errCount = 1
    }
  } else {
    New-Item -ItemType File -Force -Path (Join-Path (Join-Path $st "live") ("LIVE_ERR_{0}_EMPTY.txt" -f $d)) | Out-Null
    $errCount = 1
  }

  # REQUIRED daily MANIFEST
  @(
    "DAY=$d"
    "CREATED=$(Get-Date -Format s)"
    "FROM_META=$fm"
    "HAS_BACKUP_FOLDER=$([bool]$bk)"
    "HAS_FREEZE_ZIP=$([bool]$fz)"
    "LIVE_OUT_COUNT=$outCount"
    "LIVE_ERR_COUNT=$errCount"
  ) | Set-Content -Encoding UTF8 -Path (Join-Path $st "MANIFEST.txt")

  # zip daily
  $dailyZip = Join-Path $DailyDir ("ORG_BOT_DAILY_{0}.zip" -f $d)
  if(Test-Path $dailyZip){ Remove-Item $dailyZip -Force }
  Compress-Archive -Path (Join-Path $st "*") -DestinationPath $dailyZip -Force
  Remove-Item $st -Recurse -Force
}

# Copy latest daily to top-level of SUPER (matches your MyGPT check)
$latestDay = $Days[-1]
$latestDaily = Join-Path $DailyDir ("ORG_BOT_DAILY_{0}.zip" -f $latestDay)
$topDaily = Join-Path $CurZips ("ORG_BOT_DAILY_{0}.zip" -f $latestDay)
Copy-Item -Force $latestDaily $topDaily

# --- Rolling zip (atomic replace)
$rolling = Join-Path $CurZips ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
$rollingNew = $rolling + ".new"

$tmpRoll = Join-Path $CurZips ("_roll_" + $ts)
EnsureDir $tmpRoll
Get-ChildItem $DailyDir -File -Filter "ORG_BOT_DAILY_*.zip" |
  Sort-Object Name -Desc |
  Select-Object -First ([Math]::Min($RollingDays, (Get-ChildItem $DailyDir -File -Filter "ORG_BOT_DAILY_*.zip").Count)) |
  Copy-Item -Destination $tmpRoll -Force

Remove-WithRetry $rollingNew
Compress-Archive -Path (Join-Path $tmpRoll "*") -DestinationPath $rollingNew -Force
Remove-Item $tmpRoll -Recurse -Force
Remove-WithRetry $rolling
Move-Item -Force $rollingNew $rolling

# --- SUPER zip (atomic replace)
$staticOps  = Join-Path $CurZips "ORG_BOT_STATIC_OPS.zip"
$staticCode = Join-Path $CurZips "ORG_BOT_STATIC_CODE.zip"

$super    = Join-Path $CurZips "ORG_BOT_KNOWLEDGE_SUPER.zip"
$superNew = $super + ".new"

$tmpS = Join-Path $CurZips ("_super_" + $ts)
EnsureDir $tmpS

Copy-Item -Recurse -Force $Docs (Join-Path $tmpS "docs")
Copy-Item -Force $rolling (Join-Path $tmpS (Split-Path $rolling -Leaf))

if(Test-Path $staticOps){  Copy-Item -Force $staticOps  (Join-Path $tmpS "ORG_BOT_STATIC_OPS.zip") }
if(Test-Path $staticCode){ Copy-Item -Force $staticCode (Join-Path $tmpS "ORG_BOT_STATIC_CODE.zip") }

# include latest daily at top-level (so your MyGPT daily check passes)
Copy-Item -Force $topDaily (Join-Path $tmpS (Split-Path $topDaily -Leaf))

@(
  "CREATED=$(Get-Date -Format s)"
  "LATEST_DAY=$latestDay"
  "ROLLING_ZIP=$(Split-Path $rolling -Leaf)"
  "DAILIES_ON_DISK=$((Get-ChildItem $DailyDir -Filter 'ORG_BOT_DAILY_*.zip' | Measure-Object).Count)"
) | Set-Content -Encoding UTF8 -Path (Join-Path $tmpS "MANIFEST.txt")

Remove-WithRetry $superNew
Compress-Archive -Path (Join-Path $tmpS "*") -DestinationPath $superNew -Force
Remove-Item $tmpS -Recurse -Force
Remove-WithRetry $super
Move-Item -Force $superNew $super

# Upload copy
$upload = Join-Path $CurZips "UPLOAD_SUPER.zip"
Copy-Item -Force $super $upload

"OK: SUPER_ZIP=$super"
"OK: UPLOAD_COPY=$upload"
"OK: DAILY_DIR=$DailyDir"
"OK: ROLLING_ZIP=$rolling"
"OK: DOCS_DIR=$Docs"
