param(
  [string]\C:\alpaca-bot\org_bot   = "C:\alpaca-bot\org_bot",
  [string]\C:\alpaca-bot\org_bot_runtime\paper= "C:\alpaca-bot\org_bot_runtime\paper",
  [int]\ = 8,
  [int]\     = 1
)
\Stop="Stop"

function AgeSec([string]\){
  if(!(Test-Path -LiteralPath \)){ return \ }
  return [int](([DateTime]::UtcNow-(Get-Item -LiteralPath \).LastWriteTimeUtc).TotalSeconds)
}

\C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1 = Join-Path \C:\alpaca-bot\org_bot "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
if(!(Test-Path -LiteralPath \C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1)){ throw "MISSING_RUNNER=\C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1" }

\ = Join-Path \C:\alpaca-bot\org_bot_runtime\paper "state"
\  = Join-Path \ "locks\RUN_PAPER_PROFILE.lock"
\  = Join-Path \ "pid.txt"
\    = Join-Path \ "heartbeat.json"
\ = Join-Path \ "hb_touch.txt"
\   = Join-Path \ "heartbeat_err.txt"
\  = Join-Path \C:\alpaca-bot\org_bot_runtime\paper "logs\meta.jsonl"

"=== CLEAN_START BEGIN ==="
"ROOT=\C:\alpaca-bot\org_bot"
"RUNROOT=\C:\alpaca-bot\org_bot_runtime\paper"
"RUNNER=\C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1"

Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { \.CommandLine -like "*-m tbot.main*" -and \.CommandLine -like "*org_bot_runtime\\paper*" } |
  ForEach-Object { "KILL PID=" + \.ProcessId; Stop-Process -Id \.ProcessId -Force -ErrorAction SilentlyContinue }

Remove-Item -Force -ErrorAction SilentlyContinue \,\,\,\,\ | Out-Null
"STATE_CLEARED lock/pid/hb/touch/err"

& "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File \C:\alpaca-bot\org_bot\tools\RUN_PAPER_SHADOW_CANON_V1.ps1 -Force \
"RUNNER_EXITCODE=\"

Start-Sleep -Seconds \

\ = \
for(\=1;\ -le 20;\++){
  \ = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { \.CommandLine -like "*-m tbot.main*" -and \.CommandLine -like "*org_bot_runtime\\paper*" } |
    Select-Object -First 1
  if(\){ break }
  Start-Sleep -Seconds 1
}
if(\){
  \ = [int]\.ProcessId
  New-Item -ItemType Directory -Force -Path \ | Out-Null
  Set-Content -Encoding ASCII -LiteralPath \ -Value \
  "PID_WRITTEN=\ => \"
}else{
  "WARN: BOT_NOT_FOUND via WMI (pid not written)"
}

\ = AgeSec \
\   = AgeSec \
"POST_WARMUP META_AGE_SEC=" + (\ ?? -1)
"POST_WARMUP HB_AGE_SEC=" + (\ ?? -1)

if(Test-Path -LiteralPath \){
  "
--- heartbeat_err.txt ---"
  Get-Content -LiteralPath \ -Tail 50
}
if(Test-Path -LiteralPath \){
  "
--- heartbeat.json ---"
  Get-Content -LiteralPath \ -Tail 5
}

"=== CLEAN_START END ==="
