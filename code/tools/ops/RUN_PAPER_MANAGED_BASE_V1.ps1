param(
  [string]$Root="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper"
)
$ErrorActionPreference="Stop"

$PY = Join-Path $Root ".venv\Scripts\python.exe"
if(!(Test-Path -LiteralPath $PY)){ throw "PY_NOT_FOUND=$PY" }

$ops   = Join-Path $RunRoot "logs\ops"
$state = Join-Path $RunRoot "state"
New-Item -ItemType Directory -Force -Path $ops,$state | Out-Null

# deterministic runroot for heartbeat derivation
$env:TBOT_RUNROOT  = $RunRoot
$env:TBOT_RUNTIME  = $RunRoot

$ts   = Get-Date -Format "yyyyMMdd_HHmmss"
$mOut = Join-Path $ops ("MANAGED_STDOUT_{0}.txt" -f $ts)
$mErr = Join-Path $ops ("MANAGED_STDERR_{0}.txt" -f $ts)

$meta   = Join-Path $RunRoot "logs\meta.jsonl"
$ann    = Join-Path $RunRoot "logs\announce.log"
$ledger = Join-Path $RunRoot "logs\trades"
$shadow = Join-Path $RunRoot "logs\shadow_plans.jsonl"
New-Item -ItemType Directory -Force -Path $ledger | Out-Null

# BASELINE args فقط برای پایدار کردن لانچ/لاگ/heartbeat (بعداً ویژگی‌های runner قدیمی را مرحله‌ای اضافه می‌کنیم)
$pyArgs = @(
  "-u","-m","tbot.main",
  "--run","--iters","999999",
  "--sleep","1",
  "--meta",$meta,
  "--announce",$ann,
  "--ledger_dir",$ledger,
  "--shadow",
  "--shadow_path",$shadow
)

Write-Host ("[RUN_BASE] STDOUT={0}" -f $mOut)
Write-Host ("[RUN_BASE] STDERR={0}" -f $mErr)

$p = Start-Process -FilePath $PY -ArgumentList $pyArgs -PassThru -WindowStyle Hidden `
      -RedirectStandardOutput $mOut -RedirectStandardError $mErr

$pidFile = Join-Path $state "pid.txt"
Set-Content -Encoding ASCII -LiteralPath $pidFile -Value $p.Id
Write-Host ("[RUN_BASE] PID_WRITTEN={0} => {1}" -f $p.Id, $pidFile)

Start-Sleep -Seconds 2
try{
  Get-Process -Id $p.Id -ErrorAction Stop | Out-Null
  Write-Host ("[RUN_BASE] ALIVE=1 PID={0}" -f $p.Id)
}catch{
  Write-Host ("[RUN_BASE] ALIVE=0 PID={0} (died early)" -f $p.Id)
  if(Test-Path $mErr){
    Write-Host "--- STDERR_TAIL(120) ---"
    Get-Content -LiteralPath $mErr -Tail 120
  }
  exit 2
}
