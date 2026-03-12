param(
  [string]$Root   = "C:\alpaca-bot\org_bot",
  [string]$RunRoot= "C:\alpaca-bot\org_bot_runtime\paper"
)
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$outdir = Join-Path $Root "_MYGPT_UPLOAD\LLM_GATE_EVIDENCE_$stamp"
New-Item -ItemType Directory -Force $outdir | Out-Null

Copy-Item (Join-Path $Root 'tools\ops\LLM_GATE_WATCHDOG_V1.ps1') $outdir -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $Root 'tools\ops\LLM_GATE_RESET_FLAG.ps1') $outdir -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RunRoot 'logs\ops\llm_gate_watchdog.jsonl') $outdir -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RunRoot 'state\LLM_GATE_DISABLED.flag') $outdir -Force -ErrorAction SilentlyContinue

# Tail meta + decisions if exist
$meta = Join-Path $RunRoot 'logs\meta_paper.jsonl'
if(Test-Path $meta){
  Get-Content -LiteralPath $meta -Tail 200 | Set-Content -Encoding utf8 (Join-Path $outdir 'meta_paper_TAIL200.txt')
}

$dec = Join-Path $RunRoot 'logs\ops\local_api_decisions.jsonl'
if(Test-Path $dec){
  Get-Content -LiteralPath $dec -Tail 200 | Set-Content -Encoding utf8 (Join-Path $outdir 'local_api_decisions_TAIL200.txt')
}

# Task snapshot
schtasks /query /tn '\TBOT_LLM_GATE_WATCHDOG_10S' /v /fo list | Set-Content -Encoding utf8 (Join-Path $outdir 'TASK_WATCHDOG.txt')

$zip = "$outdir.zip"
if(Test-Path $zip){ Remove-Item $zip -Force }
Compress-Archive -Path "$outdir\*" -DestinationPath $zip -Force
"PACK_READY=$zip"
