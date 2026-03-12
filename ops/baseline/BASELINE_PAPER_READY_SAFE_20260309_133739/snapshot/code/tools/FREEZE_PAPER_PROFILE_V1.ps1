param(
  [string]$ProjectRoot = "C:\alpaca-bot\org_bot",
  [string]$RunRoot = "C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride = ""
)
$ErrorActionPreference="Stop"

# FREEZE_EXIT_DEFER_V1
if($null -eq $__freeze_exit_code){ $__freeze_exit_code = 0 }


$env:TBOT_RUNROOT = $RunRoot
$ops = Join-Path $RunRoot "logs\ops"
New-Item -ItemType Directory -Force -Path $ops | Out-Null
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $ops ("FREEZE_OUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("FREEZE_ERR_{0}.txt" -f $ts)

try {
  # AUTO IsoDayOverride from newest LIVE_OUT filename: LIVE_OUT_YYYYMMDD_*.txt -> YYYY-MM-DD
  if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
    $lo = Get-ChildItem -Path $ops -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($lo){
      $m = [regex]::Match($lo.Name, "^LIVE_OUT_(\d{4})(\d{2})(\d{2})")
      if($m.Success){ $IsoDayOverride = "{0}-{1}-{2}" -f $m.Groups[1].Value,$m.Groups[2].Value,$m.Groups[3].Value }
    }
    if([string]::IsNullOrWhiteSpace($IsoDayOverride)){ $IsoDayOverride = (Get-Date).ToString("yyyy-MM-dd") }
  }
  "ISO_DAY_USED=$IsoDayOverride" | Out-File -Encoding UTF8 -FilePath $out
  # POLICY_SNAPSHOT_AFTER_ISO_DAY_USED_V5 (market-day aligned; guaranteed)
  try {
    $iso2 = $IsoDayOverride
    if(Test-Path $out){
      $m = Select-String -Path $out -Pattern '^ISO_DAY_USED=' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($m){ $iso2 = ($m.Line.Split('=')[1]).Trim() }
    }
    if([string]::IsNullOrWhiteSpace($iso2)){ $iso2 = (Get-Date).ToString("yyyy-MM-dd") }

    $ps = Join-Path $ProjectRoot 'tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1'
    if(Test-Path $ps){
      & $ps -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $iso2 1>> $out 2>> $err
      'POLICY_SNAPSHOT_WRITER_OK=1' | Add-Content -Encoding UTF8 -Path $out
    } else {
      'POLICY_SNAPSHOT_WRITER_MISSING=1' | Add-Content -Encoding UTF8 -Path $err
    }
  } catch {
    ('POLICY_SNAPSHOT_WRITER_EXC=' + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }

  $freeze = Join-Path $ProjectRoot "tools\freeze_today_enterprise.ps1"
  if(!(Test-Path $freeze)){ throw "MISSING_FREEZE_SCRIPT=$freeze" }

    # MONEY_MACHINE_DAILY_V1 (KPI/Selection/Exposure/SimExec/Scaling)
  $py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $py)){ $py = "python" }
  $daily = Join-Path $ProjectRoot "tools\analytics\money_machine_daily.py"
  & $py $daily --runroot $RunRoot --isoday $IsoDayOverride --max_plans 30 1>> $out 2>> $err
  # LEDGER_RECON_SIM_V1 (SIM Ledger + SIM Recon)
  $py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $py)){ $py = "python" }
  $lr = Join-Path $ProjectRoot "tools\analytics\ledger_recon_sim.py"
  & $py $lr --runroot $RunRoot --isoday $IsoDayOverride 1>> $out 2>> $err
  # PAPER_POLL_BEFORE_FREEZE_V1 (refresh order states into LEDGER_REAL)
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "$ProjectRoot\tools\paper\POLL_PAPER_ORDERS_V1.ps1" -ProjectRoot "$ProjectRoot" -RunRoot "$RunRoot" -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err

  # CONFIG_GATES_FREEZE_V1
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\alpaca-bot\org_bot\tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1" -ProjectRoot "C:\alpaca-bot\org_bot" -RunRoot "C:\alpaca-bot\org_bot_runtime\paper" -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
  "CONFIG_GATES_EXIT=$LASTEXITCODE" | Add-Content -Encoding UTF8 -Path $out
  # REALIZED_KPI_FREEZE_V1 (write REALIZED_KPI_YYYYMMDD.* into analytics for evidence)
  $py = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $py)){ $py = "python" }
  $rk = Join-Path $ProjectRoot "tools\analytics\realized_kpi_from_ledger.py"
  & $py $rk --runroot $RunRoot --isoday $IsoDayOverride 1>> $out 2>> $err
  # POLICY_SNAPSHOT_FREEZE_V1 (write POLICY_SNAPSHOT_YYYYMMDD.* into analytics for evidence)
  & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass 
    -File "C:\alpaca-bot\org_bot\tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1" -ProjectRoot "C:\alpaca-bot\org_bot" -RunRoot "C:\alpaca-bot\org_bot_runtime\paper" -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
  # POLICY_SNAPSHOT_CALL_SAFE_V4 (guaranteed; logs to FREEZE_OUT/FREEZE_ERR)
  try {
    $ps = Join-Path $ProjectRoot 'tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1'
    if(Test-Path $ps){
      & $ps -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
      'POLICY_SNAPSHOT_WRITER_OK=1' | Add-Content -Encoding UTF8 -Path $out
    } else {
      'POLICY_SNAPSHOT_WRITER_MISSING=1' | Add-Content -Encoding UTF8 -Path $err
    }
  } catch {
    ('POLICY_SNAPSHOT_WRITER_EXC=' + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
  # FILELOG_PATH_SANITIZE_FREEZE_V1 (force TBOT_FILELOG_PATH under RunRoot so env_TBOT_SAFE is correct)
  try {
    $safe = Join-Path $RunRoot 'logs\bot_console_{date}.log'
    $old  = $env:TBOT_FILELOG_PATH
    $env:TBOT_FILELOG_PATH = $safe
    ("TBOT_FILELOG_PATH_SET=1 old=" + $old + " new=" + $safe) | Add-Content -Encoding UTF8 -Path $out
  } catch {
    ("TBOT_FILELOG_PATH_SET_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
  # EXPECTANCY_GUARD_FREEZE_V1 (write EXPECTANCY_GUARD_YYYYMMDD.* into ops+analytics; log exit)
  try {
    & "C:\alpaca-bot\org_bot\tools\ops\EXPECTANCY_GUARD_REPORT_V1.ps1" -ProjectRoot "C:\alpaca-bot\org_bot" -RunRoot "C:\alpaca-bot\org_bot_runtime\paper" -IsoDayOverride $IsoDayOverride -WarnCount 50 -FailCount 200 -LookbackMinutes 0 -KillOnFail 0 1>> $out 2>> $err
    ("EXPECTANCY_GUARD_EXIT=" + $LASTEXITCODE) | Add-Content -Encoding UTF8 -Path $out
  } catch {
    ("EXPECTANCY_GUARD_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
# FREEZE_SUBPROCESS_V1 (run freeze in child pwsh so 'exit' won't kill wrapper)
$pwshExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
if(!(Test-Path $pwshExe)){ $pwshExe = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwshExe)){ $pwshExe = (Get-Command powershell.exe).Source }
# FREEZE_CHILD_TIMEOUT_V1 (run freeze in child process with timeout; never hang)
$ts2 = Get-Date -Format 'yyyyMMdd_HHmmss'
$childOut = Join-Path (Split-Path $out -Parent) ('FREEZE_CHILD_OUT_' + $ts2 + '.txt')
$childErr = Join-Path (Split-Path $err -Parent) ('FREEZE_CHILD_ERR_' + $ts2 + '.txt')
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$freeze,'-Root',$ProjectRoot,'-IsoDayOverride',$IsoDayOverride)
$p = Start-Process -FilePath $pwshExe -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $childOut -RedirectStandardError $childErr
$timeoutSec = 900  # 15 minutes (adjust if needed)
$done = $p.WaitForExit($timeoutSec * 1000)
if(-not $done){
  try{ $p.Kill() } catch {}
  'FREEZE_TIMEOUT_KILLED=1 timeout_sec=' + $timeoutSec | Add-Content -Encoding UTF8 -Path $err
  $__freeze_exit_code = 124
} else {
  $__freeze_exit_code = $p.ExitCode
  ('FREEZE_CHILD_EXIT=' + $__freeze_exit_code) | Add-Content -Encoding UTF8 -Path $out
}
# append child logs (best effort)
try { if(Test-Path $childOut){ Get-Content $childOut | Add-Content -Encoding UTF8 -Path $out } } catch {}
try { if(Test-Path $childErr){ Get-Content $childErr | Add-Content -Encoding UTF8 -Path $err } } catch {}
('FREEZE_CHILD_EXIT=' + $LASTEXITCODE) | Add-Content -Encoding UTF8 -Path $out
  # POST_FREEZE_COPY_EXPECTANCY_GUARD_V1 (ensure report lands in backup + zip)
  try {
    $iso2 = $IsoDayOverride
    if(Test-Path $out){
      $m = Select-String -Path $out -Pattern '^ISO_DAY_USED=' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($m){ $iso2 = ($m.Line.Split('=')[1]).Trim() }
    }
    if([string]::IsNullOrWhiteSpace($iso2)){ $iso2 = (Get-Date).ToString('yyyy-MM-dd') }
    $ymd2 = $iso2.Replace('-','')

    $opsDir = Join-Path $RunRoot 'logs\ops'
    $anaDir = Join-Path $RunRoot 'logs\analytics'
    $bk = Get-ChildItem $opsDir -Directory -Filter ('FREEZE_BACKUP_' + $ymd2 + '_*') -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if($bk){
      $src1 = Join-Path $opsDir ('EXPECTANCY_GUARD_' + $ymd2 + '.txt')
      $src2 = Join-Path $opsDir ('EXPECTANCY_GUARD_' + $ymd2 + '.json')
      $src3 = Join-Path $anaDir ('EXPECTANCY_GUARD_' + $ymd2 + '.txt')
      $src4 = Join-Path $anaDir ('EXPECTANCY_GUARD_' + $ymd2 + '.json')
      foreach($s in @($src1,$src2,$src3,$src4)){
        if(Test-Path $s){ Copy-Item $s (Join-Path $bk.FullName (Split-Path $s -Leaf)) -Force }
      }

      # rebuild zip
      Get-ChildItem $bk.FullName -File -Filter ('FREEZE_TODAY_' + $ymd2 + '_*.zip') -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
      $zip2 = Join-Path $bk.FullName ('FREEZE_TODAY_' + $ymd2 + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.zip')
      $paths = Get-ChildItem $bk.FullName -Recurse -File -Exclude 'FREEZE_TODAY_*.zip' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
      if($paths -and $paths.Count -gt 0){ Compress-Archive -Path $paths -DestinationPath $zip2 -Force }
      ('EXPECTANCY_GUARD_COPIED=1 ymd=' + $ymd2 + ' zip=' + $zip2) | Add-Content -Encoding UTF8 -Path $out
    } else {
      ('EXPECTANCY_GUARD_COPIED=0 reason=NO_BACKUP ymd=' + $ymd2) | Add-Content -Encoding UTF8 -Path $out
    }
  } catch {
    ('EXPECTANCY_GUARD_COPY_EXC=' + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
  # POST_FREEZE_POLICY_SNAPSHOT_V2 (market-day aligned snapshot -> copy into backup -> rebuild zip)
  try {
    # Prefer ISO_DAY_USED written by freeze script, fallback to IsoDayOverride
    $iso2 = $IsoDayOverride
    if(Test-Path $out){
      $m = Select-String -Path $out -Pattern '^ISO_DAY_USED=' -ErrorAction SilentlyContinue | Select-Object -First 1
      if($m){ $iso2 = ($m.Line.Split('=')[1]).Trim() }
    }
    if([string]::IsNullOrWhiteSpace($iso2)){ $iso2 = (Get-Date).ToString('yyyy-MM-dd') }
    $ymd2 = $iso2.Replace('-','')

    # Write snapshot (goes to logs/analytics)
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass 
      -File "C:\alpaca-bot\org_bot\tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1" -ProjectRoot "C:\alpaca-bot\org_bot" -RunRoot "C:\alpaca-bot\org_bot_runtime\paper" -IsoDayOverride $iso2 1>> $out 2>> $err

    # Copy into matching backup dir
    $opsDir = Join-Path $RunRoot 'logs\ops'
    $anaDir = Join-Path $RunRoot 'logs\analytics'
    $bk = Get-ChildItem $opsDir -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $ymd2) -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if($bk){
      $md = Join-Path $anaDir ("POLICY_SNAPSHOT_{0}.md" -f $ymd2)
      $js = Join-Path $anaDir ("POLICY_SNAPSHOT_{0}.json" -f $ymd2)
      if(Test-Path $md){ Copy-Item $md (Join-Path $bk.FullName (Split-Path $md -Leaf)) -Force }
      if(Test-Path $js){ Copy-Item $js (Join-Path $bk.FullName (Split-Path $js -Leaf)) -Force }

      # Rebuild zip without including itself
      Get-ChildItem $bk.FullName -File -Filter ("FREEZE_TODAY_{0}_*.zip" -f $ymd2) -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

      $zip2 = Join-Path $bk.FullName ("FREEZE_TODAY_{0}_{1}.zip" -f $ymd2,(Get-Date -Format 'yyyyMMdd_HHmmss'))
      $paths = Get-ChildItem $bk.FullName -Recurse -File -Exclude 'FREEZE_TODAY_*.zip' -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
      if($paths -and $paths.Count -gt 0){ Compress-Archive -Path $paths -DestinationPath $zip2 -Force }

      "POST_FREEZE_POLICY_SNAPSHOT_OK=1 ymd=$ymd2 zip=$zip2" | Add-Content -Encoding UTF8 -Path $out
    } else {
      "POST_FREEZE_POLICY_SNAPSHOT_OK=0 reason=NO_BACKUP_DIR ymd=$ymd2" | Add-Content -Encoding UTF8 -Path $out
    }
  } catch {
    ("POST_FREEZE_POLICY_SNAPSHOT_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
  # POST_FREEZE_INCLUDE_CONFIG_GATES_V1 (guarantee CONFIG_GATES_* inside FREEZE_BACKUP and zip)
  try {
    $ymd = $IsoDayOverride.Replace("-","")
    $opsDir = Join-Path $RunRoot "logs\ops"
    $anaDir = Join-Path $RunRoot "logs\analytics"
    $bk = Get-ChildItem -Path $opsDir -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $ymd) -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($bk){
      Get-ChildItem $opsDir -File -Filter ("CONFIG_GATES_{0}.*" -f $ymd) -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $bk.FullName $_.Name) -Force }
      Get-ChildItem $anaDir -File -Filter ("CONFIG_GATES_{0}.*" -f $ymd) -ErrorAction SilentlyContinue |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $bk.FullName $_.Name) -Force }

      # rebuild zip without including itself
      Get-ChildItem -Path $bk.FullName -File -Filter ("FREEZE_TODAY_{0}_*.zip" -f $ymd) -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
      $zip2 = Join-Path $bk.FullName ("FREEZE_TODAY_{0}_{1}.zip" -f $ymd, (Get-Date -Format "yyyyMMdd_HHmmss"))
      $paths = Get-ChildItem -Path $bk.FullName -Recurse -File -Exclude "FREEZE_TODAY_*.zip" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
      if($paths -and $paths.Count -gt 0){ Compress-Archive -Path $paths -DestinationPath $zip2 -Force }
      "POST_FREEZE_CFG_OK=1 zip=$zip2" | Add-Content -Encoding UTF8 -Path $out
    } else {
      "POST_FREEZE_CFG_OK=0 reason=NO_BACKUP_DIR ymd=$ymd" | Add-Content -Encoding UTF8 -Path $out
    }
  } catch {
    ("POST_FREEZE_CFG_EXCEPTION=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
  # POST_FREEZE_INCLUDE_ANALYTICS_LEDGER_V2 (include analytics+ledger in FREEZE_BACKUP and zip; avoid self-zip)
    # POLICY_SNAPSHOT_COPY_INTO_BACKUP_V1
    try {
      $ymd = $IsoDayOverride.Replace("-","")
      $opsDir = Join-Path $RunRoot "logs\ops"
      $anaDir = Join-Path $RunRoot "logs\analytics"
      $bk = Get-ChildItem -Path $opsDir -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $ymd) -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
      if($bk){
        $md = Join-Path $anaDir ("POLICY_SNAPSHOT_{0}.md" -f $ymd)
        $js = Join-Path $anaDir ("POLICY_SNAPSHOT_{0}.json" -f $ymd)
        if(Test-Path $md){ Copy-Item $md (Join-Path $bk.FullName (Split-Path $md -Leaf)) -Force }
        if(Test-Path $js){ Copy-Item $js (Join-Path $bk.FullName (Split-Path $js -Leaf)) -Force }
        "POLICY_SNAPSHOT_COPIED=1 ymd=$ymd" | Add-Content -Encoding UTF8 -Path $out
      } else {
        "POLICY_SNAPSHOT_COPIED=0 reason=NO_BACKUP ymd=$ymd" | Add-Content -Encoding UTF8 -Path $out
      }
    } catch {
      ("POLICY_SNAPSHOT_COPY_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
    }
    # POLICY_SNAPSHOT_GUARANTEE_V3 (always write snapshot, then it will be copied into backup by the same block)
    try {
      & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass 
        -File "C:\alpaca-bot\org_bot\tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1" -ProjectRoot "" -RunRoot "" -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
      "POLICY_SNAPSHOT_WRITER_OK=1" | Add-Content -Encoding UTF8 -Path $out
    } catch {
      ("POLICY_SNAPSHOT_WRITER_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
    }
  try {
    $ymd = $IsoDayOverride.Replace("-","")
    $opsDir = Join-Path $RunRoot "logs\ops"
    $anaDir = Join-Path $RunRoot "logs\analytics"
    $ledDir = Join-Path $RunRoot "logs\ledger"

    $bk = Get-ChildItem -Path $opsDir -Directory -Filter ("FREEZE_BACKUP_{0}_*" -f $ymd) -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if($bk){
      # Copy analytics files for day
      if(Test-Path $anaDir){
        Get-ChildItem -Path $anaDir -File -Filter ("*_{0}.*" -f $ymd) -ErrorAction SilentlyContinue |
          ForEach-Object { Copy-Item $_.FullName (Join-Path $bk.FullName $_.Name) -Force }
      }
      # Copy ledger files for day
      if(Test-Path $ledDir){
        Get-ChildItem -Path $ledDir -File -Filter ("*_{0}.*" -f $ymd) -ErrorAction SilentlyContinue |
          ForEach-Object { Copy-Item $_.FullName (Join-Path $bk.FullName $_.Name) -Force }
      }

      # Remove old zips then rebuild a fresh zip without including itself
      Get-ChildItem -Path $bk.FullName -File -Filter ("FREEZE_TODAY_{0}_*.zip" -f $ymd) -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }

      $zip2 = Join-Path $bk.FullName ("FREEZE_TODAY_{0}_{1}.zip" -f $ymd, (Get-Date -Format "yyyyMMdd_HHmmss"))
      $paths = Get-ChildItem -Path $bk.FullName -Recurse -File -Exclude "FREEZE_TODAY_*.zip" -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty FullName
      if($paths -and $paths.Count -gt 0){
        Compress-Archive -Path $paths -DestinationPath $zip2 -Force
      }

      "POST_FREEZE_COPY_OK=1 bk=$($bk.FullName) zip=$zip2" | Add-Content -Encoding UTF8 -Path $out
    } else {
      "POST_FREEZE_COPY_OK=0 reason=NO_BACKUP_DIR_FOUND ymd=$ymd" | Add-Content -Encoding UTF8 -Path $out
    }
  } catch {
    ("POST_FREEZE_COPY_EXCEPTION=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
  $code = $LASTEXITCODE
  "FREEZE_EXIT_CODE=$code" | Add-Content -Encoding UTF8 -Path $out

  # POLICY: WARN is OK (  # POLICY: WARN is OK (exit 0), FAIL is not OK (exit 1)_freeze_exit_code = 0),  # EXIT_DEFERRED FAIL is not OK (  # POLICY: WARN is OK (exit 0), FAIL is not OK (exit 1)_freeze_exit_code = 1)  # EXIT_DEFERRED
  $bk = Get-ChildItem -Path $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($bk){
    $qc = Get-ChildItem -Path $bk.FullName -File -Filter "QC_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if($qc){
      $qct = Get-Content -Raw $qc.FullName
      $m2 = [regex]::Match($qct, "QC_RESULT=(\w+)", "IgnoreCase")
      if($m2.Success){
        $qr = $m2.Groups[1].Value.ToUpperInvariant()
        "QC_RESULT=$qr" | Add-Content -Encoding UTF8 -Path $out
        # QC_FAIL_KILLSWITCH_V1 (fail-closed)
if($qr -eq "FAIL"){
  try{
    $ks = Join-Path $RunRoot "KILL_SWITCH"
    "ts=$(Get-Date -Format s) reason=qc_fail qc=$($qc.FullName)" | Set-Content -Encoding UTF8 $ks
    $incDir = Join-Path $RunRoot "logs\ops"
    New-Item -ItemType Directory -Force -Path $incDir | Out-Null
    $inc = Join-Path $incDir ("INCIDENT_QC_FAIL_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
    "QC_FAIL_KILL_SWITCH=1 ks=$ks qc=$($qc.FullName)" | Set-Content -Encoding UTF8 $inc
  } catch {}
     = 1_freeze_exit_code = 1  # EXIT_DEFERRED  # EXIT_DEFERRED_LINE
} else { } else { exit 0 }_freeze_exit_code = 0  # EXIT_DEFERRED }
      }
    }
  }

  # Fallback: if no QC found, keep original   # Fallback: if no QC found, keep original exit code_freeze_exit_code = code  # EXIT_DEFERRED
     = $code_freeze_exit_code = $code  # EXIT_DEFERRED  # EXIT_DEFERRED_LINE
} catch {
  "FREEZE_OK=0" | Add-Content -Encoding UTF8 -Path $out
  ("EXC=" + ($_.Exception.Message)) | Add-Content -Encoding UTF8 -Path $err
  ($_ | Out-String) | Add-Content -Encoding UTF8 -Path $err
     = 1_freeze_exit_code = 1  # EXIT_DEFERRED  # EXIT_DEFERRED_LINE
}


















# EXPECTANCY_GUARD_FINAL_V4 (always run guard + copy into backup + rebuild zip; then exit deferred code)
try {
  $iso2 = $IsoDayOverride
  if(Test-Path $out){
    $m = Select-String -Path $out -Pattern '^ISO_DAY_USED=' -ErrorAction SilentlyContinue | Select-Object -First 1
    if($m){ $iso2 = ($m.Line.Split('=')[1]).Trim() }
  }
  if([string]::IsNullOrWhiteSpace($iso2)){ $iso2 = (Get-Date).ToString('yyyy-MM-dd') }
  $ymd2 = $iso2.Replace('-','')

  # run guard
  $g = Join-Path $ProjectRoot 'tools\ops\EXPECTANCY_GUARD_REPORT_V1.ps1'
  if(Test-Path $g){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $g -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $iso2 -LookbackMinutes 0 -WarnCount 50 -FailCount 200 -KillOnFail 0 1>> $out 2>> $err
    ('EXPECTANCY_GUARD_EXIT=' + $LASTEXITCODE + ' isoday=' + $iso2) | Add-Content -Encoding UTF8 -Path $out
  } else {
    'EXPECTANCY_GUARD_MISSING=1' | Add-Content -Encoding UTF8 -Path $err
  }

  # copy into backup + rebuild zip
  $opsDir = Join-Path $RunRoot 'logs\ops'
  $anaDir = Join-Path $RunRoot 'logs\analytics'
  $bk = Get-ChildItem $opsDir -Directory -Filter ('FREEZE_BACKUP_' + $ymd2 + '_*') -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($bk){
    foreach($s in @(
      (Join-Path $opsDir ('EXPECTANCY_GUARD_' + $ymd2 + '.txt')),
      (Join-Path $opsDir ('EXPECTANCY_GUARD_' + $ymd2 + '.json')),
      (Join-Path $anaDir ('EXPECTANCY_GUARD_' + $ymd2 + '.txt')),
      (Join-Path $anaDir ('EXPECTANCY_GUARD_' + $ymd2 + '.json'))
    )){
      if(Test-Path $s){ Copy-Item $s (Join-Path $bk.FullName (Split-Path $s -Leaf)) -Force }
    }

    Get-ChildItem $bk.FullName -File -Filter ('FREEZE_TODAY_' + $ymd2 + '_*.zip') -ErrorAction SilentlyContinue |
      ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue }
    $zip2 = Join-Path $bk.FullName ('FREEZE_TODAY_' + $ymd2 + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.zip')
    # MINIMAL_EVIDENCE_ZIP_V2 (avoid huge/locked zips; only audit artifacts)
    $need = @(
      ('QC_{0}.txt' -f $ymd2),
      ('env_TBOT_SAFE_{0}.txt' -f $ymd2),
      ('CONFIG_GATES_{0}.txt' -f $ymd2),
      ('CONFIG_GATES_{0}.json' -f $ymd2),
      ('POLICY_SNAPSHOT_{0}.md' -f $ymd2),
      ('POLICY_SNAPSHOT_{0}.json' -f $ymd2),
      ('KPI_{0}.json' -f $ymd2),
      ('KPI_{0}.md' -f $ymd2),
      ('REALIZED_KPI_{0}.json' -f $ymd2),
      ('REALIZED_KPI_{0}.md' -f $ymd2),
      ('LEDGER_SIM_{0}.jsonl' -f $ymd2),
      ('RECON_SIM_{0}.json' -f $ymd2),
      ('EXPECTANCY_GUARD_{0}.txt' -f $ymd2),
      ('EXPECTANCY_GUARD_{0}.json' -f $ymd2)
    )
    $paths = @()
    foreach($n in $need){
      $pp = Join-Path $bk.FullName $n
      if(Test-Path $pp){ $paths += $pp }
    }
    if($paths -and $paths.Count -gt 0){ Compress-Archive -Path $paths -DestinationPath $zip2 -Force }
    ('EXPECTANCY_GUARD_COPIED=1 ymd=' + $ymd2 + ' zip=' + $zip2) | Add-Content -Encoding UTF8 -Path $out
  } else {
    ('EXPECTANCY_GUARD_COPIED=0 reason=NO_BACKUP ymd=' + $ymd2) | Add-Content -Encoding UTF8 -Path $out
  }
} catch {
  ('EXPECTANCY_GUARD_FINAL_EXC=' + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

# exit at very end (deferred)
if($null -eq $__freeze_exit_code){ $__freeze_exit_code = 0 }
('FREEZE_WRAPPER_EXIT=' + $__freeze_exit_code) | Add-Content -Encoding UTF8 -Path $out
exit $__freeze_exit_code

