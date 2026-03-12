$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U     = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS   = Join-Path $U "ops"
$EVID  = Join-Path $OPS "evidence"
$LOGS  = Join-Path $U "runtime\paper\logs"
$TASK  = "\ORG_UNIFIED_PAPER_CANONICAL_V1"

function Get-TbotProcs {
  try {
    return @(
      Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId, ParentProcessId, Name, CommandLine, CreationDate
    )
  } catch {
    return @()
  }
}

function Export-Tail {
  param([string]$Source,[string]$Dest,[int]$Last=250)
  if (Test-Path -LiteralPath $Source) {
    Get-Content -LiteralPath $Source -Tail $Last -Encoding UTF8 |
      Set-Content -LiteralPath $Dest -Encoding UTF8
  } else {
    "MISSING=$Source" | Set-Content -LiteralPath $Dest -Encoding UTF8
  }
}

Get-TbotProcs | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT  = Join-Path $EVID ("RUN_LOOP_CHILD_SPAWN_FORENSIC_V1_FIX_CERTIFY_" + $TS)
$AUD  = Join-Path $OUT "audit"
$TAIL = Join-Path $OUT "tails"
$SUM  = Join-Path $OUT "summary"

New-Item -ItemType Directory -Force -Path $OUT,$AUD,$TAIL,$SUM | Out-Null

schtasks /run /tn $TASK 1> (Join-Path $AUD "schtasks_run_stdout.txt") 2> (Join-Path $AUD "schtasks_run_stderr.txt")

Start-Sleep -Seconds 12
$p12 = @(Get-TbotProcs)
$c12 = $p12.Count
$p12 | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "tbot_after_12s.csv")

Start-Sleep -Seconds 8
$p20 = @(Get-TbotProcs)
$c20 = $p20.Count
$p20 | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "tbot_after_20s.csv")

foreach ($f in @(
  (Join-Path $LOGS "runloop_spawn_trace.log"),
  (Join-Path $LOGS "meta_events.jsonl"),
  (Join-Path $LOGS "meta_engine.jsonl"),
  (Join-Path $LOGS "org_unified_runtime_manager_v1.log"),
  (Join-Path $LOGS "canonical_task_xml_launcher_v1.jsonl")
)) {
  $leaf = Split-Path $f -Leaf
  Export-Tail -Source $f -Dest (Join-Path $TAIL ($leaf + ".tail.txt")) -Last 250
}

Get-TbotProcs | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}

@(
  "RUN_LOOP_CHILD_SPAWN_FORENSIC_V1_FIX_CERTIFY_DONE"
  ("OUT=" + $OUT)
  ("COUNT_AFTER_12S=" + $c12)
  ("COUNT_AFTER_20S=" + $c20)
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

$zip = $OUT + ".zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"RUN_LOOP_CHILD_SPAWN_FORENSIC_V1_FIX_CERTIFY_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("COUNT_AFTER_12S=" + $c12)
("COUNT_AFTER_20S=" + $c20)
