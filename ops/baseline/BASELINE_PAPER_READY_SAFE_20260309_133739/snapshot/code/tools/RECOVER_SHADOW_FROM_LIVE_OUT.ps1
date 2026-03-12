[CmdletBinding()]
param(
  [string]$Root = 'C:\alpaca-bot\org_bot',
  [string]$IsoDayOverride = ''
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest

$Logs = Join-Path $Root 'logs'
$Ops  = Join-Path $Logs 'ops'

$Now = Get-Date
$IsoDay = if ([string]::IsNullOrWhiteSpace($IsoDayOverride)) { $Now.ToString('yyyy-MM-dd') } else { $IsoDayOverride.Trim() }
try { [void][DateTime]::ParseExact($IsoDay,'yyyy-MM-dd',[System.Globalization.CultureInfo]::InvariantCulture) } catch { throw "IsoDayOverride must be YYYY-MM-DD. Got: $IsoDay" }
$DayFile = ([DateTime]::ParseExact($IsoDay,'yyyy-MM-dd',[System.Globalization.CultureInfo]::InvariantCulture)).ToString('yyyyMMdd')

$Live = @(
  Get-ChildItem -Path $Ops -File -Filter ("LIVE_OUT_{0}_*.txt" -f $DayFile) -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime
)
if (@($Live).Count -eq 0) { throw "No LIVE_OUT files for day=$DayFile in $Ops" }

$SP = Join-Path $Logs 'shadow_plans.jsonl'
$OutPlans  = Join-Path $Logs ("shadow_plans_RECOVERED_{0}.jsonl" -f $DayFile)
$OutReject = Join-Path $Logs ("shadow_rejects_RECOVERED_{0}.jsonl" -f $DayFile)

function Extract-ObjText([string]$line) {
  $i = $line.IndexOf('{')
  $j = $line.LastIndexOf('}')
  if ($i -lt 0 -or $j -le $i) { return $null }
  return $line.Substring($i, $j-$i+1)
}

function Try-ParseJsonLoose([string]$s) {
  # 1) direct JSON
  try { return ($s | ConvertFrom-Json -ErrorAction Stop) } catch {}

  # 2) python-ish dict repair: None/True/False + single quotes
  $t = $s
  $t = $t -replace '\bNone\b','null'
  $t = $t -replace '\bTrue\b','true'
  $t = $t -replace '\bFalse\b','false'
  $t = $t -replace "'", '"'
  try { return ($t | ConvertFrom-Json -ErrorAction Stop) } catch { return $null }
}

function Get-TsFromPrefix([string]$line, [string]$fallbackIsoDay) {
  $mt = [regex]::Match($line, '\b(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\b')
  if ($mt.Success) { return $mt.Groups[1].Value }
  return ($fallbackIsoDay + "T00:00:00")
}

function Ensure-Num([object]$x, [double]$def=0.0) {
  try { return [double]$x } catch { return [double]$def }
}

$bufPlans  = New-Object System.Collections.Generic.List[string]
$bufReject = New-Object System.Collections.Generic.List[string]
$okPlans=0; $badPlans=0
$okRej=0; $badRej=0

$paths = $Live | ForEach-Object FullName

# --- recover plans (accept/plan)
$hitsPlans = Select-String -Path $paths -Pattern '\bshadow_(accept|plan)\b' -ErrorAction SilentlyContinue
foreach ($m in $hitsPlans) {
  $line = $m.Line
  if ($line -notlike "*$IsoDay*") { continue } # day guard

  $objText = Extract-ObjText $line
  if (-not $objText) { $badPlans++; continue }

  $o = Try-ParseJsonLoose $objText
  if ($null -eq $o) { $badPlans++; continue }

  # payload unwrap if present
  $p = $null
  try { $p = $o.payload } catch {}
  if ($null -eq $p) { $p = $o }

  $sid=$null; $symbol=$null; $side=$null
  try { $sid=[string]$p.sid } catch {}
  try { $symbol=[string]$p.symbol } catch {}
  try { $side=[string]$p.side } catch {}

  if ([string]::IsNullOrWhiteSpace($sid) -or [string]::IsNullOrWhiteSpace($symbol) -or [string]::IsNullOrWhiteSpace($side)) {
    $badPlans++; continue
  }

  # stamp
  $ts = Get-TsFromPrefix $line $IsoDay

  # normalize output schema (close to shadow_plans.jsonl)
  $entry = Ensure-Num ($p.entry) 0.0
  $stop  = Ensure-Num ($p.stop) 0.0
  $tp    = Ensure-Num ($p.tp) 0.0
  $qty   = 0
  try { $qty = [int]$p.qty } catch { $qty = 0 }
  $risk  = Ensure-Num ($p.risk_usd) 0.0
  $rr    = Ensure-Num ($p.rr) 0.0
  $conf  = Ensure-Num ($p.confidence) 0.0
  $reason = ''
  try { $reason = [string]$p.reason } catch { $reason='' }

  $perShare = 0.0
  if ($entry -gt 0 -and $stop -gt 0) { $perShare = [Math]::Abs($entry - $stop) }

  $out = [ordered]@{
    ts = $ts
    env = 'PAPER'
    sid = $sid
    symbol = $symbol
    side = $side
    confidence = $conf
    reason = $reason
    entry = $entry
    stop  = $stop
    tp    = $tp
    qty   = $qty
    risk_usd = $risk
    per_share_risk = $perShare
    rr = $rr
    notes = 'recovered_from_live_out'
  }

  # keep reasons[] if present
  try {
    if ($p.PSObject.Properties.Name -contains 'reasons' -and $null -ne $p.reasons) {
      $out.reasons = $p.reasons
    }
  } catch {}

  $bufPlans.Add(($out | ConvertTo-Json -Compress -Depth 12))
  $okPlans++
}

# --- recover rejects separately (for QA)
$hitsReject = Select-String -Path $paths -Pattern '\bshadow_reject\b' -ErrorAction SilentlyContinue
foreach ($m in $hitsReject) {
  $line = $m.Line
  if ($line -notlike "*$IsoDay*") { continue }

  $objText = Extract-ObjText $line
  if (-not $objText) { $badRej++; continue }

  $o = Try-ParseJsonLoose $objText
  if ($null -eq $o) { $badRej++; continue }

  $p = $null
  try { $p = $o.payload } catch {}
  if ($null -eq $p) { $p = $o }

  $ts = Get-TsFromPrefix $line $IsoDay

  $out = [ordered]@{
    ts = $ts
    kind = 'shadow_reject'
    payload = $p
  }
  $bufReject.Add(($out | ConvertTo-Json -Compress -Depth 12))
  $okRej++
}

# --- write outputs
$bufPlans  | Set-Content -Encoding UTF8 -Path $OutPlans
$bufReject | Set-Content -Encoding UTF8 -Path $OutReject

Write-Host ("RECOVER_PLANS_OK={0}  BAD={1}  OUT={2}" -f $okPlans,$badPlans,$OutPlans)
Write-Host ("RECOVER_REJECT_OK={0} BAD={1}  OUT={2}" -f $okRej,$badRej,$OutReject)

# --- refill shadow_plans.jsonl if we recovered anything
if ($okPlans -gt 0) {
  Copy-Item -Force -Path $OutPlans -Destination $SP
  Write-Host ("REFILL_OK SP={0}" -f $SP)
} else {
  Write-Host "REFILL_SKIPPED (no recovered plans)"
}

# --- quick stats
if (Test-Path -Path $SP) {
  Get-Item $SP | Select Name,Length,LastWriteTime | Format-List
}
