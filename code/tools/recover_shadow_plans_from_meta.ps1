param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [Parameter(Mandatory=$true)][string]$Day,
  [string]$TimeZoneId = "Pacific Standard Time",
  [string]$OutPath = ""
)

$ErrorActionPreference="Stop"

$Logs = Join-Path $Root "logs"
$Meta = Join-Path $Logs "meta.jsonl"

if (-not (Test-Path $Meta)) { throw "meta.jsonl not found" }

$tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZoneId)

if (-not $OutPath -or $OutPath.Trim() -eq "") {
  $OutPath = Join-Path $Logs ("shadow_daily\shadow_plans_{0}_FROM_META.jsonl" -f $Day)
}
New-Item -ItemType Directory -Force -Path (Split-Path $OutPath) | Out-Null

$startLocal = [datetime]::ParseExact($Day,"yyyyMMdd",$null).Date
$endLocal = $startLocal.AddDays(1)

$recs = New-Object System.Collections.Generic.List[object]

Get-Content -Path $Meta | ForEach-Object {
  try { $o = $_ | ConvertFrom-Json } catch { return }
  if ($o.kind -ne "shadow_plan") { return }

  $tsLocal = [datetime]::Parse($o.ts)

  if ($tsLocal -lt $startLocal -or $tsLocal -ge $endLocal) { return }

  $tsUtc = [System.TimeZoneInfo]::ConvertTimeToUtc($tsLocal, $tz)
  $tsUtcStr = $tsUtc.ToString("yyyy-MM-ddTHH:mm:ss")

  $p = $o.payload

  $rec = [ordered]@{
    ts=$tsUtcStr
    env="PAPER"
    sid=$p.sid
    symbol=$p.symbol
    side=$p.side
    confidence=$p.confidence
    reason=$p.reason
    entry=$p.entry
    stop=$p.stop
    tp=$p.tp
    qty=$p.qty
    risk_usd=$p.risk_usd
    per_share_risk=$p.per_share_risk
    rr=$p.rr
    notes="recovered_from_meta"
  }

  $recs.Add([pscustomobject]$rec) | Out-Null
}

$recs = $recs | Sort-Object ts

$recs | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content -Encoding UTF8 -Path $OutPath

"OUT=" + $OutPath
"COUNT=" + $recs.Count
if ($recs.Count -gt 0) {
  "FIRST=" + ($recs[0].ts)
  "LAST=" + ($recs[$recs.Count-1].ts)
}
