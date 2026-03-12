param(
  [Parameter(Mandatory=$false)][string]$Root = "C:\alpaca-bot\org_bot",
  [Parameter(Mandatory=$false)][string]$MarketDay = "",
  [Parameter(Mandatory=$false)][string]$BuilderPath = "",
  [Parameter(Mandatory=$false)][int]$RollingDays = 10,
  [Parameter(Mandatory=$false)][int]$KeepHistory = 7,
  [Parameter(Mandatory=$false)][int]$MaxZipMB = 490
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Fail([string]$msg){ Write-Host ("FAIL: " + $msg); exit 1 }
function Info([string]$msg){ Write-Host ("[INFO] " + $msg) }
function Ensure-Dir([string]$p){ New-Item -ItemType Directory -Force -Path $p | Out-Null }

function Find-BuilderDefault([string]$root){
  # Hard preference: tools\BUILD_MYGPT_DAILY.ps1 (your current canonical builder)
  $b = Join-Path $root "tools\BUILD_MYGPT_DAILY.ps1"
  if(Test-Path -LiteralPath $b){ return $b }

  # Fallback: newest *MYGPT*.ps1 under tools/ops
  $ops = Join-Path $root "tools\ops"
  if(Test-Path -LiteralPath $ops){
    $fallback = Get-ChildItem -LiteralPath $ops -File -Filter "*MYGPT*.ps1" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($fallback){ return $fallback.FullName }
  }
  return ""
}

function Tar-List([string]$zip){
  try{
    $out = & tar -tf $zip 2>$null
    if($out){ return @($out) } else { return @() }
  } catch {
    return @()
  }
}

function Find-EmbeddedDailyEntries([string]$rollingZip){
  $lines = Tar-List $rollingZip
  if($lines.Count -lt 1){ Fail "CANNOT_OPEN_ZIP: $rollingZip" }

  $entries = @()
  foreach($p in $lines){
    if($p -match 'ORG_BOT_DAILY_(\d{8})\.zip$'){
      $entries += [pscustomobject]@{ Path=$p; Day=$Matches[1] }
    }
  }
  if($entries.Count -lt 1){ Fail "NO_DAILY_FOUND_IN_ROLLING" }
  return ($entries | Sort-Object Day -Descending)
}

function Get-MarketDay-Auto([string]$rollingZip){
  # Pick newest daily that CONTAINS QC_YYYYMMDD.txt (holiday-safe).
  $dailies = @(Find-EmbeddedDailyEntries $rollingZip | Select-Object -First 10)

  foreach($d in $dailies){
    $tmpDir = Join-Path $env:TEMP ("MYGPT_MD_" + [Guid]::NewGuid().ToString("N"))
    Ensure-Dir $tmpDir

    & tar -xf $rollingZip -C $tmpDir $d.Path 2>$null | Out-Null
    $embedded = Join-Path $tmpDir $d.Path
    if(-not (Test-Path -LiteralPath $embedded)){ continue }

    $dailyZipLocal = Join-Path $tmpDir ("daily_" + $d.Day + ".zip")
    Move-Item -LiteralPath $embedded -Destination $dailyZipLocal -Force

    $qcName = ("QC_{0}.txt" -f $d.Day)
    $dailyList = Tar-List $dailyZipLocal
    $hasQC = @($dailyList | Where-Object { $_ -match ("(^|/)" + [regex]::Escape($qcName) + "$") })

    if($hasQC.Count -ge 1){ return $d.Day }
  }

  # Fallback: newest daily by name
  return ((Find-EmbeddedDailyEntries $rollingZip | Select-Object -First 1).Day)
}

function Assert-File([string]$p,[string]$label){
  if(-not (Test-Path -LiteralPath $p)){ Fail ("MISSING_" + $label + ": " + $p) }
}

Info "ROOT=$Root"
if(-not (Test-Path -LiteralPath $Root)){ Fail "MISSING_ROOT" }

if([string]::IsNullOrWhiteSpace($BuilderPath)){
  $BuilderPath = Find-BuilderDefault $Root
}
if([string]::IsNullOrWhiteSpace($BuilderPath) -or -not (Test-Path -LiteralPath $BuilderPath)){
  Fail "MISSING_BUILDER (pass -BuilderPath or ensure tools\BUILD_MYGPT_DAILY.ps1 exists)"
}
Info "BUILDER=$BuilderPath"

Info "RUN_BUILDER..."
& pwsh -NoProfile -ExecutionPolicy Bypass -File $BuilderPath -ProjectPath $Root -RollingDays $RollingDays -KeepHistory $KeepHistory -MaxZipMB $MaxZipMB

$LatestDir = Join-Path $Root "_MYGPT_UPLOAD\LATEST"
Assert-File $LatestDir "LATEST_DIR"
Info "LATEST_DIR=$LatestDir"

$Manifest   = Join-Path $LatestDir "MANIFEST.txt"
$StaticCode = Join-Path $LatestDir "MYGPT_STATIC_CODE.zip"
$StaticDocs = Join-Path $LatestDir "MYGPT_STATIC_DOCS.zip"
$StaticOps  = Join-Path $LatestDir "MYGPT_STATIC_OPS.zip"
$RollingZip = Join-Path $LatestDir "MYGPT_ROLLING_LAST10.zip"
$DailyLatest= Join-Path $LatestDir "MYGPT_DAILY_LATEST.zip"

Assert-File $Manifest "OUTPUT"
Assert-File $StaticCode "OUTPUT"
Assert-File $StaticDocs "OUTPUT"
Assert-File $StaticOps "OUTPUT"
Assert-File $RollingZip "OUTPUT"
Assert-File $DailyLatest "OUTPUT"

Info "OUTPUTS_PRESENT=6"

# V1) Docs sanity
Info "VERIFY_V1: MYGPT_STATIC_DOCS.zip contains docs/tasks + proof + QC_WARN_LOG"
$docsList  = Tar-List $StaticDocs

$tasksHits = @($docsList | Where-Object { $_ -match '^(\./)?docs/tasks/' })
if($tasksHits.Count -lt 1){ Fail "MISSING:docs/tasks/ inside MYGPT_STATIC_DOCS.zip" }

$proofHits = @($docsList | Where-Object { $_ -match '^(\./)?docs/tasks/TASK_PROOF_TBOT_POSTFIX_DAILY_EVIDENCE_1306_' })
if($proofHits.Count -lt 1){ Fail "MISSING:TASK_PROOF_TBOT_POSTFIX_DAILY_EVIDENCE_1306_* inside MYGPT_STATIC_DOCS.zip" }

$warnHits  = @($docsList | Where-Object { $_ -match '^(\./)?docs/issues/QC_WARN_LOG\.md$' })
if($warnHits.Count -lt 1){ Fail "MISSING:docs/issues/QC_WARN_LOG.md inside MYGPT_STATIC_DOCS.zip" }

Info ("DOCS_TASKS_COUNT=" + $tasksHits.Count)
Info ("DOCS_PROOF_COUNT=" + $proofHits.Count)

# V2) Rolling must include canonical meta tail
Info "VERIFY_V2: rolling has tails/meta_tail.jsonl"
$rollList = Tar-List $RollingZip
$metaTail = @($rollList | Where-Object { $_ -match '^(\./)?tails/meta_tail\.jsonl$' })
if($metaTail.Count -lt 1){ Fail "MISSING:tails/meta_tail.jsonl inside MYGPT_ROLLING_LAST10.zip" }

# Determine MarketDay
if([string]::IsNullOrWhiteSpace($MarketDay)){
  $MarketDay = Get-MarketDay-Auto $RollingZip
  Info ("MARKET_DAY_AUTO=" + $MarketDay)
} else {
  Info ("MARKET_DAY_OVERRIDE=" + $MarketDay)
}

# V3) Verify MARKET_DAY daily zip inside rolling has QC + LIVE_ERR_*
Info "VERIFY_V3: daily for MARKET_DAY has QC + LIVE_ERR_*"
$dailyEntries = @(Find-EmbeddedDailyEntries $RollingZip)
$target = $dailyEntries | Where-Object { $_.Day -eq $MarketDay } | Select-Object -First 1
if(-not $target){ Fail ("MISSING_DAILY_IN_ROLLING: ORG_BOT_DAILY_" + $MarketDay + ".zip") }

$tmpDir2 = Join-Path $env:TEMP ("MYGPT_DAILYCHK_" + [Guid]::NewGuid().ToString("N"))
Ensure-Dir $tmpDir2
& tar -xf $RollingZip -C $tmpDir2 $target.Path 2>$null | Out-Null
$embedded2 = Join-Path $tmpDir2 $target.Path
if(-not (Test-Path -LiteralPath $embedded2)){ Fail "EMBEDDED_DAILY_EXTRACT_FAIL" }

$dailyZip2 = Join-Path $tmpDir2 ("daily_" + $MarketDay + ".zip")
Move-Item -LiteralPath $embedded2 -Destination $dailyZip2 -Force

$dailyList2 = Tar-List $dailyZip2
$qcName2 = ("QC_{0}.txt" -f $MarketDay)

$hasQC2 = @($dailyList2 | Where-Object { $_ -match ("(^|/)" + [regex]::Escape($qcName2) + "$") })
if($hasQC2.Count -lt 1){ Fail ("MISSING:" + $qcName2 + " inside ORG_BOT_DAILY_" + $MarketDay + ".zip") }

$errHits2 = @($dailyList2 | Where-Object { $_ -match '(^|/)LIVE_ERR_' })
if($errHits2.Count -lt 1){ Fail ("MISSING:LIVE_ERR_* inside ORG_BOT_DAILY_" + $MarketDay + ".zip") }

Info ("DAILY_ZIP_IN_ROLLING=" + $target.Path)
Info ("QC_PRESENT=" + $qcName2)
Info ("LIVE_ERR_COUNT=" + $errHits2.Count)

Write-Host ""
Write-Host "READY_TO_UPLOAD"
Write-Host ("UPLOAD_1=" + $Manifest)
Write-Host ("UPLOAD_2=" + $StaticCode)
Write-Host ("UPLOAD_3=" + $StaticDocs)
Write-Host ("UPLOAD_4=" + $StaticOps)
Write-Host ("UPLOAD_5=" + $RollingZip)
Write-Host ("UPLOAD_6=" + $DailyLatest)
Write-Host ("MARKET_DAY=" + $MarketDay)
Write-Host "PASS"
