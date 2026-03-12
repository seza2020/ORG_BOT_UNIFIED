param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$WarmupSec=5
)
$ErrorActionPreference="Continue"
$PY = Join-Path $Root ".venv\Scripts\python.exe"
$ops = Join-Path $RunRoot "logs\ops"
$state = Join-Path $RunRoot "state"
New-Item -ItemType Directory -Force -Path $ops,$state | Out-Null

$env:TBOT_RUNROOT=$RunRoot
$env:TBOT_RUNTIME=$RunRoot

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$stdout = Join-Path $ops "BASE_STDOUT_$ts.txt"
$stderr = Join-Path $ops "BASE_STDERR_$ts.txt"
$meta   = Join-Path $RunRoot "logs\meta.jsonl"
$ann    = Join-Path $RunRoot "logs\announce.log"
$ledger = Join-Path $RunRoot "logs\trades"
$shadow = Join-Path $RunRoot "logs\shadow_plans.jsonl"
New-Item -ItemType Directory -Force -Path $ledger | Out-Null

# clear state (so we don't read stale hb)
Remove-Item -Force -ErrorAction SilentlyContinue `
  (Join-Path $RunRoot "state\locks\RUN_PAPER_PROFILE.lock"),
  (Join-Path $RunRoot "state\pid.txt"),
  (Join-Path $RunRoot "state\heartbeat.json"),
  (Join-Path $RunRoot "state\heartbeat_err.txt")

"=== AUTOPSY_BOOT_ONLY ==="
"TS=$ts"
"PY=$PY"
"STDOUT=$stdout"
"STDERR=$stderr"
"RUNROOT=$RunRoot"
"META=$meta"

# start python directly (not via old runner)
$args = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999",
  "--sleep","1",
  "--meta",$meta,
  "--announce",$ann,
  "--ledger_dir",$ledger,
  "--shadow","--shadow_path",$shadow
)

$p = Start-Process -FilePath $PY -ArgumentList $args -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput $stdout -RedirectStandardError $stderr

$pidFile = Join-Path $state "pid.txt"
Set-Content -Encoding ASCII -LiteralPath $pidFile -Value $p.Id
"PID=$($p.Id)"

Start-Sleep -Seconds $WarmupSec

# snapshot
$alive=$false
try{ Get-Process -Id $p.Id -ErrorAction Stop | Out-Null; $alive=$true }catch{$alive=$false}
"ALIVE=$alive"

function AgeSec([string]$p){
  if(!(Test-Path -LiteralPath $p)){ return $null }
  [int](([DateTime]::UtcNow-(Get-Item $p).LastWriteTimeUtc).TotalSeconds)
}

$ma = AgeSec $meta
$hb = Join-Path $RunRoot "state\heartbeat.json"
$ha = AgeSec $hb
"metaAgeSec=" + ($ma ?? -1)
"hbAgeSec="   + ($ha ?? -1)

"--- STDERR_TAIL(120) ---"
if(Test-Path $stderr){ Get-Content -LiteralPath $stderr -Tail 120 }

"--- STDOUT_TAIL(120) ---"
if(Test-Path $stdout){ Get-Content -LiteralPath $stdout -Tail 120 }

$herr = Join-Path $RunRoot "state\heartbeat_err.txt"
"--- HEARTBEAT_ERR_TAIL(120) ---"
if(Test-Path $herr){ Get-Content -LiteralPath $herr -Tail 120 }

"=== END AUTOPSY ==="
