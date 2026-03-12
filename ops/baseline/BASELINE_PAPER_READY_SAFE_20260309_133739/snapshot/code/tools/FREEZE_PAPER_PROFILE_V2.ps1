param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride="",      # YYYY-MM-DD optional
  [int]$TimeoutSec=180             # TEST: 180s (later you can set 900)
)
$ErrorActionPreference="Stop"

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ops,$ana | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $ops ("FREEZE_OUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("FREEZE_ERR_{0}.txt" -f $ts)

# Determine iso day
if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  # prefer latest LIVE_OUT ymd if exists
  $lo = Get-ChildItem $ops -File -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
  if($lo -and ($lo.Name -match 'LIVE_OUT_(\d{8})_')){
    $ymd=$matches[1]
    $IsoDayOverride = "{0}-{1}-{2}" -f $ymd.Substring(0,4),$ymd.Substring(4,2),$ymd.Substring(6,2)
  } else {
    $IsoDayOverride = (Get-Date).ToString("yyyy-MM-dd")
  }
}
$ymd = $IsoDayOverride.Replace("-","")

# Force filelog path safe (prevents ibkr contamination in env_TBOT_SAFE)
try{
  $safe = Join-Path $RunRoot 'logs\bot_console_{date}.log'
  $old  = $env:TBOT_FILELOG_PATH
  $env:TBOT_FILELOG_PATH = $safe
  "TBOT_FILELOG_PATH_SET=1 old=$old new=$safe" | Add-Content -Encoding UTF8 -Path $out
}catch{
  ("TBOT_FILELOG_PATH_SET_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

"ISO_DAY_USED=$IsoDayOverride" | Add-Content -Encoding UTF8 -Path $out

# 1) Policy snapshot
try{
  $ps = Join-Path $ProjectRoot "tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1"
  if(Test-Path $ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $ps -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
    "POLICY_SNAPSHOT_WRITER_OK=1" | Add-Content -Encoding UTF8 -Path $out
  }
}catch{ ("POLICY_SNAPSHOT_WRITER_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# 2) Config gates
try{
  $val = Join-Path $ProjectRoot "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1"
  if(Test-Path $val){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $val -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
    ("CONFIG_GATES_EXIT=" + $LASTEXITCODE) | Add-Content -Encoding UTF8 -Path $out
  }
}catch{ ("CONFIG_GATES_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# 3) Expectancy guard (full day)
try{
  $g = Join-Path $ProjectRoot "tools\ops\EXPECTANCY_GUARD_REPORT_V1.ps1"
  if(Test-Path $g){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $g -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride -LookbackMinutes 0 -WarnCount 50 -FailCount 200 -KillOnFail 0 1>> $out 2>> $err
    ("EXPECTANCY_GUARD_EXIT=" + $LASTEXITCODE) | Add-Content -Encoding UTF8 -Path $out
  } else {
    "EXPECTANCY_GUARD_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
  }
}catch{ ("EXPECTANCY_GUARD_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# 4) Run core freeze in child process with timeout
$freeze = Join-Path $ProjectRoot "tools\freeze_today_enterprise.ps1"
$pwshExe="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwshExe)){ $pwshExe=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwshExe)){ $pwshExe=(Get-Command powershell.exe).Source }

$childOut = Join-Path $ops ("FREEZE_CHILD_OUT_{0}.txt" -f $ts)
$childErr = Join-Path $ops ("FREEZE_CHILD_ERR_{0}.txt" -f $ts)

$exitCore = 0
try{
  if(!(Test-Path $freeze)){ throw "MISSING_FREEZE_CORE=$freeze" }
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$freeze,'-Root',$ProjectRoot,'-IsoDayOverride',$IsoDayOverride)
  $p = Start-Process -FilePath $pwshExe -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $childOut -RedirectStandardError $childErr
  $done = $p.WaitForExit($TimeoutSec * 1000)
  if(-not $done){
    try{ $p.Kill() } catch {}
    $exitCore = 124
    ("FREEZE_TIMEOUT_KILLED=1 timeout_sec=" + $TimeoutSec) | Add-Content -Encoding UTF8 -Path $err
  } else {
    $exitCore = $p.ExitCode
    ("FREEZE_CHILD_EXIT=" + $exitCore) | Add-Content -Encoding UTF8 -Path $out
  }
}catch{
  $exitCore = 125
  ("FREEZE_CORE_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

# append child logs best-effort
try{ if(Test-Path $childOut){ Get-Content $childOut | Add-Content -Encoding UTF8 -Path $out } } catch {}
try{ if(Test-Path $childErr){ Get-Content $childErr | Add-Content -Encoding UTF8 -Path $err } } catch {}

# 5) Locate backup dir and copy evidence + build minimal zip
try{
  $bk = Get-ChildItem $ops -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $ymd) -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
  if(!$bk){
    ("EXPECTANCY_GUARD_COPIED=0 reason=NO_BACKUP ymd=" + $ymd) | Add-Content -Encoding UTF8 -Path $out
  } else {
    $need = @(
      "QC_$ymd.txt",
      "env_TBOT_SAFE_$ymd.txt",
      "CONFIG_GATES_$ymd.txt","CONFIG_GATES_$ymd.json",
      "POLICY_SNAPSHOT_$ymd.md","POLICY_SNAPSHOT_$ymd.json",
      "KPI_$ymd.json","KPI_$ymd.md",
      "REALIZED_KPI_$ymd.json","REALIZED_KPI_$ymd.md",
      "LEDGER_SIM_$ymd.jsonl","RECON_SIM_$ymd.json",
      "EXPECTANCY_GUARD_$ymd.txt","EXPECTANCY_GUARD_$ymd.json"
    )

    # Ensure guard files are in backup (copy from ops/analytics if exist)
    foreach($n in @("EXPECTANCY_GUARD_$ymd.txt","EXPECTANCY_GUARD_$ymd.json")){
      foreach($src in @((Join-Path $ops $n),(Join-Path $ana $n))){
        if(Test-Path $src){ Copy-Item $src (Join-Path $bk.FullName (Split-Path $src -Leaf)) -Force }
      }
    }

    # rebuild minimal zip
    Get-ChildItem $bk.FullName -File -Filter ("FREEZE_TODAY_$ymd*.zip") -ErrorAction SilentlyContinue |
      ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

    $zip2 = Join-Path $bk.FullName ("FREEZE_TODAY_{0}_{1}.zip" -f $ymd,(Get-Date -Format "yyyyMMdd_HHmmss"))
    $paths=@()
    foreach($n in $need){
      $pp = Join-Path $bk.FullName $n
      if(Test-Path $pp){ $paths += $pp }
    }
    if($paths.Count -gt 0){
      Compress-Archive -Path $paths -DestinationPath $zip2 -Force
      ("MIN_ZIP_OK=1 files=" + $paths.Count + " zip=" + $zip2) | Add-Content -Encoding UTF8 -Path $out
      ("EXPECTANCY_GUARD_COPIED=1 ymd=" + $ymd) | Add-Content -Encoding UTF8 -Path $out
    } else {
      ("MIN_ZIP_OK=0 reason=NO_EVID_FILES ymd=" + $ymd) | Add-Content -Encoding UTF8 -Path $out
    }
  }
}catch{
  ("EVIDENCE_COPY_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

("FREEZE_V2_DONE core_exit=" + $exitCore) | Add-Content -Encoding UTF8 -Path $out
exit 0
