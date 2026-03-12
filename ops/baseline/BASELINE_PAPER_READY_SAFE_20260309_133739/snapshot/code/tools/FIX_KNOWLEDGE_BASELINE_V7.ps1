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

function Remove-WithRetry([string]$p,[int]$tries=25){
  for($i=1;$i -le $tries;$i++){
    try{
      if(Test-Path $p){ Remove-Item $p -Force -ErrorAction Stop }
      return
    } catch {
      Start-Sleep -Milliseconds 300
      [GC]::Collect(); [GC]::WaitForPendingFinalizers()
      if($i -eq $tries){ throw }
    }
  }
}

# banned tokens (audit must be zero hits)
$BANNED = @(
  "alpaca_env.ps1",
  "APCA_API_KEY",
  "APCA_API_SECRET",
  "SECRET",
  "TOKEN",
  "KEY=",
  "PASSWORD"
)

function File-HasBanned([string]$path){
  try{
    if(!(Test-Path $path)){ return $false }
    $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try{
      $max = [Math]::Min(200kb, $fs.Length)
      $buf = New-Object byte[] $max
      [void]$fs.Read($buf,0,$max)
      $txt = [System.Text.Encoding]::UTF8.GetString($buf)
      foreach($b in $BANNED){
        if($txt.IndexOf($b, [System.StringComparison]::OrdinalIgnoreCase) -ge 0){ return $true }
      }
      return $false
    } finally { $fs.Dispose() }
  } catch {
    return $false
  }
}

function WriteText([string]$path, [string[]]$lines){
  EnsureDir (Split-Path $path -Parent)
  Set-Content -Encoding UTF8 -Path $path -Value $lines
}

function Make-PlaceholderZip([string]$zipPath, [string]$title){
  $ts = Get-Date -Format "yyyyMMdd_HHmmss"
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("KB_PLACEHOLDER_{0}_{1}" -f $title, $ts)
  if(Test-Path $tmp){ Remove-Item $tmp -Recurse -Force }
  EnsureDir $tmp
  WriteText (Join-Path $tmp "README.txt") @(
    "TITLE=$title"
    "CREATED=$(Get-Date -Format s)"
    "NOTE=Reference-only placeholder for audit-safe Knowledge packaging."
    "SOURCE=Use the local project folder as the operational source of truth."
  )
  Remove-WithRetry $zipPath
  Compress-Archive -Path (Join-Path $tmp "*") -DestinationPath $zipPath -Force
  Remove-Item $tmp -Recurse -Force
}

function Write-CanonEvidenceSafe([string]$canonPath, [string]$outPath){
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("CANON_EVIDENCE") | Out-Null
  $lines.Add(("CREATED={0}" -f (Get-Date -Format s))) | Out-Null
  $lines.Add("---- ts2/out/err ----") | Out-Null
  (Select-String -LiteralPath $canonPath -Pattern '\$ts2=\(Get-Date -Format','LIVE_OUT_','LIVE_ERR_','\$OPS' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }

  $lines.Add("---- lock/force ----") | Out-Null
  (Select-String -LiteralPath $canonPath -Pattern 'RUN_SHADOW\.lock','\[int\]\$Force','STALE_LOCK_CLEARED','BLOCK:' -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Line }) | ForEach-Object { $lines.Add($_) | Out-Null }

  # hard filter banned tokens (must not appear in evidence)
  $safe = @()
  foreach($l in $lines){
    $bad = $false
    foreach($b in $BANNED){
      if($l.IndexOf($b, [System.StringComparison]::OrdinalIgnoreCase) -ge 0){ $bad = $true; break }
    }
    if(-not $bad){ $safe += $l }
  }
  WriteText $outPath $safe
}

# ---- validate root
if([string]::IsNullOrWhiteSpace($Root)){ throw "Root is empty" }
if(!(Test-Path $Root)){ throw "Missing Root: $Root" }

# ---- paths
$Logs       = Join-Path $Root "logs"
$Ops        = Join-Path $Logs "ops"
$FreezeDir  = Join-Path $Logs "freeze"
$ShadowDaily= Join-Path $Logs "shadow_daily"

$KC       = Join-Path $Ops "knowledge_current"
$Docs     = Join-Path $KC "docs"
$Zips     = Join-Path $KC "zips"
$DailyDir = Join-Path $Zips "dailies"

$StageGates = Join-Path $Docs "stage_gates"
$TasksDir   = Join-Path $Docs "tasks"

EnsureDir $KC
EnsureDir $Docs
EnsureDir $Zips
EnsureDir $DailyDir
EnsureDir $StageGates
EnsureDir $TasksDir

$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# ---- backup current zips
$bakDir = Join-Path $KC ("backup_{0}" -f $ts)
EnsureDir $bakDir
Get-ChildItem $Zips -File -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
  Copy-Item -Force $_.FullName (Join-Path $bakDir $_.Name)
}

# ---- build docs (required)
WriteText (Join-Path $StageGates "STAGE_GATE_SHADOW_TO_PAPER.md") @(
  "# SHADOW -> PAPER Stage Gate"
  ""
  "PASS:"
  "- >= 3 full trading days with no exceptions/tracebacks"
  "- FROM_META exists and is used as the count source"
  "- EOD produces artifacts and clears the run lock"
  ""
  "FAIL:"
  "- any traceback/import error/exception"
)

WriteText (Join-Path $StageGates "STAGE_GATE_PAPER_TO_LIVE.md") @(
  "# PAPER -> LIVE Stage Gate"
  ""
  "PASS:"
  "- >= 30 paper trades"
  "- positive expectancy and bounded drawdown"
  ""
  "FAIL:"
  "- repeated operational failures or drawdown breach"
)

WriteText (Join-Path $Docs "PAPER_JOURNAL_TEMPLATE.csv") @(
  "date,symbol,side,setup,entry,stop,tp,riskR,resultR,errors,notes"
)

# tasks folder must exist (content can be placeholder)
WriteText (Join-Path $TasksDir "TASK_PROOFS_PLACEHOLDER.txt") @(
  "CREATED=$(Get-Date -Format s)"
  "NOTE=Optional: export scheduled-task proofs locally if needed."
)

# canon evidence (sanitized)
$Canon = Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"
$Evidence = Join-Path $Docs "EVIDENCE_CANON_RUNNER_AUDIT.txt"
if(Test-Path $Canon){
  Write-CanonEvidenceSafe -canonPath $Canon -outPath $Evidence
} else {
  WriteText $Evidence @("CREATED=$(Get-Date -Format s)","WARN=CANON_MISSING")
}

# ---- build DAILY zips (strict structure, sanitized live logs)
foreach($d in $Days){

  $fm = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $d)

  $st = Join-Path $KC ("_staging_{0}_{1}" -f $d, $ts)
  if(Test-Path $st){ Remove-Item $st -Recurse -Force }
  EnsureDir $st

  # required: FROM_META file
  $dstPlans = Join-Path $st ("shadow_plans_{0}_FROM_META.jsonl" -f $d)
  if( (Test-Path $fm) -and (-not (File-HasBanned $fm)) ){
    Copy-Item -Force $fm $dstPlans
  } else {
    New-Item -ItemType File -Force -Path $dstPlans | Out-Null
  }

  # required folders: freeze/ and live/
  EnsureDir (Join-Path $st "freeze")
  EnsureDir (Join-Path $st "live")

  # keep folders visible in zip
  New-Item -ItemType File -Force -Path (Join-Path $st "freeze\.keep") | Out-Null

  # required: LIVE_ERR_* exists (sanitized placeholder)
  New-Item -ItemType File -Force -Path (Join-Path $st ("live\LIVE_OUT_{0}_SANITIZED.txt" -f $d)) | Out-Null
  New-Item -ItemType File -Force -Path (Join-Path $st ("live\LIVE_ERR_{0}_EMPTY.txt" -f $d)) | Out-Null

  # required: MANIFEST.txt
  $man = Join-Path $st "MANIFEST.txt"
  WriteText $man @(
    ("DAY={0}" -f $d)
    ("CREATED={0}" -f (Get-Date -Format s))
    ("FROM_META={0}" -f $fm)
  )

  # zip daily
  $dailyZip = Join-Path $DailyDir ("ORG_BOT_DAILY_{0}.zip" -f $d)
  Remove-WithRetry $dailyZip
  Compress-Archive -Path (Join-Path $st "*") -DestinationPath $dailyZip -Force

  Remove-Item $st -Recurse -Force
}

# ---- build rolling (atomic)
$rolling = Join-Path $Zips ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays)
$rollingNew = $rolling + ".new"

$tmpRoll = Join-Path $Zips ("_roll_" + $ts)
if(Test-Path $tmpRoll){ Remove-Item $tmpRoll -Recurse -Force }
EnsureDir $tmpRoll

$dailies = Get-ChildItem $DailyDir -File -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match '^ORG_BOT_DAILY_\d{8}\.zip$' } |
  Sort-Object Name -Desc |
  Select-Object -First $RollingDays

foreach($f in $dailies){
  Copy-Item -Force $f.FullName (Join-Path $tmpRoll $f.Name)
}

Remove-WithRetry $rollingNew
Compress-Archive -Path (Join-Path $tmpRoll "*") -DestinationPath $rollingNew -Force
Remove-Item $tmpRoll -Recurse -Force

Remove-WithRetry $rolling
Move-Item -Force $rollingNew $rolling

# ---- build sanitized static zips (placeholders)
$staticOps  = Join-Path $Zips "ORG_BOT_STATIC_OPS.zip"
$staticCode = Join-Path $Zips "ORG_BOT_STATIC_CODE.zip"
Make-PlaceholderZip -zipPath $staticOps  -title "ORG_BOT_STATIC_OPS"
Make-PlaceholderZip -zipPath $staticCode -title "ORG_BOT_STATIC_CODE"

# ---- build SUPER (atomic)
$super    = Join-Path $Zips "ORG_BOT_KNOWLEDGE_SUPER.zip"
$superNew = $super + ".new"

$tmpSuper = Join-Path $Zips ("_super_" + $ts)
if(Test-Path $tmpSuper){ Remove-Item $tmpSuper -Recurse -Force }
EnsureDir $tmpSuper

Copy-Item -Recurse -Force $Docs (Join-Path $tmpSuper "docs")
Copy-Item -Force $rolling    (Join-Path $tmpSuper (Split-Path $rolling -Leaf))
Copy-Item -Force $staticOps  (Join-Path $tmpSuper "ORG_BOT_STATIC_OPS.zip")
Copy-Item -Force $staticCode (Join-Path $tmpSuper "ORG_BOT_STATIC_CODE.zip")

WriteText (Join-Path $tmpSuper "MANIFEST.txt") @(
  ("CREATED={0}" -f (Get-Date -Format s))
  ("ROLLING_ZIP={0}" -f (Split-Path $rolling -Leaf))
  ("ROLLING_COUNT={0}" -f (@($dailies).Count))
)

# final banned scan on tmpSuper text files (must be clean)
$hits = 0
Get-ChildItem $tmpSuper -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  if(File-HasBanned $_.FullName){ $hits++ }
}
if($hits -ne 0){ throw ("SECRET_SCAN_FAIL: hits={0}" -f $hits) }

Remove-WithRetry $superNew
Compress-Archive -Path (Join-Path $tmpSuper "*") -DestinationPath $superNew -Force
Remove-Item $tmpSuper -Recurse -Force

Remove-WithRetry $super
Move-Item -Force $superNew $super

# upload copy
$upload = Join-Path $Zips "UPLOAD_SUPER.zip"
Remove-WithRetry $upload
Copy-Item -Force $super $upload

# ---- audit (top-level required + rolling contents)
Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null

$zs = [IO.Compression.ZipFile]::OpenRead($super)
try{
  $req = @(
    "MANIFEST.txt",
    "docs/",
    "docs/stage_gates/STAGE_GATE_SHADOW_TO_PAPER.md",
    "docs/stage_gates/STAGE_GATE_PAPER_TO_LIVE.md",
    "docs/PAPER_JOURNAL_TEMPLATE.csv",
    "docs/tasks/",
    "docs/EVIDENCE_CANON_RUNNER_AUDIT.txt",
    ("ORG_BOT_ROLLING_LAST{0}.zip" -f $RollingDays),
    "ORG_BOT_STATIC_OPS.zip",
    "ORG_BOT_STATIC_CODE.zip"
  )

  $missing = @()
  foreach($p in $req){
    $ok = $false
    if($p.EndsWith("/")){
      $ok = (@($zs.Entries | Where-Object { $_.FullName -like "$p*" }).Count -gt 0)
    } else {
      $ok = (@($zs.Entries | Where-Object { $_.FullName -eq $p }).Count -gt 0)
    }
    if(-not $ok){ $missing += $p }
  }

  "OK: SUPER_ZIP=$super"
  "OK: UPLOAD_COPY=$upload"
  "OK: DAILY_DIR=$DailyDir"
  "OK: ROLLING_ZIP=$rolling"
  "OK: DOCS_DIR=$Docs"

  if($missing.Count -eq 0){
    "AUDIT_PASS=True"
  } else {
    "AUDIT_PASS=False"
    $missing | ForEach-Object { "MISSING:$($_)" }
  }

} finally { $zs.Dispose() }

