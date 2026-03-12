param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$RollingDays = 10,
  [int]$KeepDailyZips = 10
)

$ErrorActionPreference="Stop"

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ throw "EnsureDir: path is empty" }
  New-Item -ItemType Directory -Force -Path $p | Out-Null
}

function Remove-WithRetry([string]$p,[int]$tries=25){
  for($i=1;$i -le $tries;$i++){
    try{
      if(Test-Path $p){ Remove-Item $p -Force -ErrorAction Stop }
      return
    } catch {
      Start-Sleep -Milliseconds 250
      [GC]::Collect(); [GC]::WaitForPendingFinalizers()
      if($i -eq $tries){ throw }
    }
  }
}

function Write-CanonEvidence([string]$canonPath,[string]$outPath){
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("EVIDENCE: RUN_LIVE_SHADOW_CANON_V2") | Out-Null
  $lines.Add(("CAPTURED={0}" -f (Get-Date -Format s))) | Out-Null
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

# ---- Paths
if([string]::IsNullOrWhiteSpace($Root)){ throw "Root is empty" }
if(!(Test-Path $Root)){ throw "Missing Root: $Root" }

$KC      = Join-Path $Root "logs\ops\knowledge_current"
$Zips    = Join-Path $KC "zips"
$DailyDir= Join-Path $Zips "dailies"
$Docs    = Join-Path $KC "docs"
$Stage   = Join-Path $Docs "stage_gates"
$Tasks   = Join-Path $Docs "tasks"

EnsureDir $KC
EnsureDir $Zips
EnsureDir $DailyDir
EnsureDir $Docs
EnsureDir $Stage
EnsureDir $Tasks

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# ---- Build required docs (always)
$sg1 = Join-Path $Stage "STAGE_GATE_SHADOW_TO_PAPER.md"
$sg2 = Join-Path $Stage "STAGE_GATE_PAPER_TO_LIVE.md"
$jrn = Join-Path $Docs  "PAPER_JOURNAL_TEMPLATE.csv"
$ev  = Join-Path $Docs  "EVIDENCE_CANON_RUNNER_AUDIT.txt"

@"
# SHADOW -> PAPER Stage Gate (Auditable)
PASS:
- >= 3 full trading days with no exceptions/tracebacks
- FROM_META exists and used as count source
- EOD produces freeze + QC + clears lock
FAIL:
- any traceback/import error/exception
"@ | Set-Content -Encoding UTF8 -Path $sg1

@"
# PAPER -> LIVE Stage Gate (Auditable)
PASS:
- >= 30 paper trades
- positive expectancy + bounded drawdown
FAIL:
- repeated operational failures or DD breach
"@ | Set-Content -Encoding UTF8 -Path $sg2

"date,symbol,side,setup,entry,stop,tp,riskR,resultR,errors,notes" |
  Set-Content -Encoding UTF8 -Path $jrn

$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
if(Test-Path $Canon){ Write-CanonEvidence -canonPath $Canon -outPath $ev }
else { "WARN: CANON_MISSING=$Canon" | Set-Content -Encoding UTF8 -Path $ev }

# Task proofs (best-effort, but ensure folder non-empty)
$taskList = Join-Path $Tasks ("schtasks_query_{0}.txt" -f $ts)
try{
  schtasks /Query /TN "\TBOT_RUN_SHADOW_DAILY_0630" /V /FO LIST | Out-File -Encoding UTF8 $taskList -Append
  schtasks /Query /TN "\TBOT_END_OF_DAY_1305"       /V /FO LIST | Out-File -Encoding UTF8 $taskList -Append
} catch {
  "WARN: schtasks query failed" | Out-File -Encoding UTF8 $taskList -Append
}

# ---- Choose daily zips (ignore comma-name junk)
$dailies = Get-ChildItem $DailyDir -File -Filter "ORG_BOT_DAILY_*.zip" |
  Where-Object { $_.Name -notmatch ',' } |
  Sort-Object Name -Desc

if(@($dailies).Count -eq 0){ throw "NO_DAILY_ZIPS_FOUND: $DailyDir" }

$takeN = [Math]::Min($KeepDailyZips, @($dailies).Count)
$dTake = @($dailies | Select-Object -First $takeN)

# ---- Rebuild rolling from selected dailies
$rolling = Join-Path $Zips ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
$tmpRoll = Join-Path $Zips ("_roll_{0}" -f $ts)
if(Test-Path $tmpRoll){ Remove-Item $tmpRoll -Recurse -Force }
EnsureDir $tmpRoll

$takeRoll = [Math]::Min($RollingDays, @($dTake).Count)
$rTake = @($dTake | Select-Object -First $takeRoll)
foreach($f in $rTake){ Copy-Item -Force $f.FullName (Join-Path $tmpRoll $f.Name) }

$rollingNew = $rolling + ".new"
Remove-WithRetry $rollingNew
Compress-Archive -Path (Join-Path $tmpRoll "*") -DestinationPath $rollingNew -Force
Remove-Item $tmpRoll -Recurse -Force
Remove-WithRetry $rolling
Move-Item -Force $rollingNew $rolling

# ---- Build MyGPT-friendly SUPER (flat + extracted latest_daily)
$super = Join-Path $Zips "ORG_BOT_KNOWLEDGE_SUPER.zip"
$upload= Join-Path $Zips "UPLOAD_SUPER.zip"

$tmp = Join-Path $Zips ("_super_{0}" -f $ts)
if(Test-Path $tmp){ Remove-Item $tmp -Recurse -Force }
EnsureDir $tmp

# docs/
Copy-Item -Recurse -Force $Docs (Join-Path $tmp "docs")

# dailies/ (top-level folder)
EnsureDir (Join-Path $tmp "dailies")
foreach($f in $dTake){ Copy-Item -Force $f.FullName (Join-Path (Join-Path $tmp "dailies") $f.Name) }

# latest_daily/ (extract newest daily zip)
$latest = @($dTake | Sort-Object Name -Desc | Select-Object -First 1)[0]
$latestDir = Join-Path $tmp "latest_daily"
EnsureDir $latestDir
Expand-Archive -LiteralPath $latest.FullName -DestinationPath $latestDir -Force

# rolling + static zips
Copy-Item -Force $rolling (Join-Path $tmp (Split-Path $rolling -Leaf))

$staticOps  = Join-Path $Zips "ORG_BOT_STATIC_OPS.zip"
$staticCode = Join-Path $Zips "ORG_BOT_STATIC_CODE.zip"
if(Test-Path $staticOps){  Copy-Item -Force $staticOps  (Join-Path $tmp "ORG_BOT_STATIC_OPS.zip") }
if(Test-Path $staticCode){ Copy-Item -Force $staticCode (Join-Path $tmp "ORG_BOT_STATIC_CODE.zip") }

# MANIFEST
@(
  ("CREATED={0}" -f (Get-Date -Format s))
  ("ROLLING_ZIP={0}" -f (Split-Path $rolling -Leaf))
  ("ROLLING_COUNT={0}" -f @($rTake).Count)
  ("DAILIES_COUNT={0}" -f @($dTake).Count)
  ("LATEST_DAILY={0}" -f $latest.Name)
) | Set-Content -Encoding UTF8 -Path (Join-Path $tmp "MANIFEST.txt")

# ---- Create SUPER (atomic)
$superNew = $super + ".new"
Remove-WithRetry $superNew
Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $superNew -Force
Remove-WithRetry $super
Move-Item -Force $superNew $super

# stable upload copy
Copy-Item -Force $super $upload

# ---- Final audit for MyGPT (no nested zip dependency)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zs=[IO.Compression.ZipFile]::OpenRead($super)
$missing=@()
try{
  $needExact = @(
    "MANIFEST.txt",
    "docs/stage_gates/STAGE_GATE_SHADOW_TO_PAPER.md",
    "docs/stage_gates/STAGE_GATE_PAPER_TO_LIVE.md",
    "docs/PAPER_JOURNAL_TEMPLATE.csv",
    "docs/EVIDENCE_CANON_RUNNER_AUDIT.txt",
    ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays),
    "ORG_BOT_STATIC_OPS.zip",
    "ORG_BOT_STATIC_CODE.zip",
    "latest_daily/MANIFEST.txt"
  )
  foreach($p in $needExact){
    if(@($zs.Entries | Where-Object { $_.FullName -eq $p }).Count -eq 0){ $missing += $p }
  }

  # folders (exist by prefix)
  $needPrefix = @(
    "docs/tasks/",
    "dailies/",
    "latest_daily/freeze/",
    "latest_daily/live/"
  )
  foreach($p in $needPrefix){
    if(@($zs.Entries | Where-Object { $_.FullName -like "$p*" }).Count -eq 0){ $missing += $p }
  }

  # live err
  if(@($zs.Entries | Where-Object { $_.FullName -like "latest_daily/live/LIVE_ERR_*" }).Count -eq 0){
    $missing += "latest_daily/live/LIVE_ERR_*"
  }

  if($missing.Count -eq 0){
    "AUDIT_PASS=True"
  } else {
    "AUDIT_PASS=False"
    $missing | ForEach-Object { "MISSING:$($_)" }
    exit 2
  }
} finally {
  $zs.Dispose()
  Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

"OK: SUPER_ZIP=$super"
"OK: UPLOAD_FILE=$upload"
