param(
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [string]$MetaPath = "",
  [int]$WindowSec = 300,
  [double]$MaxP95LatencySec = 1.0,
  [double]$MaxErrorRate = 0.20,
  [double]$MaxDenyRate = 0.90,
  [int]$MinSamples = 20
)

$ErrorActionPreference="Stop"

if(!$MetaPath){
  $MetaPath = Join-Path $RunRoot "logs\meta_paper.jsonl"
}

$StateDir = Join-Path $RunRoot "state"
New-Item -ItemType Directory -Force $StateDir | Out-Null

$DisableFlag = Join-Path $StateDir "LLM_GATE_DISABLED.flag"
$OpsDir = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force $OpsDir | Out-Null
$Out = Join-Path $OpsDir "llm_gate_watchdog.jsonl"

function Write-Event($obj){
  ($obj | ConvertTo-Json -Compress) | Add-Content -Encoding utf8 $Out
}

function P95($arr){
  if(!$arr -or $arr.Count -eq 0){ return $null }
  $s = $arr | Sort-Object
  $idx = [int][Math]::Floor(0.95*($s.Count-1))
  return [double]$s[$idx]
}

# Read loop
$buf = @()
$lastTs = Get-Date

while($true){
  if(!(Test-Path $MetaPath)){
    Write-Event @{ts=(Get-Date).ToString("o"); kind="llm_wd"; level="WARN"; msg="meta_missing"; meta=$MetaPath}
    Start-Sleep -Seconds 5
    continue
  }

  # tail last ~500 lines each cycle (simple, robust)
  $lines = Get-Content -LiteralPath $MetaPath -Tail 500 -ErrorAction SilentlyContinue
  $now = Get-Date

  $lat = New-Object System.Collections.Generic.List[double]
  $okC=0; $errC=0; $denyC=0; $tot=0

  foreach($ln in $lines){
    if([string]::IsNullOrWhiteSpace($ln)){ continue }
    if($ln -notmatch '"kind"\s*:\s*"llm_gate"'){ continue }

    $tot++
    try{
      $o = $ln | ConvertFrom-Json
      if($o.ok -eq $true){
        $okC++
      } else {
        $denyC++
      }
      if($null -ne $o.latency){
        $lat.Add([double]$o.latency)
      }
      if($o.reason -match '^llm_error' -or $o.reason -eq 'llm_timeout'){
        $errC++
      }
    } catch {
      $errC++
    }
  }

  if($tot -ge $MinSamples){
    $p95 = P95($lat)
    $errRate = if($tot -gt 0){ $errC / $tot } else { 0 }
    $denyRate = if($tot -gt 0){ $denyC / $tot } else { 0 }

    $trip = $false
    if($p95 -ne $null -and $p95 -gt $MaxP95LatencySec){ $trip = $true }
    if($errRate -gt $MaxErrorRate){ $trip = $true }
    if($denyRate -gt $MaxDenyRate){ $trip = $true }

    Write-Event @{
      ts=(Get-Date).ToString("o")
      kind="llm_wd"
      tot=$tot
      ok=$okC
      deny=$denyC
      err=$errC
      p95_latency=$p95
      err_rate=$errRate
      deny_rate=$denyRate
      disable_flag=(Test-Path $DisableFlag)
      trip=$trip
    }

    if($trip -and !(Test-Path $DisableFlag)){
      "DISABLED $(Get-Date -Format o)" | Set-Content -Encoding utf8 $DisableFlag
      Write-Event @{ts=(Get-Date).ToString("o"); kind="llm_wd"; level="ALERT"; msg="LLM_GATE_DISABLED"; flag=$DisableFlag}
    }
  }

  Start-Sleep -Seconds 10
}
