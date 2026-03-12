param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride=""  # YYYY-MM-DD
)
$ErrorActionPreference="Stop"

if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  $IsoDayOverride = (Get-Date).ToString("yyyy-MM-dd")
}
$ymd = $IsoDayOverride.Replace("-","")

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ops,$ana | Out-Null

$profilePath = Join-Path $ProjectRoot "tools\profiles\paper.profile.json"
if(!(Test-Path $profilePath)){ throw "MISSING_PROFILE=$profilePath" }
$j = Get-Content -Raw -Encoding UTF8 $profilePath | ConvertFrom-Json

function GetVal([string]$k){
  if($j.PSObject.Properties.Match($k).Count -gt 0){
    return @{v=$j.$k; src=("paper.profile.json:{0}" -f $k)}
  }
  if($j.PSObject.Properties.Match("env").Count -gt 0 -and $j.env){
    $ek=("TBOT_{0}" -f $k.ToUpper())
    if($j.env.PSObject.Properties.Match($ek).Count -gt 0){
      return @{v=$j.env.$ek; src=("paper.profile.json:env.{0}" -f $ek)}
    }
    if($j.env.PSObject.Properties.Match($k).Count -gt 0){
      return @{v=$j.env.$k; src=("paper.profile.json:env.{0}" -f $k)}
    }
  }
  return @{v=$null; src="(missing)"}
}

# whitelist only (no secrets)
$fieldsExec = @("sleep_sec","max_concurrent_orders","max_symbols_active","allow_out_of_session")
$fieldsGate = @("gate_cooldown_sec","gate_max_plans_per_day","gate_min_conf","gate_min_rr")
$fieldsRisk = @("risk_per_trade_usd","gate_max_risk_usd","gate_max_risk_per_day_usd","weekly_max_risk_usd")
$fieldsKill = @("kill_on_duplicate_orders","kill_on_stop_missing","kill_on_tp_missing","kill_on_price_synthetic","kill_on_config_invalid")
$fieldsQC   = @("rotate_shadow_plans_at_start","enforce_single_instance","qc_must_pass_before_start","eod_freeze_required")

# symbols
$symbols=@()
if($j.PSObject.Properties.Match("symbols").Count -gt 0 -and $j.symbols){
  try {
    if($j.symbols -is [string]){
      $symbols = @($j.symbols.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    } else {
      $symbols = @($j.symbols)
    }
  } catch { $symbols=@() }
}

# executor task args (safe)
$execArgs=$null
try{
  $t = Get-ScheduledTask -TaskName "ORG_BOT_PAPER_EXECUTOR" -ErrorAction Stop
  $a = ($t.Actions | Select-Object -First 1)
  $execArgs = [string]$a.Arguments
} catch { $execArgs=$null }

function ExtractArg([string]$args,[string]$name){
  if([string]::IsNullOrWhiteSpace($args)){ return $null }
  $m=[regex]::Match($args, "(?i)\-$([regex]::Escape($name))\s+([^\s]+)")
  if($m.Success){ return $m.Groups[1].Value } else { return $null }
}

$ex = @{
  MaxOrdersPerDay = ExtractArg $execArgs "MaxOrdersPerDay"
  MaxOrdersPerRun = ExtractArg $execArgs "MaxOrdersPerRun"
  DefaultQty      = ExtractArg $execArgs "DefaultQty"
  DryRun          = ExtractArg $execArgs "DryRun"
}

# snapshot object (json)
$snap = [ordered]@{
  isoday=$IsoDayOverride
  ymd=$ymd
  runroot=$RunRoot
  exec_limits=[ordered]@{}
  gate_quality=[ordered]@{}
  risk=[ordered]@{}
  kill_switches=[ordered]@{}
  qc_observability=[ordered]@{}
  executor_task=[ordered]@{
    name="ORG_BOT_PAPER_EXECUTOR"
    dryrun=$ex.DryRun
    max_orders_per_day=$ex.MaxOrdersPerDay
    max_orders_per_run=$ex.MaxOrdersPerRun
    default_qty=$ex.DefaultQty
  }
  symbols=$symbols
}

foreach($k in $fieldsExec){ $r=GetVal $k; $snap.exec_limits[$k]=@{value=$r.v; src=$r.src} }
foreach($k in $fieldsGate){ $r=GetVal $k; $snap.gate_quality[$k]=@{value=$r.v; src=$r.src} }
foreach($k in $fieldsRisk){ $r=GetVal $k; $snap.risk[$k]=@{value=$r.v; src=$r.src} }
foreach($k in $fieldsKill){ $r=GetVal $k; $snap.kill_switches[$k]=@{value=$r.v; src=$r.src} }
foreach($k in $fieldsQC){ $r=GetVal $k; $snap.qc_observability[$k]=@{value=$r.v; src=$r.src} }

# write BOTH analytics + ops (so backup always catches it)
$jsA = Join-Path $ana ("POLICY_SNAPSHOT_{0}.json" -f $ymd)
$jsO = Join-Path $ops ("POLICY_SNAPSHOT_{0}.json" -f $ymd)
($snap | ConvertTo-Json -Depth 25) | Set-Content -Encoding UTF8 -Path $jsA
Copy-Item $jsA $jsO -Force

$mdA = Join-Path $ana ("POLICY_SNAPSHOT_{0}.md" -f $ymd)
$mdO = Join-Path $ops ("POLICY_SNAPSHOT_{0}.md" -f $ymd)

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add(("# POLICY SNAPSHOT {0}" -f $IsoDayOverride)) | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- runroot: {0}" -f $RunRoot)) | Out-Null
$lines.Add("") | Out-Null

function AddSection([string]$title, $obj){
  $lines.Add(("## {0}" -f $title)) | Out-Null
  $lines.Add("") | Out-Null
  foreach($k in $obj.Keys){
    $v=$obj[$k].value
    $src=$obj[$k].src
    $lines.Add(("- {0} = {1} (src: {2})" -f $k,$v,$src)) | Out-Null
  }
  $lines.Add("") | Out-Null
}

AddSection "Execution limits" $snap.exec_limits
AddSection "Gate quality" $snap.gate_quality
AddSection "Risk" $snap.risk
AddSection "Kill switches" $snap.kill_switches
AddSection "QC & Observability" $snap.qc_observability

$lines.Add("## Executor task (safety)") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- DryRun: {0}" -f $snap.executor_task.dryrun)) | Out-Null
$lines.Add(("- MaxOrdersPerDay: {0}" -f $snap.executor_task.max_orders_per_day)) | Out-Null
$lines.Add(("- MaxOrdersPerRun: {0}" -f $snap.executor_task.max_orders_per_run)) | Out-Null
$lines.Add(("- DefaultQty: {0}" -f $snap.executor_task.default_qty)) | Out-Null
$lines.Add("") | Out-Null

$lines.Add("## Symbols") | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("- " + ($symbols -join ", "))) | Out-Null
$lines.Add("") | Out-Null
$lines.Add(("OK=POLICY_SNAPSHOT_WRITTEN ymd={0}" -f $ymd)) | Out-Null

$lines.ToArray() | Set-Content -Encoding UTF8 -Path $mdA
Copy-Item $mdA $mdO -Force

Write-Host ("OK=POLICY_SNAPSHOT_WRITTEN ymd={0} md={1}" -f $ymd,$mdA)
