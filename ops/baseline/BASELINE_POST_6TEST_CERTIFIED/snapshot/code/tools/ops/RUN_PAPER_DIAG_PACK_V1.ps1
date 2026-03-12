param()

$ErrorActionPreference="Stop"
$ROOT="C:\alpaca-bot\org_bot"
$RUN ="C:\alpaca-bot\org_bot_runtime\paper"
$UP  = Join-Path $ROOT "_MYGPT_UPLOAD"
New-Item -ItemType Directory -Force -Path $UP | Out-Null

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OUTDIR = Join-Path $UP "PAPER_RUN_DIAG_$stamp"
New-Item -ItemType Directory -Force -Path $OUTDIR | Out-Null

$meta    = Join-Path $RUN "logs\meta.jsonl"
$runner  = Join-Path $ROOT "tools\RUN_PAPER_SHADOW_CANON_V1.ps1"
$profile = Join-Path $ROOT "tools\profiles\paper.profile.json"

$pwsh="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwsh)){ $pwsh="pwsh" }

$stdout = Join-Path $OUTDIR "runner_out.txt"
$stderr = Join-Path $OUTDIR "runner_err.txt"

$arg = @(
  "-NoProfile","-ExecutionPolicy","Bypass",
  "-File","`"$runner`"",
  "-ProjectRoot","`"$ROOT`"",
  "-ProfilePath","`"$profile`""
) -join " "

$p = Start-Process -FilePath $pwsh -ArgumentList $arg -PassThru `
      -RedirectStandardOutput $stdout -RedirectStandardError $stderr

"STARTED_PID=$($p.Id)" | Set-Content -Encoding utf8 (Join-Path $OUTDIR "pid.txt")
"ARG=$arg"             | Set-Content -Encoding utf8 (Join-Path $OUTDIR "arg.txt")

# Watch meta movement for 60s
$t0 = if(Test-Path $meta){ (Get-Item $meta).LastWriteTime } else { $null }
"META_T0=$t0" | Set-Content -Encoding utf8 (Join-Path $OUTDIR "meta_watch.txt")

for($i=1;$i -le 6;$i++){
  Start-Sleep -Seconds 10
  $t = if(Test-Path $meta){ (Get-Item $meta).LastWriteTime } else { $null }
  "$i META_T=$t" | Add-Content -Encoding utf8 (Join-Path $OUTDIR "meta_watch.txt")
}

if(Test-Path $meta){
  Get-Content -LiteralPath $meta -Tail 30 | Set-Content -Encoding utf8 (Join-Path $OUTDIR "meta_tail_30.txt")
}

# Process snapshot
Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Select-Object ProcessId,CommandLine |
  Out-String | Set-Content -Encoding utf8 (Join-Path $OUTDIR "python_processes.txt")

# Task snapshots (best-effort; never fail the pack)
try { schtasks /query /tn "\ORG_BOT_PAPER_RUNNER" /v /fo list | Out-String | Set-Content -Encoding utf8 (Join-Path $OUTDIR "task_runner_status.txt") } catch { $_ | Out-String | Set-Content -Encoding utf8 (Join-Path $OUTDIR "task_runner_status.txt") }
try { schtasks /query /tn "\TBOT_LLM_GATE_WATCHDOG_10S" /v /fo list | Out-String | Set-Content -Encoding utf8 (Join-Path $OUTDIR "task_llm_watchdog_status.txt") } catch { $_ | Out-String | Set-Content -Encoding utf8 (Join-Path $OUTDIR "task_llm_watchdog_status.txt") }

# Zip (best-effort but should not hang)
$ZIP="$OUTDIR.zip"
if(Test-Path $ZIP){ Remove-Item $ZIP -Force }
Compress-Archive -Path (Join-Path $OUTDIR "*") -DestinationPath $ZIP -Force

"PACK_READY=$ZIP" | Write-Host
