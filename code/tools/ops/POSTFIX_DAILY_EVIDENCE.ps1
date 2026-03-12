param(
  [Parameter(Mandatory=$false)][string]$Root = "C:\alpaca-bot\org_bot"
)

$ErrorActionPreference = "Stop"

function Find-LatestDailyZip {
  param([string]$Root)
  $candidates = @(
    (Join-Path $Root "logs\ops\knowledge_archive\daily_zips"),
    (Join-Path $Root "logs\mygpt_pack\publish")
  )
  $hits = @()
  foreach($d in $candidates){
    if (Test-Path -LiteralPath $d){
      $hits += Get-ChildItem -LiteralPath $d -File -Filter "ORG_BOT_DAILY_*.zip" -ErrorAction SilentlyContinue
    }
  }
  if (-not $hits) { return $null }
  return ($hits | Sort-Object LastWriteTime -Desc | Select-Object -First 1)
}

function Get-DayStampFromName {
  param([string]$Name)
  $m = [regex]::Match($Name, 'ORG_BOT_DAILY_(\d{8})\.zip', 'IgnoreCase')
  if ($m.Success) { return $m.Groups[1].Value }
  return "UNKNOWN"
}

function Ensure-LiveErrInDailyZip {
  param([string]$ZipPath)

  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $work  = Join-Path $env:TEMP ("POSTFIX_DAILY_" + $stamp)
  New-Item -ItemType Directory -Force -Path $work | Out-Null

  tar -xf $ZipPath -C $work

  $existingErr = Get-ChildItem -LiteralPath $work -Recurse -File -Filter "LIVE_ERR_*" -ErrorAction SilentlyContinue
  if ($existingErr) {
    return @{ injected = $false; workdir = $work }
  }

  $liveDir = Join-Path $work "live"
  if (-not (Test-Path -LiteralPath $liveDir)) {
    New-Item -ItemType Directory -Force -Path $liveDir | Out-Null
  }

  $ph = Join-Path $liveDir ("LIVE_ERR_PLACEHOLDER_{0}.txt" -f $stamp)
  @"
LIVE_ERR_PLACEHOLDER
Replace with real LIVE_ERR_* outputs when available.
"@ | Set-Content -LiteralPath $ph -Encoding UTF8

  $tmp = Join-Path (Split-Path $ZipPath -Parent) ("_tmp_" + (Split-Path $ZipPath -Leaf))
  if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }

  tar -a -c -f $tmp -C $work .
  Move-Item -LiteralPath $tmp -Destination $ZipPath -Force

  return @{ injected = $true; placeholder = $ph; workdir = $work }
}

function Read-QcResultFromDailyZip {
  param([string]$ZipPath)

  $stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
  $work  = Join-Path $env:TEMP ("QC_READ_" + $stamp)
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  tar -xf $ZipPath -C $work

  $qc = Get-ChildItem -LiteralPath $work -File -Filter "QC_*.txt" -ErrorAction SilentlyContinue |
    Sort-Object Name -Desc | Select-Object -First 1

  if (-not $qc) { return @{ qc="MISSING"; qc_file=$null } }

  $m = Select-String -LiteralPath $qc.FullName -Pattern 'QC_RESULT\s*=\s*(\w+)' -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if (-not $m) { return @{ qc="UNKNOWN"; qc_file=$qc.Name } }

  $val = ($m.Matches[0].Groups[1].Value).ToUpperInvariant()
  return @{ qc=$val; qc_file=$qc.Name }
}

function Append-QcWarnLog {
  param(
    [string]$Root,
    [string]$DayStamp,
    [string]$QcResult,
    [string]$DailyZipName
  )

  $issuesDir = Join-Path $Root "docs\issues"
  New-Item -ItemType Directory -Force -Path $issuesDir | Out-Null

  $log = Join-Path $issuesDir "QC_WARN_LOG.md"
  if (-not (Test-Path -LiteralPath $log)) {
    Set-Content -LiteralPath $log -Encoding UTF8 -Value "# QC WARN/FAIL Log`r`n"
  }

  $marker = "daily_zip=$DailyZipName"
  $already = Select-String -LiteralPath $log -SimpleMatch -Pattern $marker -ErrorAction SilentlyContinue
  if ($already) { return $false }

  $ts = (Get-Date).ToString("s")
  $line = "* $ts day=$DayStamp QC_RESULT=$QcResult $marker"
  Add-Content -LiteralPath $log -Encoding UTF8 -Value $line
  return $true
}

$daily = Find-LatestDailyZip -Root $Root
if (-not $daily) { throw "MISSING:ORG_BOT_DAILY_*.zip (no daily zip found in expected folders)" }

$day = Get-DayStampFromName -Name $daily.Name

$fix = Ensure-LiveErrInDailyZip -ZipPath $daily.FullName
$q   = Read-QcResultFromDailyZip -ZipPath $daily.FullName

$logged = $false
if ($q.qc -eq "WARN" -or $q.qc -eq "FAIL") {
  $logged = Append-QcWarnLog -Root $Root -DayStamp $day -QcResult $q.qc -DailyZipName $daily.Name
}

"POSTFIX_OK"
"DAILY_ZIP=" + $daily.FullName
"DAY=" + $day
"QC_RESULT=" + $q.qc
"QC_FILE=" + ($q.qc_file | ForEach-Object { $_ })
"LIVE_ERR_INJECTED=" + ($fix.injected | ForEach-Object { $_ })
"QC_WARN_LOGGED=" + ($logged | ForEach-Object { $_ })

"VERIFY_LIVE_ERR:"
tar -tf $daily.FullName | findstr /I "LIVE_ERR_"
