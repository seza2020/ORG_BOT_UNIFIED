param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$InnerScript=""
)
$ErrorActionPreference="Stop"

$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"

$out = Join-Path $ops ("WATCHDOG_WRAP_OUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("WATCHDOG_WRAP_ERR_{0}.txt" -f $ts)

$hb = Join-Path $RunRoot "state\heartbeat.json"
$pidf = Join-Path $RunRoot "state\pid.txt"
$hbAge = -1
if(Test-Path $hb){ $hbAge = [int](([DateTime]::UtcNow - (Get-Item $hb).LastWriteTimeUtc).TotalSeconds) }

"ts=$ts" | Set-Content -Encoding UTF8 $out
"RUNROOT=$RunRoot" | Add-Content -Encoding UTF8 $out
"HEARTBEAT_PRESENT=$([bool](Test-Path $hb)) age_sec=$hbAge" | Add-Content -Encoding UTF8 $out
"PID_PRESENT=$([bool](Test-Path $pidf))" | Add-Content -Encoding UTF8 $out
"INNER=$InnerScript" | Add-Content -Encoding UTF8 $out

# run inner in a separate pwsh so its exit won't kill wrapper
$pwsh = "C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwsh)){ $pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwsh)){ $pwsh = (Get-Command powershell.exe).Source }

$innerExit = 0
try {
  if(!(Test-Path $InnerScript)){ throw "MISSING_INNER=$InnerScript" }
  & $pwsh -NoProfile -ExecutionPolicy Bypass -File $InnerScript -ProjectRoot $ProjectRoot -RunRoot $RunRoot 1>> $out 2>> $err
  $innerExit = $LASTEXITCODE
} catch {
  $innerExit = 99
  ("WRAP_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 $err
}

"INNER_EXIT_CODE=$innerExit" | Add-Content -Encoding UTF8 $out
"WRAP_EXIT_CODE=0 (always)" | Add-Content -Encoding UTF8 $out

exit 0
