$ErrorActionPreference = "Stop"

$U        = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS      = Join-Path $U "ops"
$WRAP     = Join-Path $OPS "task_wrappers"
$PATCHES  = Join-Path $OPS "patches"
$EVID     = Join-Path $OPS "evidence"
$CODE     = Join-Path $U "code"
$PWSH     = "C:\Program Files\PowerShell\7\pwsh.exe"
$WRAPPER  = Join-Path $WRAP "ORG_UNIFIED_PAPER_RUN.ps1"

if (!(Test-Path $PWSH))    { throw "PWSH_NOT_FOUND=$PWSH" }
if (!(Test-Path $WRAPPER)) { throw "WRAPPER_NOT_FOUND=$WRAPPER" }

$TS   = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT  = Join-Path $EVID ("ROOT_FIX_CERTIFY_20CYCLE_V1_" + $TS)
$AUD  = Join-Path $OUT "audit"
$SUM  = Join-Path $OUT "summary"
New-Item -ItemType Directory -Force $OUT, $AUD, $SUM | Out-Null

function Get-TbotProcesses {
  try {
    return Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
      Where-Object { $_.CommandLine -match "tbot\.main" } |
      Select-Object ProcessId, ParentProcessId, Name, CommandLine
  } catch {
    return @()
  }
}

$results = New-Object System.Collections.Generic.List[object]
$maxOverall = 0

1..20 | ForEach-Object {
  $cycle = $_

  $proc = Start-Process -FilePath $PWSH `
    -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$WRAPPER) `
    -WorkingDirectory $CODE `
    -PassThru `
    -WindowStyle Hidden

  Start-Sleep -Seconds 8

  $maxCycle = 0
  1..25 | ForEach-Object {
    $p = @(Get-TbotProcesses)
    $count = $p.Count
    $maxCycle = [Math]::Max($maxCycle, $count)
    $maxOverall = [Math]::Max($maxOverall, $count)
    $p | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD ("cycle_{0:D2}_tick_{1:D2}.csv" -f $cycle, $_))
    Start-Sleep -Seconds 2
  }

  $results.Add([pscustomobject]@{
    Cycle = $cycle
    WrapperPid = $proc.Id
    MaxTbotCountObserved = $maxCycle
    Pass = ($maxCycle -eq 1)
  }) | Out-Null

  try {
    Get-TbotProcesses | ForEach-Object {
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
  } catch {}

  try {
    if (-not $proc.HasExited) {
      Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
  } catch {}

  Start-Sleep -Seconds 2
}

$results | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD "cycle_results.csv")

$failed = @($results | Where-Object { -not $_.Pass }).Count
$passed = @($results | Where-Object { $_.Pass }).Count
$overall = if ($failed -eq 0 -and $maxOverall -eq 1) { "PASS" } else { "FAIL" }

@(
  "ROOT_FIX_CERTIFY_20CYCLE_V1"
  ("MAX_TBOT_COUNT_OBSERVED=" + $maxOverall)
  ("CYCLES_PASSED=" + $passed)
  ("CYCLES_FAILED=" + $failed)
  ("OVERALL=" + $overall)
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

$zip = $OUT + ".zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"ROOT_FIX_CERTIFY_20CYCLE_V1_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("MAX_TBOT_COUNT_OBSERVED=" + $maxOverall)
("CYCLES_PASSED=" + $passed)
("CYCLES_FAILED=" + $failed)
("OVERALL=" + $overall)

