param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [int]$AllowBootOverrun=0
)
$ErrorActionPreference="Stop"

$PY = Join-Path $Root ".venv\Scripts\python.exe"
if(!(Test-Path -LiteralPath $PY)){ throw "PY_NOT_FOUND=$PY" }

$ops = Join-Path $RunRoot "logs\ops"
$state = Join-Path $RunRoot "state"
New-Item -ItemType Directory -Force -Path $ops,$state | Out-Null

$env:TBOT_RUNROOT = $RunRoot
$env:TBOT_RUNTIME = $RunRoot

if($AllowBootOverrun -eq 1){ $env:TBOT_ALLOW_BOOT_OVERRUN="1" }
else{ Remove-Item Env:TBOT_ALLOW_BOOT_OVERRUN -ErrorAction SilentlyContinue }

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$mOut = Join-Path $ops ("MANAGED_STDOUT_{0}.txt" -f $ts)
$mErr = Join-Path $ops ("MANAGED_STDERR_{0}.txt" -f $ts)

$meta   = Join-Path $RunRoot "logs\meta_paper.jsonl"
$ann    = Join-Path $RunRoot "logs\announce.log"
$ledger = Join-Path $RunRoot "logs\trades"
$shadow = Join-Path $RunRoot "logs\shadow_plans.jsonl"
New-Item -ItemType Directory -Force -Path $ledger | Out-Null

$pyArgs = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999",
  "--sleep","1",
  "--meta",$meta,
  "--announce",$ann,
  "--ledger_dir",$ledger,
  "--shadow",
  "--shadow_path",$shadow,
  "--gate_min_rr","1.5",
  "--gate_min_conf","0.55",
  "--gate_cooldown_sec","300",
  "--gate_max_plans_per_day","10",
  "--gate_max_risk_per_trade_usd","25",
  "--gate_max_risk_per_day_usd","150"
)

Write-Host ("[MANAGED] AllowBootOverrun={0}" -f $AllowBootOverrun)
Write-Host ("[MANAGED] STDOUT={0}" -f $mOut)
Write-Host ("[MANAGED] STDERR={0}" -f $mErr)

$p = Start-Process -FilePath $PY -ArgumentList $pyArgs -PassThru -WindowStyle Hidden `
  -RedirectStandardOutput $mOut -RedirectStandardError $mErr

$pidFile = Join-Path $state "pid.txt"
Set-Content -Encoding ASCII -LiteralPath $pidFile -Value $p.Id
Write-Host ("[MANAGED] PID_WRITTEN={0} => {1}" -f $p.Id, $pidFile)

Start-Sleep -Seconds 2
try{
  Get-Process -Id $p.Id -ErrorAction Stop | Out-Null
  Write-Host ("[MANAGED] ALIVE=1 PID={0}" -f $p.Id)
}catch{
  Write-Host ("[MANAGED] ALIVE=0 PID={0} (died early)" -f $p.Id)
  if(Test-Path $mErr){
    Write-Host "--- STDERR_TAIL(120) ---"
    Get-Content -LiteralPath $mErr -Tail 120
  }
  exit 2
}

