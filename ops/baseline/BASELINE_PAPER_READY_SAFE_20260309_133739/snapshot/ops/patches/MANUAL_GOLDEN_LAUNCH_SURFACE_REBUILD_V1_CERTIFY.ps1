$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$EVID    = Join-Path $OPS "evidence"
$WRAPDIR = Join-Path $OPS "task_wrappers"
$CODE    = Join-Path $U "code"
$LOGS    = Join-Path $U "runtime\paper\logs"
$PWSH    = "C:\Program Files\PowerShell\7\pwsh.exe"
$WRAPPER = Join-Path $WRAPDIR "ORG_UNIFIED_PAPER_RUN.ps1"

function Get-LineCount {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return -3 }
  if (!(Test-Path -LiteralPath $Path)) { return -1 }
  try { return (Get-Content -LiteralPath $Path -Encoding UTF8 | Measure-Object -Line).Lines }
  catch { return -2 }
}

function Get-TbotProcesses {
  try {
    return @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId, ParentProcessId, Name, CommandLine)
  } catch {
    return @()
  }
}

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2

$TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT  = Join-Path $EVID ("MANUAL_GOLDEN_LAUNCH_SURFACE_REBUILD_V1_CERTIFY_" + $TS)
$AUD  = Join-Path $OUT "audit"
$SUM  = Join-Path $OUT "summary"
New-Item -ItemType Directory -Force -Path $OUT, $AUD, $SUM | Out-Null

$metaEvents = Join-Path $LOGS "meta_events.jsonl"
$metaEngine = Join-Path $LOGS "meta_engine.jsonl"

$beforeMetaEvents = Get-LineCount -Path $metaEvents
$beforeMetaEngine = Get-LineCount -Path $metaEngine

$stdout = Join-Path $AUD "wrapper_stdout.txt"
$stderr = Join-Path $AUD "wrapper_stderr.txt"

$proc = Start-Process -FilePath $PWSH `
  -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$WRAPPER) `
  -WorkingDirectory $CODE `
  -RedirectStandardOutput $stdout `
  -RedirectStandardError $stderr `
  -PassThru

Start-Sleep -Seconds 12
$count12 = @(Get-TbotProcesses).Count
Start-Sleep -Seconds 8
$count20 = @(Get-TbotProcesses).Count

$wrapperAlive20 = $false
try {
  $probe = Get-Process -Id $proc.Id -ErrorAction Stop
  if ($probe) { $wrapperAlive20 = $true }
} catch {}

$wrapperExitCode = $null
try { $wrapperExitCode = $proc.ExitCode } catch {}

$afterMetaEvents = Get-LineCount -Path $metaEvents
$afterMetaEngine = Get-LineCount -Path $metaEngine

$metaEventsGrowth = $afterMetaEvents - $beforeMetaEvents
$metaEngineGrowth = $afterMetaEngine - $beforeMetaEngine

Get-TbotProcesses | ForEach-Object {
  Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
}
try {
  if ($wrapperAlive20) {
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
  }
} catch {}

@(
  "MANUAL_GOLDEN_LAUNCH_SURFACE_REBUILD_V1_CERTIFY_DONE"
  ("OUT=" + $OUT)
  ("COUNT_AFTER_12S=" + $count12)
  ("COUNT_AFTER_20S=" + $count20)
  ("WRAPPER_ALIVE_AFTER_20S=" + $wrapperAlive20)
  ("WRAPPER_EXIT_CODE=" + $wrapperExitCode)
  ("META_EVENTS_GROWTH=" + $metaEventsGrowth)
  ("META_ENGINE_GROWTH=" + $metaEngineGrowth)
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

$zip = $OUT + ".zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"MANUAL_GOLDEN_LAUNCH_SURFACE_REBUILD_V1_CERTIFY_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("COUNT_AFTER_12S=" + $count12)
("COUNT_AFTER_20S=" + $count20)
("WRAPPER_ALIVE_AFTER_20S=" + $wrapperAlive20)
("WRAPPER_EXIT_CODE=" + $wrapperExitCode)
("META_EVENTS_GROWTH=" + $metaEventsGrowth)
("META_ENGINE_GROWTH=" + $metaEngineGrowth)
