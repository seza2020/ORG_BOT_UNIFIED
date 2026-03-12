param(
  [string]$Root = "C:\alpaca-bot\org_bot",
  [int]$MaxPerGroup = 20,
  [int]$MakeZip = 1
)

$ErrorActionPreference="SilentlyContinue"

function NowStamp { (Get-Date).ToString("yyyyMMdd_HHmmss") }

function SafeAdd([string]$Group,[string]$Label,[string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return $null }
  if($Path -match "\\secrets\\" -or $Path -match "alpaca_env\.ps1$"){ return $null } # never include secrets
  $exists = Test-Path -LiteralPath $Path
  $len = $null; $lw = $null
  if($exists){
    $it = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if($it){ $len=$it.Length; $lw=$it.LastWriteTime }
  }
  [pscustomobject]@{
    Group=$Group; Label=$Label; FullName=$Path; Exists=$exists; Length=$len; LastWriteTime=$lw
  }
}

function SortForReport($arr){
  $arr | Sort-Object -Property `
    @{Expression='Group';Descending=$false}, `
    @{Expression='Exists';Descending=$true}, `
    @{Expression='LastWriteTime';Descending=$true}
}

if(!(Test-Path -LiteralPath $Root)){ throw "Root not found: $Root" }

$stamp = NowStamp
$OpsDir = Join-Path $Root "logs\ops"
$OutDir = Join-Path $OpsDir ("UPLOAD_BUNDLE_{0}" -f $stamp)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$reportTxt = Join-Path $OutDir ("UPLOAD_FILE_LIST_{0}.txt" -f $stamp)
$reportCsv = Join-Path $OutDir ("UPLOAD_FILE_LIST_{0}.csv" -f $stamp)

$items = New-Object System.Collections.Generic.List[object]

# ---- Explicit Ops scripts (best-effort) ----
$explicit = @(
  (Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON_V2.ps1"),
  (Join-Path $Root "tools\RUN_LIVE_SHADOW_CANON.ps1"),
  (Join-Path $Root "tools\OPS_END_OF_DAY_V2.ps1"),
  (Join-Path $Root "tools\OPS_END_OF_DAY.ps1"),
  (Join-Path $Root "tools\recover_shadow_plans_from_meta.ps1"),
  (Join-Path $Root "tools\RECOVER_SHADOW_FROM_LIVE_OUT.ps1"),
  (Join-Path $Root "tools\freeze_today_enterprise_SAFE.ps1"),
  (Join-Path $Root "tools\freeze_today_enterprise.ps1"),
  (Join-Path $Root "tools\CLEAR_TBOT_LOCK.ps1"),
  (Join-Path $Root "tools\ops\TBOT_Freeze.ps1"),
  (Join-Path $Root "tools\ops\TBOT_Freeze_v2.ps1")
)

foreach($p in $explicit){
  $items.Add((SafeAdd "OPS_SCRIPTS" (Split-Path $p -Leaf) $p)) | Out-Null
}

# ---- Core logs (source of truth) ----
$items.Add((SafeAdd "CORE_LOGS" "meta.jsonl" (Join-Path $Root "logs\meta.jsonl"))) | Out-Null
$items.Add((SafeAdd "CORE_LOGS" "announce.log" (Join-Path $Root "logs\announce.log"))) | Out-Null
$items.Add((SafeAdd "CORE_LOGS" "shadow_plans.jsonl" (Join-Path $Root "logs\shadow_plans.jsonl"))) | Out-Null

# ---- Recent FREEZE zips ----
$freezeDir = Join-Path $Root "logs\freeze"
if(Test-Path $freezeDir){
  Get-ChildItem -Path $freezeDir -File -Filter "FREEZE_TODAY_*.zip" |
    Sort-Object LastWriteTime -Desc | Select-Object -First $MaxPerGroup |
    ForEach-Object { $items.Add((SafeAdd "LOGS_FREEZE" $_.Name $_.FullName)) | Out-Null }
}

# ---- Recent LIVE_OUT / LIVE_ERR / QC ----
$ops = Join-Path $Root "logs\ops"
if(Test-Path $ops){
  Get-ChildItem -Path $ops -File -Filter "LIVE_OUT_*.txt" |
    Sort-Object LastWriteTime -Desc | Select-Object -First $MaxPerGroup |
    ForEach-Object { $items.Add((SafeAdd "LOGS_LIVE_OUT" $_.Name $_.FullName)) | Out-Null }

  Get-ChildItem -Path $ops -File -Filter "LIVE_ERR_*.txt" |
    Sort-Object LastWriteTime -Desc | Select-Object -First $MaxPerGroup |
    ForEach-Object { $items.Add((SafeAdd "LOGS_LIVE_ERR" $_.Name $_.FullName)) | Out-Null }

  Get-ChildItem -Path $ops -File -Filter "QC_*.txt" |
    Sort-Object LastWriteTime -Desc | Select-Object -First $MaxPerGroup |
    ForEach-Object { $items.Add((SafeAdd "QA_QC" $_.Name $_.FullName)) | Out-Null }
}

# ---- FROM_META recovered files ----
$sd = Join-Path $Root "logs\shadow_daily"
if(Test-Path $sd){
  Get-ChildItem -Path $sd -File -Filter "shadow_plans_*_FROM_META.jsonl" |
    Sort-Object LastWriteTime -Desc | Select-Object -First $MaxPerGroup |
    ForEach-Object { $items.Add((SafeAdd "SHADOW_DAILY_FROM_META" $_.Name $_.FullName)) | Out-Null }
}

# ---- Scheduled Tasks export (TBOT-related only) ----
$taskExport = Join-Path $OutDir ("OPS__SCHEDULED_TASKS__EXPORT__{0}.txt" -f $stamp)
try{
  $tn = @("TBOT_RUN_SHADOW_DAILY_0630","TBOT_END_OF_DAY_1305","TBOT_RUN_SHADOW_UI_0630","P200K_SHADOW_PIPELINE_0630")
  $lines = New-Object System.Collections.Generic.List[string]
  foreach($name in $tn){
    $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if(!$t){ $lines.Add(("TASK_NOT_FOUND: {0}" -f $name)) | Out-Null; continue }
    $lines.Add(("=== TASK: {0} ===" -f $name)) | Out-Null
    $lines.Add(("State: {0}" -f $t.State)) | Out-Null
    $lines.Add("Actions:") | Out-Null
    foreach($a in $t.Actions){
      $lines.Add(("  Execute: {0}" -f $a.Execute)) | Out-Null
      $lines.Add(("  Args:    {0}" -f $a.Arguments)) | Out-Null
    }
    $lines.Add("Triggers:") | Out-Null
    foreach($tr in $t.Triggers){
      $lines.Add(("  StartBoundary: {0}" -f $tr.StartBoundary)) | Out-Null
      $lines.Add(("  Enabled: {0}" -f $tr.Enabled)) | Out-Null
      if($tr.PSObject.Properties.Name -contains "DaysOfWeek"){ $lines.Add(("  DaysOfWeek: {0}" -f $tr.DaysOfWeek)) | Out-Null }
    }
    $lines.Add("") | Out-Null
  }
  $lines | Set-Content -Encoding UTF8 -Path $taskExport
  $items.Add((SafeAdd "OPS_TASKS" (Split-Path $taskExport -Leaf) $taskExport)) | Out-Null
}catch{}

# ---- finalize ----
$final = $items | Where-Object { $_ -ne $null }
$finalSorted = SortForReport $final

$finalSorted | Format-Table Group,Exists,Label,FullName,Length,LastWriteTime -Auto

$finalSorted | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $reportCsv
$finalSorted | ForEach-Object {
  "{0}`t{1}`t{2}`t{3}`t{4}" -f $_.Group,$_.Exists,$_.FullName,$_.Length,$_.LastWriteTime
} | Set-Content -Encoding UTF8 -Path $reportTxt

""
"REPORT_TXT=$reportTxt"
"REPORT_CSV=$reportCsv"

if($MakeZip -eq 1){
  $copyList = $finalSorted | Where-Object { $_.Exists } | Select-Object -ExpandProperty FullName -Unique
  foreach($p in $copyList){
    try{
      $name = Split-Path $p -Leaf
      Copy-Item -LiteralPath $p -Destination (Join-Path $OutDir $name) -Force
    }catch{}
  }
  $zip = Join-Path $OpsDir ("UPLOAD_BUNDLE_{0}.zip" -f $stamp)
  if(Test-Path $zip){ Remove-Item $zip -Force }
  Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $zip -Force
  "ZIP_READY=$zip"
  "FOLDER_READY=$OutDir"
}
