$ErrorActionPreference = "Stop"

$U       = "C:\alpaca-bot\ORG_BOT_UNIFIED"
$OPS     = Join-Path $U "ops"
$WRAP    = Join-Path $OPS "task_wrappers"
$EVID    = Join-Path $OPS "evidence"
$CODE    = Join-Path $U "code"
$PWSH    = "C:\Program Files\PowerShell\7\pwsh.exe"
$WRAPPER = Join-Path $WRAP "ORG_UNIFIED_PAPER_RUN.ps1"

$TS  = Get-Date -Format "yyyyMMdd_HHmmss"
$OUT = Join-Path $EVID ("ROOT_FIX_CERTIFY_10MIN_V1_" + $TS)
$AUD = Join-Path $OUT "audit"
$SUM = Join-Path $OUT "summary"
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

$proc = Start-Process -FilePath $PWSH `
  -ArgumentList @("-NoProfile","-ExecutionPolicy","Bypass","-File",$WRAPPER) `
  -WorkingDirectory $CODE `
  -PassThru `
  -WindowStyle Hidden

Start-Sleep -Seconds 10

$maxObserved = 0
1..120 | ForEach-Object {
  $p = @(Get-TbotProcesses)
  $count = $p.Count
  $maxObserved = [Math]::Max($maxObserved, $count)
  $p | Export-Csv -NoTypeInformation -Encoding UTF8 -Path (Join-Path $AUD ("tick_{0:D3}.csv" -f $_))
  Start-Sleep -Seconds 5
}

$overall = if ($maxObserved -le 1) { "PASS" } else { "FAIL" }

@(
  "ROOT_FIX_CERTIFY_10MIN_V1"
  ("WRAPPER_PID=" + $proc.Id)
  ("MAX_TBOT_COUNT_OBSERVED=" + $maxObserved)
  ("OVERALL=" + $overall)
) | Set-Content -LiteralPath (Join-Path $SUM "SUMMARY.txt") -Encoding UTF8

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

$zip = $OUT + ".zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $OUT "*") -DestinationPath $zip -CompressionLevel Optimal -Force

"ROOT_FIX_CERTIFY_10MIN_V1_DONE"
("OUT=" + $OUT)
("ZIP=" + $zip)
("MAX_TBOT_COUNT_OBSERVED=" + $maxObserved)
("OVERALL=" + $overall)
