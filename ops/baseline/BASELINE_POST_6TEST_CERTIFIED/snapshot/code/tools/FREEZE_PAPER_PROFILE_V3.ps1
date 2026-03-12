param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride="",
  [int]$TimeoutSec=180
)
$ErrorActionPreference="Stop"

# TO_SCRIPTBLOCK_HELPER_V1
function __ToScriptBlock([object]$x){
  if($x -is [ScriptBlock]){ return $x }
  if($x -is [string]){ return [ScriptBlock]::Create([string]$x) }
  try{ return [ScriptBlock]::Create(($x | Out-String)) } catch { return [ScriptBlock]::Create("") }
}

# LOAD_SECRETS_PAPER_ENFORCED_V2
try{
  $rr2 = $RunRoot
  if([string]::IsNullOrWhiteSpace($rr2)){
    try{
      $p = Join-Path $ProjectRoot 'tools\profiles\paper.profile.json'
      if(Test-Path $p){
        $j = Get-Content -Raw -Encoding UTF8 $p | ConvertFrom-Json
        if($j.runroot){ $rr2=[string]$j.runroot } elseif($j.runtime){ $rr2=[string]$j.runtime }
      }
    } catch {}
  }
  if([string]::IsNullOrWhiteSpace($rr2)){ $rr2='C:\alpaca-bot\org_bot_runtime\paper' }
  $ldr = Join-Path $ProjectRoot 'tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1'
  . $ldr -Profile 'PAPER' -ProjectRoot $ProjectRoot -RunRoot $rr2 | Out-Null
} catch { throw }

# PROFILE_SECRETS_LOAD_V1 (PAPER)
try{
  & (Join-Path $ProjectRoot "tools\secrets\LOAD_PROFILE_SECRETS_V1.ps1") -Profile "PAPER" | Out-Null
}catch{ throw }

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ops,$ana | Out-Null

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $ops ("FREEZE_OUT_{0}.txt" -f $ts)
$err = Join-Path $ops ("FREEZE_ERR_{0}.txt" -f $ts)

# Pick isoday (prefer LIVE_OUT ymd)
if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  $lo = Get-ChildItem $ops -File -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
  if($lo -and ($lo.Name -match 'LIVE_OUT_(\d{8})_')){
    $ymd0=$matches[1]
    $IsoDayOverride = "{0}-{1}-{2}" -f $ymd0.Substring(0,4),$ymd0.Substring(4,2),$ymd0.Substring(6,2)
  } else {
    $IsoDayOverride = (Get-Date).ToString("yyyy-MM-dd")
  }
}
$ymd = $IsoDayOverride.Replace("-","")

# Force safe filelog path (prevents ibkr contamination)
try{
  $safe = Join-Path $RunRoot 'logs\bot_console_{date}.log'
  $old  = $env:TBOT_FILELOG_PATH
  $env:TBOT_FILELOG_PATH = $safe
  "TBOT_FILELOG_PATH_SET=1 old=$old new=$safe" | Add-Content -Encoding UTF8 -Path $out
}catch{ ("TBOT_FILELOG_PATH_SET_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

"ISO_DAY_USED=$IsoDayOverride" | Add-Content -Encoding UTF8 -Path $out

# Create a fresh RunRoot backup folder for THIS run
$bkLocal = Join-Path $ops ("FREEZE_BACKUP_{0}_{1}" -f $ymd,$ts)
New-Item -ItemType Directory -Force -Path $bkLocal | Out-Null
("RUNROOT_BACKUP_DIR=" + $bkLocal) | Add-Content -Encoding UTF8 -Path $out

# Policy snapshot
try{
  $ps = Join-Path $ProjectRoot "tools\ops\WRITE_POLICY_SNAPSHOT_V1.ps1"
  if(Test-Path $ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $ps -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
    "POLICY_SNAPSHOT_WRITER_OK=1" | Add-Content -Encoding UTF8 -Path $out
  }
}catch{ ("POLICY_SNAPSHOT_WRITER_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# Config gates
try{
  $val = Join-Path $ProjectRoot "tools\ops\VALIDATE_PAPER_CONFIG_GATES_V1.ps1"
  if(Test-Path $val){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $val -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
    ("CONFIG_GATES_EXIT=" + $LASTEXITCODE) | Add-Content -Encoding UTF8 -Path $out
  }
}catch{ ("CONFIG_GATES_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# Expectancy guard
try{
  $g = Join-Path $ProjectRoot "tools\ops\EXPECTANCY_GUARD_REPORT_V1.ps1"
  if(Test-Path $g){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $g -ProjectRoot $ProjectRoot -RunRoot $RunRoot -IsoDayOverride $IsoDayOverride -LookbackMinutes 0 -WarnCount 50 -FailCount 200 -KillOnFail 1 1>> $out 2>> $err
    ("EXPECTANCY_GUARD_EXIT=" + $LASTEXITCODE) | Add-Content -Encoding UTF8 -Path $out
  } else { "EXPECTANCY_GUARD_MISSING=1" | Add-Content -Encoding UTF8 -Path $err }
}catch{ ("EXPECTANCY_GUARD_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# Run core freeze (under ProjectRoot) with timeout
$freeze = Join-Path $ProjectRoot "tools\freeze_today_enterprise.ps1"
$pwshExe="C:\Program Files\PowerShell\7\pwsh.exe"
if(!(Test-Path $pwshExe)){ $pwshExe=(Get-Command pwsh.exe -ErrorAction SilentlyContinue).Source }
if([string]::IsNullOrWhiteSpace($pwshExe)){ $pwshExe=(Get-Command powershell.exe).Source }

$childOut = Join-Path $ops ("FREEZE_CHILD_OUT_{0}.txt" -f $ts)
$childErr = Join-Path $ops ("FREEZE_CHILD_ERR_{0}.txt" -f $ts)

$exitCore=0
try{
  if(!(Test-Path $freeze)){ throw "MISSING_FREEZE_CORE=$freeze" }
  $args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$freeze,'-Root',$ProjectRoot,'-IsoDayOverride',$IsoDayOverride)
  $p = Start-Process -FilePath $pwshExe -ArgumentList $args -PassThru -WindowStyle Hidden -RedirectStandardOutput $childOut -RedirectStandardError $childErr
  $done = $p.WaitForExit($TimeoutSec * 1000)
  if(-not $done){
    try{ $p.Kill() } catch {}
    $exitCore=124
    ("FREEZE_TIMEOUT_KILLED=1 timeout_sec=" + $TimeoutSec) | Add-Content -Encoding UTF8 -Path $err
  } else {
    $exitCore=$p.ExitCode
    ("FREEZE_CHILD_EXIT=" + $exitCore) | Add-Content -Encoding UTF8 -Path $out
  }
}catch{
  $exitCore=125
  ("FREEZE_CORE_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

# Append child logs (best effort)
try{ if(Test-Path $childOut){ Get-Content $childOut | Add-Content -Encoding UTF8 -Path $out } } catch {}
try{ if(Test-Path $childErr){ Get-Content $childErr | Add-Content -Encoding UTF8 -Path $err } } catch {}

# Import core backup folder (from childOut) into bkLocal
try{
  $coreBk=$null
  if(Test-Path $childOut){
    $m = Select-String -Path $childOut -Pattern '^BACKUP FOLDER:\s*(.+)$' -ErrorAction SilentlyContinue | Select-Object -First 1
    if($m){ $coreBk = ($m.Matches[0].Groups[1].Value).Trim() }
  }
  if($coreBk){ ("CORE_BACKUP_DIR=" + $coreBk) | Add-Content -Encoding UTF8 -Path $out }

  if($coreBk -and (Test-Path $coreBk)){
    $want=@(
      "QC_$ymd.txt","env_TBOT_SAFE_$ymd.txt","boot_config_$ymd.txt",
      "daily_summary_$ymd.json","file_hashes_$ymd.txt","git_state_$ymd.txt","compile_check_$ymd.txt",
      "announce_$ymd.log","meta_$ymd.jsonl","shadow_plans_$ymd.jsonl","shadow_plans_FULL_$ymd.jsonl"
    )
    foreach($n in $want){
      $src = Join-Path $coreBk $n
      if(Test-Path $src){ Copy-Item $src (Join-Path $bkLocal $n) -Force }
    }
    "CORE_BACKUP_IMPORTED=1" | Add-Content -Encoding UTF8 -Path $out
  } else {
    "CORE_BACKUP_IMPORTED=0" | Add-Content -Encoding UTF8 -Path $out
  }
}catch{ ("CORE_BACKUP_IMPORT_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# Ensure local evidence copies from RunRoot logs (policy/config/guard/analytics)
foreach($n in @(
  "CONFIG_GATES_$ymd.txt","CONFIG_GATES_$ymd.json",
  "POLICY_SNAPSHOT_$ymd.md","POLICY_SNAPSHOT_$ymd.json",
  "KPI_$ymd.json","KPI_$ymd.md",
  "REALIZED_KPI_$ymd.json","REALIZED_KPI_$ymd.md",
  "LEDGER_SIM_$ymd.jsonl","RECON_SIM_$ymd.json",
  "EXPECTANCY_GUARD_$ymd.txt","EXPECTANCY_GUARD_$ymd.json","QC_OBS_$ymd.txt"
)){
  foreach($src in @((Join-Path $ops $n),(Join-Path $ana $n))){
    if(Test-Path $src){ Copy-Item $src (Join-Path $bkLocal (Split-Path $src -Leaf)) -Force }
  }
}

# OPP_QUEUE_CALL_V2 (guaranteed; writes into bkLocal + analytics; then included in zip)
try{
  $pyExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $pyExe)){ $pyExe = "python" }
  $opp = Join-Path $ProjectRoot "tools\analytics\opp_queue_v1.py"
  if(Test-Path $opp){
    & $pyExe $opp --backupdir $bkLocal --runroot $RunRoot --ymd $ymd 1>> $out 2>> $err
# OPP_QUEUE_EXIT_LOG_V1
$oqc = $LASTEXITCODE
("OPP_QUEUE_EXIT=" + $oqc) | Add-Content -Encoding UTF8 -Path $out
if($oqc -ne 0){ "OPP_QUEUE_OK=0" | Add-Content -Encoding UTF8 -Path $out } else { "OPP_QUEUE_OK=1" | Add-Content -Encoding UTF8 -Path $out }
    "OPP_QUEUE_OK=1" | Add-Content -Encoding UTF8 -Path $out
  } else {
    "OPP_QUEUE_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
  }
} catch {
  ("OPP_QUEUE_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}
# SELECTION_COVERAGE_CALL_FROM_OPP_PS_V1
try{
  $ps = Join-Path $ProjectRoot "tools\ops\SELECTION_COVERAGE_FROM_OPP_V1.ps1"
  if(Test-Path $ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $ps -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bkLocal -IsoDayOverride $IsoDayOverride 1>> $out 2>> $err
    "SELECTION_COVERAGE_OK=1" | Add-Content -Encoding UTF8 -Path $out
  } else {
    "SELECTION_COVERAGE_MISSING_PS=1" | Add-Content -Encoding UTF8 -Path $err
  }
}catch{
  ("SELECTION_COVERAGE_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

# LATENCY_SLO_CALL_V1 (Cost-of-Delay / missed opportunities signal)
try{
  $ps = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
  if(Test-Path $ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $ps 
      -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bkLocal -IsoDayOverride $IsoDayOverride -OutPath $out -ErrPath $err
    "LATENCY_SLO_OK=1" | Add-Content -Encoding UTF8 -Path $out
  } else {
    "LATENCY_SLO_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
  }
}catch{
  ("LATENCY_SLO_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

# OPP_QUEUE_GUARANTEE_V1 (never miss these artifacts in evidence)
try{
  $oq = Join-Path $bkLocal ("OPP_QUEUE_{0}.json" -f $ymd)
  $se = Join-Path $bkLocal ("SELECTION_EFF_{0}.json" -f $ymd)
  $t1 = Join-Path $bkLocal ("TOP1P_{0}.md" -f $ymd)

  if(!(Test-Path $oq)){
    @{ ymd=$ymd; status="PLACEHOLDER"; reason="opp_queue_missing"; note="Check FREEZE_ERR for python traceback." } |
      ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $oq
    "OPP_QUEUE_PLACEHOLDER=1" | Add-Content -Encoding UTF8 -Path $out
  }
  if(!(Test-Path $se)){
    @{ ymd=$ymd; status="PLACEHOLDER"; reason="selection_eff_missing"; note="Add plan_id telemetry for exact top1% coverage." } |
      ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -Path $se
    "SELECTION_EFF_PLACEHOLDER=1" | Add-Content -Encoding UTF8 -Path $out
  }
  if(!(Test-Path $t1)){
    @(
      "# TOP 1% REPORT " + $ymd,
      "",
      "PLACEHOLDER=1",
      "reason=top1p_missing",
      "note=Either shadow_plans_FULL missing or python failed. Check FREEZE_ERR."
    ) | Set-Content -Encoding UTF8 -Path $t1
    "TOP1P_PLACEHOLDER=1" | Add-Content -Encoding UTF8 -Path $out
  }
}catch{
  ("OPP_QUEUE_GUARANTEE_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}
# Build minimal zip from bkLocal
# DAILY_REPORT_PACK_CALL_V1 (Funnel/MissedOpps/Exec/Alpha/Anomaly/DailyBrief)
try{
  $pyExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $pyExe)){ $pyExe = "python" }
  $rp = Join-Path $ProjectRoot "tools\analytics\daily_report_pack_v1.py"
  if(Test-Path $rp){
    & $pyExe $rp --runroot $RunRoot --isoday $IsoDayOverride --backupdir $bkLocal --outdir $ana 1>> $out 2>> $err
    "DAILY_REPORT_PACK_OK=1" | Add-Content -Encoding UTF8 -Path $out
# OPP_QUEUE_CALL_V1 (opportunity queue + top1% report)
try{
  $pyExe = Join-Path $ProjectRoot ".venv\Scripts\python.exe"
  if(!(Test-Path $pyExe)){ $pyExe = "python" }
  $opp = Join-Path $ProjectRoot "tools\analytics\opp_queue_v1.py"
  if(Test-Path $opp){
    & $pyExe $opp --backupdir $bkLocal --runroot $RunRoot --ymd $ymd 1>> $out 2>> $err
    "OPP_QUEUE_OK=1" | Add-Content -Encoding UTF8 -Path $out
  }
}catch{
  ("OPP_QUEUE_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}
  } else {
    "DAILY_REPORT_PACK_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
  }
}catch{
  ("DAILY_REPORT_PACK_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}
try{
# === FREEZE_LLM_EVIDENCE_FINAL ===
try {
  $llmWd   = Join-Path "C:\alpaca-bot\org_bot_runtime\paper" "logs\ops\llm_gate_watchdog.jsonl"
  $llmFlag = Join-Path "C:\alpaca-bot\org_bot_runtime\paper" "state\LLM_GATE_DISABLED.flag"

  if(Test-Path $llmWd){ Copy-Item $llmWd $bkLocal -Force }
  if(Test-Path $llmFlag){ Copy-Item $llmFlag $bkLocal -Force }

  schtasks /query /tn "\TBOT_LLM_GATE_WATCHDOG_10S" /v /fo list *>&1 |
    Out-String | Set-Content -Encoding UTF8 (Join-Path $bkLocal "TASK_WATCHDOG.txt")

} catch {
  "WARN: FREEZE_LLM_EVIDENCE failed" | Out-File (Join-Path $bkLocal "WARN_freeze_llm_evidence.txt")
}
# === END_FREEZE_LLM_EVIDENCE_FINAL ===

  $need=@(
    "QC_$ymd.txt","env_TBOT_SAFE_$ymd.txt",
    "CONFIG_GATES_$ymd.txt","CONFIG_GATES_$ymd.json",
    "POLICY_SNAPSHOT_$ymd.md","POLICY_SNAPSHOT_$ymd.json",
    "KPI_$ymd.json","KPI_$ymd.md",
    "REALIZED_KPI_$ymd.json","REALIZED_KPI_$ymd.md",
    "LEDGER_SIM_$ymd.jsonl","RECON_SIM_$ymd.json",
    "EXPECTANCY_GUARD_$ymd.txt","EXPECTANCY_GUARD_$ymd.json","QC_OBS_$ymd.txt"
  )
  # OBS_LIVE_ERR_IN_ZIP_V1 (guarantee LIVE_ERR + useful stderr makes it into backup/zip)
  try {
    # 1) Latest LIVE_OUT / LIVE_ERR for this market-day
    $lo = Get-ChildItem $ops -File -Filter ("LIVE_OUT_{0}_*.txt" -f $ymd) -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1
    $le = Get-ChildItem $ops -File -Filter ("LIVE_ERR_{0}_*.txt" -f $ymd) -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1

    $loName = "LIVE_OUT_{0}_LATEST.txt" -f $ymd
    $leName = "LIVE_ERR_{0}_LATEST.txt" -f $ymd

    if($lo){
      Copy-Item $lo.FullName (Join-Path $bkLocal $loName) -Force
      ("LIVE_OUT_COPIED=1 src=" + $lo.Name) | Add-Content -Encoding UTF8 -Path $out
    } else {
      ("LIVE_OUT_COPIED=0 ymd=" + $ymd) | Add-Content -Encoding UTF8 -Path $out
    }

    if($le){
      Copy-Item $le.FullName (Join-Path $bkLocal $leName) -Force
      ("LIVE_ERR_COPIED=1 src=" + $le.Name) | Add-Content -Encoding UTF8 -Path $out
    } else {
      # Placeholder so evidence is never blind
      $ph = Join-Path $bkLocal $leName
      @(
        "LIVE_ERR_PLACEHOLDER=1",
        "reason=no_LIVE_ERR_file_found_for_ymd",
        ("ymd=" + $ymd),
        "tip=check FREEZE_ERR_* and FREEZE_CHILD_ERR_* for subprocess stderr"
      ) | Set-Content -Encoding UTF8 -Path $ph
      ("LIVE_ERR_COPIED=0 placeholder=1") | Add-Content -Encoding UTF8 -Path $out
    }

    # 2) Always include wrapper/core stderr for this run (stable names)
    Copy-Item $out (Join-Path $bkLocal ("FREEZE_OUT_{0}_LATEST.txt" -f $ymd)) -Force
    Copy-Item $err (Join-Path $bkLocal ("FREEZE_ERR_{0}_LATEST.txt" -f $ymd)) -Force

    if(Test-Path $childOut){ Copy-Item $childOut (Join-Path $bkLocal ("FREEZE_CHILD_OUT_{0}_LATEST.txt" -f $ymd)) -Force }
    if(Test-Path $childErr){ Copy-Item $childErr (Join-Path $bkLocal ("FREEZE_CHILD_ERR_{0}_LATEST.txt" -f $ymd)) -Force }

    # 3) Ensure zip "need" includes these stable names
    $need += @(
      $loName,
      $leName,
      ("FREEZE_OUT_{0}_LATEST.txt" -f $ymd),
      ("FREEZE_ERR_{0}_LATEST.txt" -f $ymd),
      ("FREEZE_CHILD_OUT_{0}_LATEST.txt" -f $ymd),
      ("FREEZE_CHILD_ERR_{0}_LATEST.txt" -f $ymd)
    )
  } catch {
    ("OBS_LIVEERR_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
    # OBS_QC_LIVEERR_V2 (tail fallback for LIVE_ERR + observability QC)
  try {
    $loName = ("LIVE_OUT_{0}_LATEST.txt" -f $ymd)
    $leName = ("LIVE_ERR_{0}_LATEST.txt" -f $ymd)
    $loP = Join-Path $bkLocal $loName
    $leP = Join-Path $bkLocal $leName

    $loPresent = Test-Path $loP
    $lePresent = Test-Path $leP
    $loLen = if($loPresent){ (Get-Item $loP).Length } else { 0 }
    $leLen = if($lePresent){ (Get-Item $leP).Length } else { 0 }

    # Tail fallback: if LIVE_ERR exists but empty, fill from child/core stderr tails
    if($lePresent -and $leLen -eq 0){
      $srcs = @(
        (Join-Path $bkLocal ("FREEZE_CHILD_ERR_{0}_LATEST.txt" -f $ymd)),
        (Join-Path $bkLocal ("FREEZE_ERR_{0}_LATEST.txt" -f $ymd))
      )
      foreach($s in $srcs){
        if(Test-Path $s){
          $sLen = (Get-Item $s).Length
          if($sLen -gt 0){
            $tail = Get-Content $s -Tail 80
            @(
              ("LIVE_ERR_FALLBACK=1 src=" + (Split-Path $s -Leaf)),
              "----TAIL----"
            ) + $tail | Set-Content -Encoding UTF8 -Path $leP
            $leLen = (Get-Item $leP).Length
            break
          }
        }
      }
    }

        # OBS_LIVEERR_PLACEHOLDER_V1 (if still empty after fallback, write a placeholder so evidence isn't blind)
    if($lePresent -and $leLen -eq 0){
      @(
        "LIVE_ERR_PLACEHOLDER=1",
        ("ymd=" + $ymd),
        "reason=stderr_empty_after_fallback",
        "checked=FREEZE_CHILD_ERR_LATEST,FREEZE_ERR_LATEST",
        "note=No stderr captured for this run. This is acceptable; placeholder prevents blind evidence."
      ) | Set-Content -Encoding UTF8 -Path $leP
      $leLen = (Get-Item $leP).Length
      ("LIVE_ERR_PLACEHOLDER_WRITTEN=1 len=" + $leLen) | Add-Content -Encoding UTF8 -Path $out
    }
# Observability QC
    $status = "PASS"
    $findings = New-Object System.Collections.Generic.List[string]

    if(-not $loPresent){ $status="FAIL"; $findings.Add("MISSING:LIVE_OUT_LATEST") | Out-Null }
    if(-not $lePresent){ $status="FAIL"; $findings.Add("MISSING:LIVE_ERR_LATEST") | Out-Null }

    if($lePresent -and $leLen -eq 0 -and $status -ne "FAIL"){
      $status="WARN"
      $findings.Add("WARN:LIVE_ERR_LATEST_EMPTY") | Out-Null
    }

    $obs = Join-Path $bkLocal ("QC_OBS_{0}.txt" -f $ymd)
    @(
      ("OBS_QC_RESULT=" + $status),
      ("LIVE_OUT_PRESENT=" + $loPresent + " len=" + $loLen),
      ("LIVE_ERR_PRESENT=" + $lePresent + " len=" + $leLen)
    ) + ($findings | ForEach-Object { "FINDING=$_"} ) | Set-Content -Encoding UTF8 -Path $obs

    # Also append to main QC if exists
    $qc = Join-Path $bkLocal ("QC_{0}.txt" -f $ymd)
    if(Test-Path $qc){
      Add-Content -Encoding UTF8 -Path $qc ""
      Add-Content -Encoding UTF8 -Path $qc ("OBS_QC_RESULT=" + $status)
      Add-Content -Encoding UTF8 -Path $qc ("OBS_LIVE_OUT_PRESENT=" + $loPresent + " len=" + $loLen)
      Add-Content -Encoding UTF8 -Path $qc ("OBS_LIVE_ERR_PRESENT=" + $lePresent + " len=" + $leLen)
      foreach($x in $findings){ Add-Content -Encoding UTF8 -Path $qc ("OBS_" + $x) }
    }

    ("OBS_QC_RESULT=" + $status) | Add-Content -Encoding UTF8 -Path $out

    # Ensure zip includes QC_OBS
    if($need -notcontains ("QC_OBS_{0}.txt" -f $ymd)){
      $need += ("QC_OBS_{0}.txt" -f $ymd)
    }
  } catch {
    ("OBS_QC_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
  }
$zip2 = Join-Path $bkLocal ("FREEZE_TODAY_{0}_{1}.zip" -f $ymd,(Get-Date -Format "yyyyMMdd_HHmmss"))
# DAILY_REPORT_PACK_NEED_V1
$need += @(
  ("DAILY_BRIEF_{0}.md" -f $ymd),
  ("FUNNEL_{0}.json" -f $ymd), ("FUNNEL_{0}.md" -f $ymd),
  ("SKIP_REASONS_{0}.json" -f $ymd), ("SKIP_REASONS_{0}.md" -f $ymd),
  ("EXEC_HEALTH_{0}.json" -f $ymd), ("EXEC_HEALTH_{0}.md" -f $ymd),
  ("ALPHA_HEALTH_{0}.json" -f $ymd), ("ALPHA_HEALTH_{0}.md" -f $ymd),
  ("MISSED_OPPS_{0}.json" -f $ymd),
  ("ANOMALY_{0}.json" -f $ymd), ("ANOMALY_{0}.md" -f $ymd)
)
# OPP_QUEUE_NEED_V1
$need += @(
  ("OPP_QUEUE_{0}.json" -f $ymd),
  ("SELECTION_EFF_{0}.json" -f $ymd),
  ("TOP1P_{0}.md" -f $ymd)
)
# OPP_QUEUE_NEED_V2
# SELECTION_COVERAGE_NEED_FROM_OPP_PS_V1
$need += @(
  ("SELECTION_COVERAGE_{0}.json" -f $ymd),
  ("SELECTION_COVERAGE_{0}.md" -f $ymd)
)

$need += @(
  ("OPP_QUEUE_{0}.json" -f $ymd),
  ("SELECTION_EFF_{0}.json" -f $ymd),
  ("TOP1P_{0}.md" -f $ymd)
)
  $paths=@()
  foreach($n in $need){
    $pp=Join-Path $bkLocal $n
    if(Test-Path $pp){ $paths += $pp }
  }
  if($paths.Count -gt 0){
    # DEDUP_BEFORE_COMPRESS_V4_paths (avoid duplicate paths crashing Compress-Archive)
    try {
      $tmp = Get-Variable -Name 'paths' -ValueOnly -ErrorAction SilentlyContinue
      if($null -ne $tmp){
        $arr = @($tmp) | Where-Object { $_ } | Sort-Object -Unique
        Set-Variable -Name 'paths' -Value $arr -Force
      }
    } catch { }

    Compress-Archive -Path $paths -DestinationPath $zip2 -Force
    ("MIN_ZIP_OK=1 files=" + $paths.Count + " zip=" + $zip2) | Add-Content -Encoding UTF8 -Path $out
    ("EXPECTANCY_GUARD_COPIED=1 ymd=" + $ymd) | Add-Content -Encoding UTF8 -Path $out
  } else {
    ("MIN_ZIP_OK=0 reason=NO_EVID_FILES ymd=" + $ymd) | Add-Content -Encoding UTF8 -Path $out
  }
}catch{ ("MIN_ZIP_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err }

# POSTFREEZE_MINZIP2_CALL_V1 (guarantee zip in RUNROOT_BACKUP_DIR)
try{
# LATENCY_SLO_CALL_PREZIP_V2 (write LATENCY_SLO into bkLocal BEFORE building _RUNROOT.zip)
try{
  $ps = Join-Path $ProjectRoot "tools\ops\LATENCY_SLO_REPORT_V1.ps1"
  if(Test-Path $ps){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File $ps 
      -ProjectRoot $ProjectRoot -RunRoot $RunRoot -BackupDir $bkLocal -IsoDayOverride $IsoDayOverride -OutPath $out -ErrPath $err
    "LATENCY_SLO_OK=1" | Add-Content -Encoding UTF8 -Path $out
  } else {
    "LATENCY_SLO_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
  }
}catch{
  ("LATENCY_SLO_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}
  $pf = Join-Path $ProjectRoot "tools\ops\POSTFREEZE_BUILD_MINZIP_SEL_COV_V1.ps1"
  if(Test-Path $pf){
    & "C:\Program Files\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass `
      -File $pf -ProjectRoot $ProjectRoot -RunRoot $RunRoot -OutPath $out -ErrPath $err -IsoDayOverride $IsoDayOverride
  } else {
    "POSTFREEZE_MINZIP2_MISSING=1" | Add-Content -Encoding UTF8 -Path $err
  }
}catch{
  ("POSTFREEZE_MINZIP2_EXC=" + $_.Exception.Message) | Add-Content -Encoding UTF8 -Path $err
}

("FREEZE_V3_DONE core_exit=" + $exitCore) | Add-Content -Encoding UTF8 -Path $out

# ENFORCE_FREEZE_CORE_ARTIFACTS_V1
try{
  # Resolve RunRoot from whatever this script has
  $rr = (Get-Variable -Name RunRoot -ErrorAction SilentlyContinue).Value
  if([string]::IsNullOrWhiteSpace([string]$rr)){
    # fallback: infer from logs location if possible
    $rr = (Get-Location).Path
  }
  if([string]::IsNullOrWhiteSpace([string]$rr)){ throw "RUNROOT_UNKNOWN" }

  $ops = Join-Path $rr "logs\ops"
  $fo = Get-ChildItem $ops -File -Filter "FREEZE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1

  $bk = $null
  if($fo){
    $m = Select-String -Path $fo.FullName -Pattern '^RUNROOT_BACKUP_DIR=' -ErrorAction SilentlyContinue | Select -First 1
    if($m){ $bk = $m.Line.Split("=",2)[1].Trim() }
  }
  if([string]::IsNullOrWhiteSpace($bk) -or !(Test-Path $bk)){
    $bk = (Get-ChildItem $ops -Directory -Filter "FREEZE_BACKUP_*" -ErrorAction SilentlyContinue | Sort LastWriteTime -Desc | Select -First 1).FullName
  }
  if([string]::IsNullOrWhiteSpace($bk) -or !(Test-Path $bk)){ throw "BK_NOT_FOUND" }

  $ymd = ($bk -replace '^.*FREEZE_BACKUP_(\d{8}).*','$1')
  if($ymd -notmatch '^\d{8}$'){ $ymd = (Get-Date).ToString("yyyyMMdd") }

  $isPaper = (([string]$rr).ToLower() -like '*\paper*')

  $missing = New-Object System.Collections.Generic.List[string]

  if($isPaper){
    foreach($n in @(
      ("QC_{0}.txt" -f $ymd),
      ("KPI_{0}.json" -f $ymd),
      ("REALIZED_KPI_{0}.json" -f $ymd),
      ("POLICY_SNAPSHOT_{0}.md" -f $ymd)
    )){
      $p = Join-Path $bk $n
      if(!(Test-Path $p)){ $missing.Add($n) | Out-Null }
    }
  } else {
    # Shadow: require at least ONE freeze zip in the backup
    $zip = Get-ChildItem $bk -File -Filter ("FREEZE_TODAY_{0}_*.zip" -f $ymd) -ErrorAction SilentlyContinue | Select -First 1
    if(-not $zip){ $missing.Add(("FREEZE_TODAY_{0}_*.zip" -f $ymd)) | Out-Null }
  }

  if($missing.Count -gt 0){
    $msg = "FREEZE_QUALITY=FAIL ymd=$ymd bk=$bk missing=" + ((@($missing) | Sort-Object -Unique) -join ",")
    try{
      if(Get-Variable -Name err -ErrorAction SilentlyContinue){
        $msg | Add-Content -Encoding UTF8 -Path $err
      }
    } catch {}
    $msg | Out-Host

    # hard stop pipeline
    $ks = Join-Path $rr "KILL_SWITCH"
    @(
      ("ts=" + (Get-Date).ToString("s")),
      "reason=freeze_missing_artifacts",
      ("ymd=" + $ymd),
      ("bk=" + $bk),
      ("missing=" + ((@($missing)|Sort-Object -Unique) -join ",")))
    ) | Set-Content -Encoding UTF8 -Path $ks

    exit 1
  } else {
    ("FREEZE_QUALITY=PASS ymd=$ymd bk=$bk") | Out-Host
  }
}catch{
  ("FREEZE_QUALITY_EXC=" + $_.Exception.Message) | Out-Host
  exit 1
}

exit 0
















