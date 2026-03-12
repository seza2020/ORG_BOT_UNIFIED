$ErrorActionPreference="Stop"

function WL($s){ Write-Host $s }

$BASE="C:\alpaca-bot"
$UNIFIED="C:\alpaca-bot\ORG_BOT_UNIFIED"
$LEGACY1="C:\alpaca-bot\org_bot_runtime"
$LEGACY2="C:\alpaca-bot\org_bot"

$stamp=Get-Date -Format "yyyyMMdd_HHmmss"
$ADIR=Join-Path $UNIFIED ("ops\audit\LOCKDOWN_LEGACY_RUNTIME_" + $stamp)
New-Item -ItemType Directory -Force $ADIR | Out-Null

WL ("AUDIT_DIR=" + $ADIR)

# 1) Kill suspicious python/pwsh processes referencing legacy paths
try {
  $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe' or Name='pwsh.exe' or Name='powershell.exe'"
  $hits = @()
  foreach($p in $procs){
    $cl = [string]$p.CommandLine
    if($cl -match "org_bot_runtime" -or $cl -match "\\org_bot\\" -or $cl -match "ORG_BOT_PAPER" -or $cl -match "RUN_PAPER" ){
      $hits += [pscustomobject]@{ pid=$p.ProcessId; name=$p.Name; cmd=$cl }
    }
  }
  $hits | Export-Csv (Join-Path $ADIR "proc_hits.csv") -NoTypeInformation
  ($hits | Select-Object -First 200 | Format-Table -AutoSize | Out-String) | Set-Content (Join-Path $ADIR "proc_hits_head.txt") -Encoding utf8

  foreach($h in $hits){
    try { Stop-Process -Id $h.pid -Force -ErrorAction SilentlyContinue } catch {}
  }
  WL ("KILLED_COUNT=" + $hits.Count)
} catch {
  WL ("WARN: PROC_SCAN_ERR=" + $_.Exception.Message)
}

# 2) Disable scheduled tasks that contain legacy paths (best-effort)
try {
  $tasks = Get-ScheduledTask -ErrorAction Stop
  $tHits=@()
  foreach($t in $tasks){
    try {
      $xml = Export-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath 2>$null
      if($xml -match "org_bot_runtime" -or $xml -match "\\org_bot\\"){
        $tHits += [pscustomobject]@{ task=($t.TaskPath + $t.TaskName) }
        try { Disable-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath -ErrorAction SilentlyContinue | Out-Null } catch {}
      }
    } catch {}
  }
  $tHits | Export-Csv (Join-Path $ADIR "task_hits.csv") -NoTypeInformation
  ($tHits | Format-Table -AutoSize | Out-String) | Set-Content (Join-Path $ADIR "task_hits.txt") -Encoding utf8
  WL ("TASK_DISABLE_COUNT=" + $tHits.Count)
} catch {
  WL ("WARN: TASK_SCAN_ERR=" + $_.Exception.Message)
  WL "NOTE: If tasks run as SYSTEM or you lack admin rights, task disable may fail."
}

# 3) Guard scan: find newest OUT/ERR in legacy vs unified
function NewestUnder($path,[string]$pattern){
  try {
    if(!(Test-Path -LiteralPath $path)){ return $null }
    return Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match $pattern } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 5 FullName,LastWriteTime,Length
  } catch { return $null }
}

$legacyLogs = NewestUnder $LEGACY1 "paper\\logs\\ops\\PAPER_.*_(OUT|ERR)_"
$unifiedLogs = NewestUnder (Join-Path $UNIFIED "runtime\paper\logs\ops") "PAPER_.*_(OUT|ERR)_"

($legacyLogs | Format-Table -AutoSize | Out-String) | Set-Content (Join-Path $ADIR "legacy_logs_head.txt") -Encoding utf8
($unifiedLogs | Format-Table -AutoSize | Out-String) | Set-Content (Join-Path $ADIR "unified_logs_head.txt") -Encoding utf8

WL "LOCKDOWN_DONE=OK"
WL "NEXT=Run your Paper live script when market is open; then verify ALL logs land under ORG_BOT_UNIFIED\\runtime\\paper\\logs\\ops"
