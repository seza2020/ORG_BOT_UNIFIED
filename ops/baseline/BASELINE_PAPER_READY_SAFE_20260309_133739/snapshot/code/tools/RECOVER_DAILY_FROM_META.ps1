param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [string]$Day = ""  # optional: yyyy-MM-dd; if empty use latest day in meta
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Log([string]$m){ Write-Host ("[{0}] {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $m) }

$Meta = Join-Path $ProjectPath "logs\meta.jsonl"
if (-not (Test-Path -LiteralPath $Meta)) { throw "MISSING:logs/meta.jsonl" }

$LatestDaily = Join-Path $ProjectPath "latest_daily"
$LiveDir = Join-Path $LatestDaily "live"
$FreezeDir = Join-Path $LatestDaily "freeze"
Ensure-Dir $LatestDaily
Ensure-Dir $LiveDir
Ensure-Dir $FreezeDir

Log "LOAD_META"
$lines = Get-Content -LiteralPath $Meta -ErrorAction Stop

# Detect day if not provided
if ([string]::IsNullOrWhiteSpace($Day)) {
  $lastTs = $null
  foreach($ln in $lines){
    if ([string]::IsNullOrWhiteSpace($ln)) { continue }
    try { $o = $ln | ConvertFrom-Json } catch { continue }
    if (-not $o -or -not $o.ts) { continue }
    try { $t = [datetime]$o.ts } catch { continue }
    if ($lastTs -eq $null -or $t -gt $lastTs) { $lastTs = $t }
  }
  if ($lastTs -eq $null) { throw "META_HAS_NO_TS" }
  $Day = $lastTs.ToString("yyyy-MM-dd")
}

Log ("RECOVER_DAY=" + $Day)

# Write FROM_META slice
$outFrom = Join-Path $LatestDaily ("FROM_META_{0}.jsonl" -f $Day.Replace("-",""))
if (Test-Path -LiteralPath $outFrom) { Remove-Item -LiteralPath $outFrom -Force }
$count = 0

foreach($ln in $lines){
  if ([string]::IsNullOrWhiteSpace($ln)) { continue }
  try { $o = $ln | ConvertFrom-Json } catch { continue }
  if (-not $o -or -not $o.ts) { continue }
  try { $t = [datetime]$o.ts } catch { continue }
  if ($t.ToString("yyyy-MM-dd") -eq $Day) {
    Add-Content -LiteralPath $outFrom -Encoding UTF8 -Value $ln
    $count++
  }
}

# Ensure LIVE_ERR exists even if placeholder
$err = Join-Path $LiveDir ("LIVE_ERR_{0}_PLACEHOLDER.txt" -f $Day.Replace("-",""))
if (-not (Test-Path -LiteralPath $err)) {
  Set-Content -LiteralPath $err -Encoding UTF8 -Value "LIVE_ERR_PLACEHOLDER (recovery coverage)"
}

# Write QC summary
$qc = Join-Path $LatestDaily ("QC_{0}.txt" -f $Day.Replace("-",""))
@(
  ("QC DATE={0}" -f $Day)
  "QC_RESULT=RECOVERED"
  ("FROM_META_FILE={0}" -f (Split-Path $outFrom -Leaf))
  ("FROM_META_LINES={0}" -f $count)
  ("LIVE_ERR_FILE={0}" -f (Split-Path $err -Leaf))
) | Set-Content -LiteralPath $qc -Encoding UTF8

Log "OK: RECOVERY_DONE"
Log ("WROTE_FROM_META=" + $outFrom)
Log ("WROTE_QC=" + $qc)
Log ("ENSURED_LIVE_ERR=" + $err)
