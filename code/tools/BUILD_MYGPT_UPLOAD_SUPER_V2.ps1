param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$RollingDays = 10,
  [int]$KeepDailyZips = 10
)

$ErrorActionPreference="Stop"

function EnsureDir([string]$p){
  if([string]::IsNullOrWhiteSpace($p)){ throw "EnsureDir: empty path" }
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

function Write-Text([string]$path, [string[]]$lines){
  EnsureDir (Split-Path $path -Parent)
  Set-Content -Encoding UTF8 -Path $path -Value $lines
}

function Secret-Scan([string]$baseDir){
  $needles = @(
    '-----BEGIN PRIVATE KEY-----',
    '-----BEGIN RSA PRIVATE KEY-----',
    'Bearer\s+[A-Za-z0-9\-_\.]{20,}',
    '(?i)\b(apca|alpaca)\b.*\b(secret|key)\b\s*[:=]\s*["'']?[A-Za-z0-9\-_]{20,}["'']?',
    '(?i)\b(token|secret|password)\b\s*[:=]\s*["'']?[A-Za-z0-9\-_]{20,}["'']?'
  )
  $rx = $needles | ForEach-Object { [regex]::new($_) }

  $hits = New-Object System.Collections.Generic.List[string]
  if(!(Test-Path $baseDir)){ return @() }

  $files = Get-ChildItem $baseDir -File -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.Length -le 5MB }

  foreach($f in $files){
    $txt = $null
    try { $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction Stop } catch { continue }
    $txt = [string]$txt
    foreach($r in $rx){
      $m = $r.Match($txt)
      if($m.Success){
        $hits.Add(("SECRET_HIT:{0}::pattern={1}" -f $f.FullName, $r.ToString())) | Out-Null
        break
      }
    }
  }

  # IMPORTANT: return as an array (safe even if empty)
  return @($hits.ToArray())
}

if([string]::IsNullOrWhiteSpace($Root)){ throw "Root is empty" }
if(!(Test-Path $Root)){ throw "Missing Root: $Root" }

$KC       = Join-Path $Root "logs\ops\knowledge_current"
$Zips     = Join-Path $KC "zips"
$DailyDir = Join-Path $Zips "dailies"
$Docs     = Join-Path $KC "docs"

EnsureDir $KC
EnsureDir $Zips
EnsureDir $DailyDir
EnsureDir $Docs

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# ensure baseline docs exist
$StageDir = Join-Path $Docs "stage_gates"
$TaskDir  = Join-Path $Docs "tasks"
EnsureDir $StageDir
EnsureDir $TaskDir

# guarantee docs/tasks/* exists (MyGPT requirement)
$taskPlaceholder = Join-Path $TaskDir "TASK_PROOFS_PLACEHOLDER.txt"
if(!(Test-Path $taskPlaceholder)){
  "placeholder (task proofs live here)" | Set-Content -Encoding UTF8 -Path $taskPlaceholder
}

$sg1 = Join-Path $StageDir "STAGE_GATE_SHADOW_TO_PAPER.md"
$sg2 = Join-Path $StageDir "STAGE_GATE_PAPER_TO_LIVE.md"
$jr  = Join-Path $Docs "PAPER_JOURNAL_TEMPLATE.csv"
$ev  = Join-Path $Docs "EVIDENCE_CANON_RUNNER_AUDIT.txt"

if(!(Test-Path $sg1)){
  Write-Text $sg1 @(
    "# SHADOW -> PAPER Stage Gate (Auditable)",
    "",
    "PASS:",
    "- >= 3 full trading days with no exceptions/tracebacks",
    "- FROM_META exists and used as count source",
    "- EOD produces freeze + QC + clears lock",
    "",
    "FAIL:",
    "- any traceback/import error/exception"
  )
}
if(!(Test-Path $sg2)){
  Write-Text $sg2 @(
    "# PAPER -> LIVE Stage Gate (Auditable)",
    "",
    "PASS:",
    "- >= 30 paper trades",
    "- positive expectancy + bounded drawdown",
    "",
    "FAIL:",
    "- repeated operational failures or DD breach"
  )
}
if(!(Test-Path $jr)){
  Write-Text $jr @("date,symbol,side,setup,entry,stop,tp,riskR,resultR,errors,notes")
}
if(!(Test-Path $ev)){
  $canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
  if(Test-Path $canon){
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("---- canon evidence (selected lines) ----") | Out-Null
    (Select-String -LiteralPath $canon -Pattern '\$LOCK\s*=','RUN_SHADOW\.lock','\[int\]\$Force','LIVE_OUT_','LIVE_ERR_','STALE_LOCK_CLEARED','BLOCK:' -ErrorAction SilentlyContinue |
      ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }
    Write-Text $ev $lines.ToArray()
  } else {
    Write-Text $ev @("WARN: canon runner missing at build time: $canon")
  }
}

# pick daily zips (exclude comma names)
$dailies = @(Get-ChildItem $DailyDir -File -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch ',' } |
            Sort-Object Name -Desc |
            Select-Object -First $KeepDailyZips)

if($dailies.Count -eq 0){ throw "NO_DAILIES_FOUND: $DailyDir" }
$latest = $dailies[0]

# staging structure (MyGPT-friendly)
$tmp = Join-Path $KC ("_mygpt_super_" + $ts)
if(Test-Path $tmp){ Remove-Item $tmp -Recurse -Force }
EnsureDir $tmp

# copy docs CONTENTS (avoid docs/docs nesting)
EnsureDir (Join-Path $tmp "docs")
Copy-Item -Recurse -Force (Join-Path $Docs "*") (Join-Path $tmp "docs")

# include dailies/ as plain zips
EnsureDir (Join-Path $tmp "dailies")
foreach($f in $dailies){
  Copy-Item -Force $f.FullName (Join-Path (Join-Path $tmp "dailies") $f.Name)
}

# include rolling + statics as artifacts (not required for MyGPT deep unzip)
$rolling = Join-Path $Zips ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
if(Test-Path $rolling){ Copy-Item -Force $rolling (Join-Path $tmp (Split-Path $rolling -Leaf)) }

$staticOps  = Join-Path $Zips "ORG_BOT_STATIC_OPS.zip"
$staticCode = Join-Path $Zips "ORG_BOT_STATIC_CODE.zip"
if(Test-Path $staticOps){  Copy-Item -Force $staticOps  (Join-Path $tmp "ORG_BOT_STATIC_OPS.zip") }
if(Test-Path $staticCode){ Copy-Item -Force $staticCode (Join-Path $tmp "ORG_BOT_STATIC_CODE.zip") }

# Extract latest daily to latest_daily/ (so MyGPT can verify without zip-in-zip)
$latestDir = Join-Path $tmp "latest_daily"
EnsureDir $latestDir
Expand-Archive -LiteralPath $latest.FullName -DestinationPath $latestDir -Force

# root manifest
Write-Text (Join-Path $tmp "MANIFEST.txt") @(
  ("CREATED={0}" -f (Get-Date -Format s)),
  ("LATEST_DAILY_ZIP={0}" -f $latest.Name),
  ("DAILIES_INCLUDED={0}" -f $dailies.Count),
  ("ROLLING_PRESENT={0}" -f (Test-Path $rolling)),
  ("STATIC_OPS_PRESENT={0}" -f (Test-Path $staticOps)),
  ("STATIC_CODE_PRESENT={0}" -f (Test-Path $staticCode))
)

# SECRET scan ONLY on docs + latest_daily (safe; no false positives from static zips)
$hits = New-Object System.Collections.Generic.List[string]
foreach($h in @(Secret-Scan (Join-Path $tmp "docs"))){        $hits.Add($h) | Out-Null }
foreach($h in @(Secret-Scan (Join-Path $tmp "latest_daily"))){$hits.Add($h) | Out-Null }

$secretReport = Join-Path $tmp "docs\SECRET_SCAN_REPORT.txt"
Write-Text $secretReport (@(("SECRET_HITS={0}" -f $hits.Count)) + @($hits.ToArray()))

if($hits.Count -gt 0){
  throw ("SECRET_SCAN_FAIL: hits={0} report={1}" -f $hits.Count, $secretReport)
}

# create upload zip (unique + stable)
$upload = Join-Path $Zips ("UPLOAD_MYGPT_SUPER_{0}.zip" -f $ts)
$stable = Join-Path $Zips "UPLOAD_SUPER.zip"

Remove-WithRetry $upload
Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $upload -Force
Copy-Item -Force $upload $stable

# minimal audit inside upload zip (NO nested zip checks)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zs = [IO.Compression.ZipFile]::OpenRead($upload)
try{
  $missing = @()

  foreach($p in @(
    "MANIFEST.txt",
    "docs/stage_gates/STAGE_GATE_SHADOW_TO_PAPER.md",
    "docs/stage_gates/STAGE_GATE_PAPER_TO_LIVE.md",
    "docs/PAPER_JOURNAL_TEMPLATE.csv",
    "docs/EVIDENCE_CANON_RUNNER_AUDIT.txt"
  )){
    if(@($zs.Entries | Where-Object { $_.FullName -eq $p }).Count -eq 0){ $missing += $p }
  }

  if(@($zs.Entries | Where-Object { $_.FullName -like "docs/tasks/*" }).Count -eq 0){ $missing += "docs/tasks/" }
  if(@($zs.Entries | Where-Object { $_.FullName -like "dailies/ORG_BOT_DAILY_*.zip" }).Count -eq 0){ $missing += "dailies/ORG_BOT_DAILY_*.zip" }

  if(@($zs.Entries | Where-Object { $_.FullName -eq "latest_daily/MANIFEST.txt" }).Count -eq 0){ $missing += "latest_daily/MANIFEST.txt" }
  if(@($zs.Entries | Where-Object { $_.FullName -like "latest_daily/freeze/*" }).Count -eq 0){ $missing += "latest_daily/freeze/" }
  if(@($zs.Entries | Where-Object { $_.FullName -like "latest_daily/live/*" }).Count -eq 0){ $missing += "latest_daily/live/" }
  if(@($zs.Entries | Where-Object { $_.FullName -like "latest_daily/live/LIVE_ERR_*" }).Count -eq 0){ $missing += "latest_daily/live/LIVE_ERR_*" }

  if($missing.Count -eq 0){
    "AUDIT_PASS=True"
  } else {
    "AUDIT_PASS=False"
    $missing | ForEach-Object { "MISSING:$($_)" }
  }

} finally {
  $zs.Dispose()
}

# cleanup staging
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

"OK: UPLOAD_FILE=$upload"
"OK: STABLE_COPY=$stable"

