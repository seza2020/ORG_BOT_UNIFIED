param(
  [string]\C:\alpaca-bot\org_bot="C:\alpaca-bot\org_bot",
  [string]\C:\alpaca-bot\org_bot_runtime\paper="C:\alpaca-bot\org_bot_runtime\paper",
  [int]\=60
)
\Stop="Stop"
"=== WATCHDOG_LOOP START ==="
"Root=\C:\alpaca-bot\org_bot"
"RunRoot=\C:\alpaca-bot\org_bot_runtime\paper"
"EverySec=\"

while(\True){
  try{
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path \C:\alpaca-bot\org_bot "tools\ops\WATCHDOG_META_STALL_AUTOFIX_V1.ps1") -Root \C:\alpaca-bot\org_bot -RunRoot \C:\alpaca-bot\org_bot_runtime\paper
  }catch{
    \ | Out-Host
  }
  Start-Sleep -Seconds \
}
