param(
  [string]$UnifiedRoot = "C:\alpaca-bot\ORG_BOT_UNIFIED",
  [int]$RefreshSec = 10,
  [int]$Loops = 0
)

$ErrorActionPreference = "Stop"

$Runtime = Join-Path $UnifiedRoot "runtime\paper"
$Logs    = Join-Path $Runtime "logs"
$State   = Join-Path $Runtime "state"
$Evid    = Join-Path $UnifiedRoot "ops\evidence"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$OutDir = Join-Path $Evid ("MISSION_CONTROL_V1_" + $ts)
New-Item -ItemType Directory -Force $OutDir | Out-Null

$Audit = Join-Path $OutDir "mission_control_audit.txt"

function Write-Audit([string]$msg){
  $msg | Out-File -LiteralPath $Audit -Append -Encoding utf8
}

function Get-TailSafe([string]$Path,[int]$N=5){
  if(Test-Path $Path){
    try { return (Get-Content -LiteralPath $Path -Tail $N -ErrorAction Stop) }
    catch { return @("READ_ERROR: $($_.Exception.Message)") }
  }
  return @("MISSING")
}

function Get-FileAgeSec([string]$Path){
  if(!(Test-Path $Path)){ return $null }
  return [int]((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds
}

function Get-LastJsonKind([string]$Path){
  if(!(Test-Path $Path)){ return "MISSING" }
  try {
    $line = Get-Content -LiteralPath $Path -Tail 1 -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($line)){ return "EMPTY" }
    $obj = $line | ConvertFrom-Json
    if($obj.kind){ return [string]$obj.kind }
    return "NO_KIND"
  } catch {
    return "PARSE_ERROR"
  }
}

function Has-StderrIssue([string]$Path){
  if(!(Test-Path $Path)){ return $false }
  try {
    $tail = Get-Content -LiteralPath $Path -Tail 50 -ErrorAction Stop
    $txt = ($tail -join "`n")
    return ($txt -match "Traceback|ERROR|Exception|CRITICAL")
  } catch {
    return $true
  }
}

function Get-LatestShadowPlan([string]$Path){
  if(!(Test-Path $Path)){ return "MISSING" }
  try {
    $line = Get-Content -LiteralPath $Path -Tail 1 -ErrorAction Stop
    if([string]::IsNullOrWhiteSpace($line)){ return "EMPTY" }
    return $line
  } catch {
    return "READ_ERROR"
  }
}

$iter = 0
while($true){
  $iter++

  $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.CommandLine -match "tbot\.main" } |
    Select-Object ProcessId,ParentProcessId,CommandLine

  $pidCount = @($procs).Count
  $pids = if($pidCount -gt 0){ (@($procs) | Select-Object -ExpandProperty ProcessId) -join "," } else { "" }

  $runtimeHealth = Join-Path $Logs "runtime_health.log"
  $metaEvents    = Join-Path $Logs "meta_events.jsonl"
  $stdoutLog     = Join-Path $Logs "bot_stdout.log"
  $stderrLog     = Join-Path $Logs "bot_stderr.log"
  $shadowPlans   = Join-Path $Logs "shadow_plans.jsonl"
  $pidFile       = Join-Path $State "tbot.pid"

  $ageHealth = Get-FileAgeSec $runtimeHealth
  $ageMeta   = Get-FileAgeSec $metaEvents
  $ageOut    = Get-FileAgeSec $stdoutLog
  $ageErr    = Get-FileAgeSec $stderrLog

  $lastKind = Get-LastJsonKind $metaEvents
  $stderrIssue = Has-StderrIssue $stderrLog
  $latestPlan = Get-LatestShadowPlan $shadowPlans

  $status = "GREEN"
  $notes = New-Object System.Collections.Generic.List[string]

  if($pidCount -ne 1){
    $status = "RED"
    $notes.Add("PID_COUNT=$pidCount")
  }

  if($stderrIssue){
    if($status -ne "RED"){ $status = "RED" }
    $notes.Add("STDERR_ALERT")
  }

  foreach($pair in @(
    @{Name="runtime_health"; Age=$ageHealth},
    @{Name="meta_events"; Age=$ageMeta}
  )){
    if($null -eq $pair.Age){
      if($status -eq "GREEN"){ $status = "YELLOW" }
      $notes.Add("$($pair.Name)_MISSING")
    } elseif($pair.Age -gt 120){
      if($status -eq "GREEN"){ $status = "YELLOW" }
      $notes.Add("$($pair.Name)_STALE=$($pair.Age)s")
    }
  }

  Clear-Host
  $header = "MISSION CONTROL V1 | {0} | STATUS={1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $status
  Write-Host $header
  Write-Host ("PID_COUNT     : {0}" -f $pidCount)
  Write-Host ("PIDS          : {0}" -f $pids)
  Write-Host ("PID_FILE      : {0}" -f (Test-Path $pidFile))
  Write-Host ("LAST_EVENT    : {0}" -f $lastKind)
  Write-Host ("AGE_HEALTH    : {0}" -f ($(if($null -eq $ageHealth){"MISSING"}else{"$ageHealth sec"})))
  Write-Host ("AGE_META      : {0}" -f ($(if($null -eq $ageMeta){"MISSING"}else{"$ageMeta sec"})))
  Write-Host ("AGE_STDOUT    : {0}" -f ($(if($null -eq $ageOut){"MISSING"}else{"$ageOut sec"})))
  Write-Host ("AGE_STDERR    : {0}" -f ($(if($null -eq $ageErr){"MISSING"}else{"$ageErr sec"})))
  Write-Host ("STDERR_ALERT  : {0}" -f $stderrIssue)
  Write-Host ("NOTES         : {0}" -f ($(if($notes.Count -eq 0){"OK"}else{($notes -join "; ")})))

  Write-Host ""
  Write-Host "---- META_EVENTS TAIL ----"
  Get-TailSafe $metaEvents 5 | ForEach-Object { Write-Host $_ }

  Write-Host ""
  Write-Host "---- STDERR TAIL ----"
  Get-TailSafe $stderrLog 5 | ForEach-Object { Write-Host $_ }

  Write-Host ""
  Write-Host "---- SHADOW PLAN LAST ----"
  Write-Host $latestPlan

  $auditRow = "{0} | STATUS={1} | PID_COUNT={2} | PIDS={3} | LAST_EVENT={4} | STDERR_ALERT={5} | NOTES={6}" -f `
    (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $status, $pidCount, $pids, $lastKind, $stderrIssue, ($(if($notes.Count -eq 0){"OK"}else{($notes -join "; ")}))
  Write-Audit $auditRow

  if($Loops -gt 0 -and $iter -ge $Loops){
    break
  }

  Start-Sleep -Seconds $RefreshSec
}
