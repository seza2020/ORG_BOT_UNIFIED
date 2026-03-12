param(
    [string]$Root   = "C:\alpaca-bot\org_bot",
    [string]$RunRoot= "C:\alpaca-bot\org_bot_runtime\paper",
    [int]$WarmupSec = 8,
    [int]$Force     = 1
)

$ErrorActionPreference="Stop"

function AgeSec($p){
    if(!(Test-Path $p)){ return $null }
    [int](([DateTime]::UtcNow-(Get-Item $p).LastWriteTimeUtc).TotalSeconds)
}

$runner="$Root\tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$state="$RunRoot\state"
$lock="$state\locks\RUN_PAPER_PROFILE.lock"
$pidf="$state\pid.txt"
$hb="$state\heartbeat.json"
$touch="$state\hb_touch.txt"
$err="$state\heartbeat_err.txt"
$meta="$RunRoot\logs\meta.jsonl"

"=== CLEAN START ==="
"ROOT=$Root"
"RUNROOT=$RunRoot"

# Kill old paper bots
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
 Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\\paper*" } |
 ForEach-Object { "KILL PID=$($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# Clear state
Remove-Item -Force -ErrorAction SilentlyContinue $lock,$pidf,$hb,$touch,$err

"STATE CLEARED"

# Start runner
& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $runner -Force $Force

"RUNNER_EXIT=$LASTEXITCODE"

Start-Sleep -Seconds $WarmupSec

# Find bot
$bot=$null
for($i=1;$i -le 20;$i++){
    $bot=Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
        Where-Object { $_.CommandLine -like "*-m tbot.main*" -and $_.CommandLine -like "*org_bot_runtime\\paper*" } |
        Select-Object -First 1
    if($bot){break}
    Start-Sleep 1
}

if($bot){
    New-Item -ItemType Directory -Force -Path $state | Out-Null
    Set-Content -LiteralPath $pidf -Value $bot.ProcessId
    "PID_WRITTEN=$($bot.ProcessId)"
}else{
    "WARN: BOT NOT DETECTED"
}

"META_AGE=" + (AgeSec $meta ?? -1)
"HB_AGE="   + (AgeSec $hb ?? -1)

if(Test-Path $err){
  "--- heartbeat_err.txt ---"
  Get-Content $err -Tail 50
}

if(Test-Path $hb){
  "--- heartbeat.json ---"
  Get-Content $hb -Tail 5
}

"=== CLEAN END ==="
