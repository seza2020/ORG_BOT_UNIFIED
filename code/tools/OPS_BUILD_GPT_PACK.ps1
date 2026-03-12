param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [string]$Day  = "",
  [string]$TimeZoneId = "Pacific Standard Time",
  [switch]$BuildStatic,
  [switch]$BuildDaily,
  [switch]$BuildAll
)

$ErrorActionPreference="Stop"

function Log([string]$m){
  $ts=(Get-Date -Format "HH:mm:ss")
  Write-Host "[$ts] $m"
}

function Get-PTDay([string]$tzId){
  $tz=[System.TimeZoneInfo]::FindSystemTimeZoneById($tzId)
  $utc=[datetime]::UtcNow
  $pt=[System.TimeZoneInfo]::ConvertTimeFromUtc($utc,$tz)
  return $pt.ToString("yyyyMMdd")
}

if([string]::IsNullOrWhiteSpace($Day)){ $Day = Get-PTDay $TimeZoneId }
if(-not $BuildStatic -and -not $BuildDaily -and -not $BuildAll){ $BuildAll = $true }
if($BuildAll){ $BuildStatic=$true; $BuildDaily=$true }

$OutDir = Join-Path $Root "logs\gpt_pack"
$TmpDir = Join-Path $OutDir "_tmp"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if(Test-Path $TmpDir){ Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null

function Copy-Into([string]$src, [string]$dstRoot, [string]$rel){
  if(!(Test-Path $src)){ return $false }
  $dst = Join-Path $dstRoot $rel
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst -Force
  return $true
}

function Write-Manifest([string]$dstRoot, [string]$name, [string[]]$lines){
  $p = Join-Path $dstRoot $name
  $hdr = @(
    ("CREATED_UTC=" + [datetime]::UtcNow.ToString("o")),
    ("ROOT=" + $Root),
    ("DAY=" + $Day),
    ""
  )
  ($hdr + $lines) | Set-Content -Encoding UTF8 -Path $p
}

function Zip-Staging([string]$stage, [string]$zipPath){
  if(Test-Path $zipPath){ Remove-Item $zipPath -Force -ErrorAction SilentlyContinue }
  Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zipPath -Force
}

# ---------- STATIC PACK ----------
if($BuildStatic){
  Log "BUILD_STATIC..."
  $S = Join-Path $TmpDir "static"
  New-Item -ItemType Directory -Force -Path $S | Out-Null

  $added = New-Object System.Collections.Generic.List[string]
  $missing = New-Object System.Collections.Generic.List[string]

  $staticFiles = @(
    "tools\RUN_LIVE_SHADOW_CANON_V2.ps1",
    "tools\OPS_END_OF_DAY_V2.ps1",
    "tools\recover_shadow_plans_from_meta.ps1",
    "tools\freeze_today_enterprise.ps1",
    "tools\freeze_today_enterprise_SAFE.ps1",
    "tools\CLEAR_TBOT_LOCK.ps1",
    "tools\RUN_SHADOW_UI.ps1",
    "tools\run_shadow.ps1",

    "tbot\main.py",
    "tbot\runtime\orchestrator.py",
    "tbot\runtime\shadow.py",
    "tbot\runtime\shadow_pricing.py",
    "tbot\runtime\meta.py",
    "tbot\runtime\announce.py",
    "tbot\runtime\orch_bridge.py",
    "tbot\runtime\ledger.py",
    "tbot\strategies\s01_core.py",
    "tbot\strategies\s11_alpha.py"
  )

  foreach($rel in $staticFiles){
    $src = Join-Path $Root $rel
    $ok = Copy-Into $src $S $rel
    if($ok){ $added.Add("OK " + $rel) | Out-Null } else { $missing.Add("MISS " + $rel) | Out-Null }
  }

  # Optional docs if they exist
  $docCandidates = @(
    "PROJECT_SNAPSHOT__ALPACA_ORG_BOT__CURRENT.txt",
    "RUNBOOK__SHADOW_DAILY__PT.md",
    "QA__SHADOW_DAILY_CHECKLIST.md",
    "QA__EOD_TEMPLATE.md",
    "QA__PAPER_JOURNAL_TEMPLATE.csv",
    "QA__ERROR_TAGS.md",
    "CODEMAP__KEY_FILES__CURRENT.md"
  )
  foreach($n in $docCandidates){
    $src = Join-Path $Root $n
    $ok = Copy-Into $src $S ("docs\" + $n)
    if($ok){ $added.Add("OK docs\" + $n) | Out-Null }
  }

  Write-Manifest $S "MANIFEST_STATIC.txt" (@("FILES_ADDED:") + $added + @("") + @("FILES_MISSING:") + $missing)

  $zip = Join-Path $OutDir "GPT_STATIC_BASE.zip"
  Zip-Staging $S $zip
  Log ("OUT_STATIC=" + $zip)
}

# ---------- DAILY PACK ----------
if($BuildDaily){
  Log "BUILD_DAILY..."
  $D = Join-Path $TmpDir ("daily_" + $Day)
  New-Item -ItemType Directory -Force -Path $D | Out-Null

  $added = New-Object System.Collections.Generic.List[string]
  $missing = New-Object System.Collections.Generic.List[string]

  $Logs = Join-Path $Root "logs"
  $Ops  = Join-Path $Logs "ops"
  $FreezeDir = Join-Path $Logs "freeze"
  $ShadowDaily = Join-Path $Logs "shadow_daily"

  # 1) Latest FREEZE_BACKUP folder for the day
  $bk = Get-ChildItem -Path $Ops -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $Day) -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

  if($bk){
    $dstBk = Join-Path $D ("FREEZE_BACKUP_{0}" -f $Day)
    New-Item -ItemType Directory -Force -Path $dstBk | Out-Null
    Copy-Item -Path (Join-Path $bk.FullName "*") -Destination $dstBk -Recurse -Force
    $added.Add("OK backup_folder=" + $bk.FullName) | Out-Null
  } else {
    $missing.Add("MISS FREEZE_BACKUP folder for day " + $Day) | Out-Null
  }

  # 2) Latest FREEZE_TODAY zip for the day
  $fz = Get-ChildItem -Path $FreezeDir -File -Filter ("FREEZE_TODAY_{0}_*.zip" -f $Day) -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1

  if($fz){
    $ok = Copy-Into $fz.FullName $D ("FREEZE_TODAY_{0}.zip" -f $Day)
    if($ok){ $added.Add("OK freeze_zip=" + $fz.Name) | Out-Null }
  } else {
    $missing.Add("MISS FREEZE_TODAY zip for day " + $Day) | Out-Null
  }

  # 3) Official daily plans FROM_META
  $fromMeta = Join-Path $ShadowDaily ("shadow_plans_{0}_FROM_META.jsonl" -f $Day)
  if(Test-Path $fromMeta){
    $ok = Copy-Into $fromMeta $D ("shadow_plans_{0}_FROM_META.jsonl" -f $Day)
    if($ok){ $added.Add("OK from_meta_plans=" + $fromMeta) | Out-Null }
  } else {
    $missing.Add("MISS " + $fromMeta) | Out-Null
  }

  # 4) Convenience: include raw live out/err for day (if present)
  $liveOut = Get-ChildItem -Path $Ops -File -Filter ("LIVE_OUT_{0}_*.txt" -f $Day) -ErrorAction SilentlyContinue
  foreach($f in $liveOut){
    $ok = Copy-Into $f.FullName $D ("ops\" + $f.Name)
    if($ok){ $added.Add("OK ops\" + $f.Name) | Out-Null }
  }
  $liveErr = Get-ChildItem -Path $Ops -File -Filter ("LIVE_ERR_{0}_*.txt" -f $Day) -ErrorAction SilentlyContinue
  foreach($f in $liveErr){
    $ok = Copy-Into $f.FullName $D ("ops\" + $f.Name)
    if($ok){ $added.Add("OK ops\" + $f.Name) | Out-Null }
  }

  Write-Manifest $D ("MANIFEST_DAILY_{0}.txt" -f $Day) (@("FILES_ADDED:") + $added + @("") + @("FILES_MISSING:") + $missing)

  $zipDay = Join-Path $OutDir ("GPT_DAILY_{0}.zip" -f $Day)
  Zip-Staging $D $zipDay
  Log ("OUT_DAILY=" + $zipDay)

  # Rolling latest (replace daily)
  $zipLatest = Join-Path $OutDir "GPT_DAILY_LATEST.zip"
  Copy-Item -LiteralPath $zipDay -Destination $zipLatest -Force
  Log ("OUT_LATEST=" + $zipLatest)
}

# Cleanup temp (leave only zips)
if(Test-Path $TmpDir){ Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue }

Log "DONE"
