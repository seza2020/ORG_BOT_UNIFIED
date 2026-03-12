param()

$ErrorActionPreference = "Stop"

$U         = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS       = Join-Path $U "ops"
$DASH      = Join-Path $OPS "dashboard"
$RTP       = Join-Path $U "runtime\paper"
$LOGS      = Join-Path $RTP "logs"

$META      = Join-Path $LOGS "meta_events.jsonl"
$PERF      = Join-Path $LOGS "strategy_perf_events.jsonl"
$LEDGER    = Join-Path $LOGS "risk_ledger_v1.json"
$LOCK      = Join-Path $RTP "locks\tbot_main.lock"

$OUT_JSON  = Join-Path $DASH "project_live_snapshot.json"
$OUT_CSV   = Join-Path $DASH "live_control_table.csv"
$OUT_MD    = Join-Path $DASH "live_control_table.md"
$OUT_HTML  = Join-Path $DASH "live_control_dashboard.html"

$riskUsd = 250.0
try {
  if ($env:TBOT_RISK_PER_TRADE_USD) {
    $riskUsd = [double]$env:TBOT_RISK_PER_TRADE_USD
  }
} catch {}

function Get-JsonlObjects([string]$path) {
  $rows = @()
  if (!(Test-Path $path)) { return $rows }
  foreach ($line in Get-Content $path) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $rows += ($line | ConvertFrom-Json) } catch {}
  }
  return $rows
}

function Get-LastKind($rows, [string]$kind) {
  return @($rows | Where-Object { $_.kind -eq $kind })[-1]
}

function Get-LineCountSafe([string]$path) {
  if (Test-Path $path) { return (Get-Content $path).Count }
  return 0
}

function Get-TbotFamilyInfo {
  $lockPid = $null
  if (Test-Path $LOCK) {
    try {
      $txt = (Get-Content $LOCK -Raw).Trim()
      if ($txt) { $lockPid = [int]$txt }
    } catch {}
  }

  $allPy = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'")
  $procs = @(
    $allPy | Where-Object {
      ($_.CommandLine -match "tbot\.main") -or
      ($_.ExecutablePath -match "ORG_BOT_UNIFIED\\code\\\.venv\\Scripts\\python\.exe") -or
      ($_.ExecutablePath -match "C:\\Python313\\python\.exe") -or
      ($lockPid -ne $null -and [int]$_.ProcessId -eq $lockPid)
    }
  )

  $byPid = @{}
  foreach ($p in $procs) { $byPid[[int]$p.ProcessId] = $p }

  function Get-RootPid([int]$targetPid, $map, $lockPidLocal) {
    $seen = @{}
    $cur = $targetPid
    while ($true) {
      if ($seen.ContainsKey($cur)) { return $cur }
      $seen[$cur] = $true
      if (-not $map.ContainsKey($cur)) { return $cur }
      $proc = $map[$cur]
      $parentPid = [int]$proc.ParentProcessId
      if ($parentPid -le 0) { return $cur }
      if (-not $map.ContainsKey($parentPid)) { return $cur }
      $parent = $map[$parentPid]
      $sameTree = (
        ($parent.CommandLine -match "tbot\.main") -or
        ($parent.ExecutablePath -match "ORG_BOT_UNIFIED\\code\\\.venv\\Scripts\\python\.exe") -or
        ($parent.ExecutablePath -match "C:\\Python313\\python\.exe") -or
        ($lockPidLocal -ne $null -and [int]$parent.ProcessId -eq $lockPidLocal)
      )
      if (($parent.Name -eq "python.exe") -and $sameTree) {
        $cur = $parentPid
        continue
      }
      return $cur
    }
  }

  $rows = foreach ($p in $procs) {
    [PSCustomObject]@{
      RootPid         = Get-RootPid -targetPid ([int]$p.ProcessId) -map $byPid -lockPidLocal $lockPid
      ProcessId       = [int]$p.ProcessId
      ParentProcessId = [int]$p.ParentProcessId
      ExecutablePath  = $p.ExecutablePath
      CommandLine     = $p.CommandLine
      IsLockPid       = ($lockPid -ne $null -and [int]$p.ProcessId -eq $lockPid)
    }
  }

  $families = @(
    $rows | Group-Object RootPid | ForEach-Object {
      $items = $_.Group | Sort-Object ProcessId
      [PSCustomObject]@{
        RootPid         = [int]$_.Name
        MemberCount     = $items.Count
        MemberPids      = (($items.ProcessId) -join ",")
        LockPidPresent  = (($items | Where-Object { $_.IsLockPid }).Count -gt 0)
        ExecutablePaths = (($items.ExecutablePath | Select-Object -Unique) -join " | ")
      }
    }
  ) | Sort-Object RootPid

  return $families
}

$metaRows = Get-JsonlObjects $META
$perfRows = Get-JsonlObjects $PERF

$families = @(Get-TbotFamilyInfo)
$familyCount = $families.Count

$lastHeartbeat = Get-LastKind $metaRows "heartbeat"
$lastRegime    = Get-LastKind $metaRows "regime"
$lastCore      = Get-LastKind $metaRows "core_context"
$lastAlpha     = Get-LastKind $metaRows "alpha_mode"
$lastGate      = Get-LastKind $metaRows "gate_decision"
$lastSkip      = Get-LastKind $metaRows "plan_skipped"
$lastPlan      = Get-LastKind $metaRows "plan_created"

$tailMeta = @()
if (Test-Path $META) { $tailMeta = @(Get-Content $META -Tail 2000) }

$tailPerf = @()
if (Test-Path $PERF) { $tailPerf = @(Get-Content $PERF -Tail 2000) }

$tailMetaObjs = @()
foreach ($line in $tailMeta) {
  try { $tailMetaObjs += ($line | ConvertFrom-Json) } catch {}
}

$tailPerfObjs = @()
foreach ($line in $tailPerf) {
  try { $tailPerfObjs += ($line | ConvertFrom-Json) } catch {}
}

$reasonCounts = @{}
foreach ($r in $tailMetaObjs) {
  try {
    $reason = $null
    if ($r.payload -and $r.payload.reason) { $reason = [string]$r.payload.reason }
    if (![string]::IsNullOrWhiteSpace($reason)) {
      if (!$reasonCounts.ContainsKey($reason)) { $reasonCounts[$reason] = 0 }
      $reasonCounts[$reason]++
    }
  } catch {}
}
$topReasons = @($reasonCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5)

$realizedR = 0.0
$realizedCount = 0
foreach ($r in $perfRows) {
  try {
    if ($null -ne $r.realized_r -and "$($r.realized_r)" -ne "") {
      $realizedR += [double]$r.realized_r
      $realizedCount++
    }
  } catch {}
}
$realizedUsd = [math]::Round($realizedR * $riskUsd, 2)

$planCreatedCount     = ($tailMeta | Select-String '"kind": "plan_created"').Count
$planSkippedCount     = ($tailMeta | Select-String '"kind": "plan_skipped"').Count
$chopEvalCount        = ($tailMeta | Select-String '"kind": "chop_v1_eval"').Count
$chopPlanCreatedCount = ($tailMeta | Select-String '"kind": "chop_v1_plan_created"').Count
$chopRejectedCount    = ($tailMeta | Select-String '"kind": "chop_v1_rejected"').Count
$gateAcceptCount      = ($tailMeta | Select-String '"decision": "ACCEPT"').Count
$regimeExceptionCount = ($tailMeta | Select-String 'regime_exception').Count

$ledgerObj = $null
if (Test-Path $LEDGER) {
  try { $ledgerObj = Get-Content $LEDGER -Raw | ConvertFrom-Json } catch {}
}

$now = Get-Date
$rows = @()

function Add-Row([string]$section,[string]$metric,[string]$value,[string]$notes="") {
  $script:rows += [PSCustomObject]@{
    ts      = $now.ToString("yyyy-MM-dd HH:mm:ss")
    section = $section
    metric  = $metric
    value   = $value
    notes   = $notes
  }
}

Add-Row "Runtime" "family_count" $familyCount
Add-Row "Runtime" "family_root_pids" (($families.RootPid) -join ",")
Add-Row "Runtime" "lock_pid_present" ((@($families | Where-Object { $_.LockPidPresent }).Count -gt 0))
Add-Row "Runtime" "last_heartbeat_ts" ($lastHeartbeat.ts)
Add-Row "Runtime" "meta_line_count" (Get-LineCountSafe $META)
Add-Row "Runtime" "perf_line_count" (Get-LineCountSafe $PERF)

Add-Row "Market" "regime" ($lastRegime.payload.regime)
Add-Row "Market" "confidence" ($lastRegime.payload.confidence)
Add-Row "Market" "regime_reason" ($lastRegime.payload.reason)
Add-Row "Market" "alpha_mode" ($lastAlpha.payload.mode)
Add-Row "Market" "alpha_reason" ($lastAlpha.payload.reason)
Add-Row "Market" "bias" ($lastCore.payload.bias)
Add-Row "Market" "trend_strength" ($lastCore.payload.trend_strength)
Add-Row "Market" "vwap_state" ($lastCore.payload.vwap_state)
Add-Row "Market" "ema_sep" ($lastCore.payload.ema_sep)

Add-Row "Strategy" "last_gate_decision" ($lastGate.payload.decision)
Add-Row "Strategy" "last_gate_reason" ($lastGate.payload.reason)
Add-Row "Strategy" "last_plan_sid" ($lastPlan.payload.sid)
Add-Row "Strategy" "last_skipped_sid" ($lastSkip.payload.sid)
Add-Row "Strategy" "last_skipped_reason" ($lastSkip.payload.reason)
Add-Row "Strategy" "plan_created_count_tail" $planCreatedCount
Add-Row "Strategy" "plan_skipped_count_tail" $planSkippedCount
Add-Row "Strategy" "gate_accept_count_tail" $gateAcceptCount
Add-Row "Strategy" "chop_v1_eval_count_tail" $chopEvalCount
Add-Row "Strategy" "chop_v1_plan_created_count_tail" $chopPlanCreatedCount
Add-Row "Strategy" "chop_v1_rejected_count_tail" $chopRejectedCount

Add-Row "PnL" "realized_r_total" ([math]::Round($realizedR,4))
Add-Row "PnL" "realized_r_count" $realizedCount
Add-Row "PnL" "risk_per_trade_usd" $riskUsd
Add-Row "PnL" "realized_usd_total" $realizedUsd "Computed as realized_r_total * risk_per_trade_usd"

if ($ledgerObj) {
  Add-Row "Risk" "ledger_day_key" ($ledgerObj.day_key)
  Add-Row "Risk" "ledger_week_key" ($ledgerObj.week_key)
  Add-Row "Risk" "daily_budget_used_r" ($ledgerObj.daily_budget_used_r)
  Add-Row "Risk" "weekly_budget_used_r" ($ledgerObj.weekly_budget_used_r)
  Add-Row "Risk" "open_risk_r" ($ledgerObj.open_risk_r)
  Add-Row "Risk" "open_positions_count" ($ledgerObj.open_positions_count)
  Add-Row "Risk" "ledger_last_reason" ($ledgerObj.last_reason)
} else {
  Add-Row "Risk" "ledger_status" "missing_or_unreadable"
}

Add-Row "Stability" "regime_exception_count_tail" $regimeExceptionCount
for ($i = 0; $i -lt $topReasons.Count; $i++) {
  Add-Row "Reasons" ("top_reason_" + ($i+1)) $topReasons[$i].Key ("count=" + $topReasons[$i].Value)
}

$snapshot = [ordered]@{
  ts = $now.ToString("yyyy-MM-dd HH:mm:ss")
  runtime = [ordered]@{
    family_count = $familyCount
    families = $families
    last_heartbeat_ts = $lastHeartbeat.ts
    meta_line_count = Get-LineCountSafe $META
    perf_line_count = Get-LineCountSafe $PERF
  }
  market = [ordered]@{
    regime = $lastRegime.payload.regime
    confidence = $lastRegime.payload.confidence
    regime_reason = $lastRegime.payload.reason
    alpha_mode = $lastAlpha.payload.mode
    alpha_reason = $lastAlpha.payload.reason
    bias = $lastCore.payload.bias
    trend_strength = $lastCore.payload.trend_strength
    vwap_state = $lastCore.payload.vwap_state
    ema_sep = $lastCore.payload.ema_sep
  }
  strategy = [ordered]@{
    last_gate_decision = $lastGate.payload.decision
    last_gate_reason = $lastGate.payload.reason
    last_plan = $lastPlan
    last_skipped = $lastSkip
    plan_created_count_tail = $planCreatedCount
    plan_skipped_count_tail = $planSkippedCount
    gate_accept_count_tail = $gateAcceptCount
    chop_v1_eval_count_tail = $chopEvalCount
    chop_v1_plan_created_count_tail = $chopPlanCreatedCount
    chop_v1_rejected_count_tail = $chopRejectedCount
  }
  pnl = [ordered]@{
    realized_r_total = [math]::Round($realizedR,4)
    realized_r_count = $realizedCount
    risk_per_trade_usd = $riskUsd
    realized_usd_total = $realizedUsd
  }
  risk = $ledgerObj
  top_reasons = @($topReasons | ForEach-Object {
    [ordered]@{ reason = $_.Key; count = $_.Value }
  })
}

$snapshot | ConvertTo-Json -Depth 8 | Out-File $OUT_JSON -Encoding utf8
$rows | Export-Csv $OUT_CSV -NoTypeInformation -Encoding UTF8

$md = @()
$md += "# Enterprise Project Control Table"
$md += ""
$md += "Generated: $($now.ToString("yyyy-MM-dd HH:mm:ss"))"
$md += ""
$md += "| Section | Metric | Value | Notes |"
$md += "|---|---|---:|---|"
foreach ($r in $rows) {
  $val = [string]$r.value
  $notes = [string]$r.notes
  $md += "| $($r.section) | $($r.metric) | $val | $notes |"
}
$md -join "`r`n" | Out-File $OUT_MD -Encoding utf8

$htmlRows = ($rows | ForEach-Object {
  "<tr><td>$($_.section)</td><td>$($_.metric)</td><td>$($_.value)</td><td>$($_.notes)</td></tr>"
}) -join "`n"

$html = @"
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>Enterprise Control Dashboard</title>
<style>
body { font-family: Arial, sans-serif; margin: 20px; background: #fafafa; color: #111; }
h1 { margin-bottom: 4px; }
small { color: #555; }
table { border-collapse: collapse; width: 100%; background: white; }
th, td { border: 1px solid #ddd; padding: 8px; font-size: 13px; text-align: left; }
th { background: #f0f0f0; position: sticky; top: 0; }
.section { font-weight: bold; }
.card { background: white; border: 1px solid #ddd; padding: 12px; margin-bottom: 16px; }
</style>
</head>
<body>
<h1>Enterprise Project Control Dashboard</h1>
<small>Generated: $($now.ToString("yyyy-MM-dd HH:mm:ss"))</small>

<div class="card">
<b>Runtime:</b> family_count=$familyCount |
<b>Regime:</b> $($lastRegime.payload.regime) |
<b>Alpha:</b> $($lastAlpha.payload.mode) |
<b>Bias:</b> $($lastCore.payload.bias) |
<b>Realized P/L:</b> $([math]::Round($realizedR,4)) R / $$realizedUsd
</div>

<table>
<thead>
<tr><th>Section</th><th>Metric</th><th>Value</th><th>Notes</th></tr>
</thead>
<tbody>
$htmlRows
</tbody>
</table>
</body>
</html>
"@

$html | Out-File $OUT_HTML -Encoding utf8

Write-Host "CONTROL_TABLE_OK"
Write-Host "JSON=$OUT_JSON"
Write-Host "CSV=$OUT_CSV"
Write-Host "MD=$OUT_MD"
Write-Host "HTML=$OUT_HTML"
