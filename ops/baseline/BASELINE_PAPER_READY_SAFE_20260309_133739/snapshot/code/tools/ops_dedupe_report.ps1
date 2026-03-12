[CmdletBinding()]
param(
  [int]$WindowSec = 1800,
  [string]$ShadowJsonl = "C:\alpaca-bot\org_bot\logs\shadow_plans.jsonl"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Parse-IsoTs([string]$s) {
  if ([string]::IsNullOrWhiteSpace($s)) { return $null }
  try {
    return [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture, `
      [System.Globalization.DateTimeStyles]::AssumeLocal)
  } catch {
    return $null
  }
}

$opsDir = "C:\alpaca-bot\org_bot\logs\ops"
if (!(Test-Path $opsDir)) { New-Item -ItemType Directory -Path $opsDir -Force | Out-Null }
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$OutFile = Join-Path $opsDir ("DEDUPE_{0}.txt" -f $ts)

if (!(Test-Path $ShadowJsonl)) {
  @(
    "DEDUPE_REPORT"
    "ShadowJsonl=$ShadowJsonl"
    "ERROR=NOT_FOUND"
    "OUT_DEDUPE=$OutFile"
  ) | Set-Content -LiteralPath $OutFile -Encoding UTF8
  Write-Host "OUT_DEDUPE=$OutFile"
  exit 0
}

$rawLines = @(Get-Content -LiteralPath $ShadowJsonl -Encoding UTF8 -ErrorAction Stop)
$items = @()

foreach ($ln in $rawLines) {
  if ([string]::IsNullOrWhiteSpace($ln)) { continue }
  try { $o = $ln | ConvertFrom-Json -ErrorAction Stop } catch { continue }

  $t = $null
  if ($null -ne $o.ts) { $t = Parse-IsoTs ([string]$o.ts) }
  elseif ($null -ne $o.time) { $t = Parse-IsoTs ([string]$o.time) }
  elseif ($null -ne $o.timestamp) { $t = Parse-IsoTs ([string]$o.timestamp) }

  $items += [pscustomobject]@{
    ts     = $t
    sid    = [string]$o.sid
    symbol = [string]$o.symbol
    side   = [string]$o.side
    entry  = $o.entry
    stop   = $o.stop
    tp     = $o.tp
  }
}

$cut = (Get-Date).AddSeconds(-1 * [math]::Abs($WindowSec))
$items2 = @($items | Where-Object { $_.ts -ne $null -and $_.ts -ge $cut })

$groups = @(
  $items2 |
    Group-Object -Property @{
      Expression = { "{0}|{1}|{2}|{3}|{4}|{5}" -f $_.sid,$_.symbol,$_.side,$_.entry,$_.stop,$_.tp }
    }
)

$dupes = @($groups | Where-Object { $_.Count -ge 2 } | Sort-Object Count -Descending)

@(
  "DEDUPE_REPORT"
  "ShadowJsonl=$ShadowJsonl"
  "WindowSec=$WindowSec"
  "Cutoff=$cut"
  "TotalItems=$($items.Count)"
  "WindowItems=$($items2.Count)"
  "DuplicateGroups=$($dupes.Count)"
  ""
  "TopDuplicates:"
) | Set-Content -LiteralPath $OutFile -Encoding UTF8

$dupes | Select-Object -First 25 | ForEach-Object {
  "COUNT=$($_.Count) KEY=$($_.Name)" | Add-Content -LiteralPath $OutFile -Encoding UTF8
}

"OUT_DEDUPE=$OutFile" | Add-Content -LiteralPath $OutFile -Encoding UTF8
Write-Host "OUT_DEDUPE=$OutFile"
