# tools\WEEK2_ONECLICK.ps1  (V2)
# Week2 One-File Gate + Checks (NO python changes)
# Safe boundaries: kills ONLY project venv python whose CommandLine contains tbot.main

[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [ValidateSet("SetupAndCheck","StartOps","StartResearch","Status","Report","Stop","Tasks","Disable0630","Enable0630","MetaStats")]
  [string]$Cmd = "SetupAndCheck",

  [switch]$Disable0630,
  [switch]$Enable0630,
  [switch]$NoTaskCheck,
  [switch]$Force,

  [int]$TotalDaily = 120,
  [int]$CooldownSec = 45,
  [int]$MaxPerSymbol = 60,
  [string]$Symbols = "SPY,QQQ,NVDA",

  [double]$ShadowRiskUsd = 25.0,
  [double]$GateMaxRiskUsd = 500.0,

  [int]$MaxBootsPerDay = 3,
  [int]$ResearchMinutes = 5,

  # hard stop before pre-close safety task (12:58:30 PT)
  [int]$HardStop_HH = 12,
  [int]$HardStop_MM = 58,
  [int]$HardStop_SS = 15
)

$ErrorActionPreference="Stop"

# ----- Paths -----
$ROOT = Split-Path -Parent $PSScriptRoot
$PY     = Join-Path $ROOT ".venv\Scripts\python.exe"
$META   = Join-Path $ROOT "logs\meta.jsonl"
$SHADOW = Join-Path $ROOT "logs\shadow_plans.jsonl"
$OPS    = Join-Path $ROOT "logs\ops"
$LOCKD  = Join-Path $ROOT "logs\locks"
New-Item -ItemType Directory -Force -Path $OPS,$LOCKD | Out-Null

# ----- Timezone (PT) -----
$TZ = [TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
function Now-PT { [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $TZ) }

# Robust meta ts parse:
# - if ts has Z or +/-HH:MM => DateTimeOffset parse + convert to PT
# - else assume ts is already PT local clock
function Parse-MetaTsPT([string]$ts){
  $hasOffset = ($ts -match '(Z|[+-]\d{2}:\d{2})$')
  if($hasOffset){
    $dto = [DateTimeOffset]::Parse($ts)
    return [TimeZoneInfo]::ConvertTime($dto, $TZ)
  } else {
    $dt = [DateTime]::Parse($ts)
    $u  = [DateTime]::SpecifyKind($dt,[DateTimeKind]::Unspecified)
    $off= $TZ.GetUtcOffset($u)
    return [DateTimeOffset]::new($u,$off)
  }
}

# ----- Session + buckets (40/40/20 across 06:30–13:00 PT) -----
function Session-Bounds([datetimeoffset]$nowPt){
  $d=$nowPt.Date; $o=$nowPt.Offset
  $s=[datetimeoffset]::new($d.Year,$d.Month,$d.Day, 6,30,0,$o)
  $e=[datetimeoffset]::new($d.Year,$d.Month,$d.Day,13, 0,0,$o)
  $hs=[datetimeoffset]::new($d.Year,$d.Month,$d.Day,$HardStop_HH,$HardStop_MM,$HardStop_SS,$o)
  return @{ start=$s; end=$e; hardStop=$hs }
}
function Bucket-Bounds([datetimeoffset]$nowPt){
  $sb=Session-Bounds $nowPt
  $s=$sb.start; $e=$sb.end
  $total=($e-$s).TotalSeconds
  $b0e=$s.AddSeconds([Math]::Round($total*0.40))
  $b1e=$b0e.AddSeconds([Math]::Round($total*0.40))
  return @{ b0s=$s; b0e=$b0e; b1s=$b0e; b1e=$b1e; b2s=$b1e; b2e=$e }
}
function Bucket-Id([datetimeoffset]$tPt){
  $bb=Bucket-Bounds $tPt
  if($tPt -lt $bb.b0s){ return -1 }
  if($tPt -ge $bb.b0s -and $tPt -lt $bb.b0e){ return 0 }
  if($tPt -ge $bb.b1s -and $tPt -lt $bb.b1e){ return 1 }
  if($tPt -ge $bb.b2s -and $tPt -lt $bb.b2e){ return 2 }
  return 99
}
function Bucket-Quota([int]$idx){
  if($idx -eq 0){ return [Math]::Ceiling($TotalDaily*0.40) }
  if($idx -eq 1){ return [Math]::Ceiling($TotalDaily*0.40) }
  if($idx -eq 2){ return [Math]::Ceiling($TotalDaily*0.20) }
  return 0
}

# ----- Wrapper lock -----
$global:LockHandle=$null
function Acquire-Lock{
  $lf=Join-Path $LOCKD "WEEK2_GATE_WRAPPER.lock"
  try{
    $fs=[System.IO.FileStream]::new($lf,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    $global:LockHandle=$fs
    $msg="pid=$PID start="+(Get-Date).ToString("s")
    $b=[Text.Encoding]::UTF8.GetBytes($msg)
    $fs.SetLength(0); $fs.Write($b,0,$b.Length); $fs.Flush()
    return $true
  } catch { return $false }
}
function Release-Lock{ if($global:LockHandle){ try{$global:LockHandle.Dispose()}catch{}; $global:LockHandle=$null } }

# ----- Project-only TBOT processes -----
function Get-TbotProcs{
  if(-not (Test-Path $PY)){ return @() }
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $PY -and ($_.CommandLine -like "*-m tbot.main*" -or $_.CommandLine -like "*tbot.main*") } |
    Select-Object ProcessId,CommandLine
}
function Stop-TbotAll{
  $ps=@(Get-TbotProcs)
  foreach($p in $ps){
    try{ Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }
  return $ps.Count
}

# ----- State (restart-safe) -----
function State-Path([datetimeoffset]$nowPt){
  Join-Path $OPS ("gate_state_{0}.json" -f $nowPt.ToString("yyyyMMdd"))
}
function New-State([datetimeoffset]$nowPt){
  @{
    day=$nowPt.ToString("yyyy-MM-dd")
    tz="PT"
    meta_pos=0
    accepted_total=0
    per_symbol=[pscustomobject]@{}
    per_bucket=@(0,0,0)
    run_ids=@()
    boots_today=0
    audit_ok=$true
    audit_notes=@()
    kill_tripped=$false
    kill_reason=$null
    last_accept_ts=$null
  }
}
function Load-State([datetimeoffset]$nowPt){
  $p=State-Path $nowPt
  if(Test-Path $p){ try{ return (Get-Content $p -Raw | ConvertFrom-Json) } catch {} }
  return (New-State $nowPt)
}
function Save-State($st,[datetimeoffset]$nowPt){ ($st | ConvertTo-Json -Depth 12) | Set-Content -Encoding UTF8 (State-Path $nowPt) }

# ----- Kill switch -----
function Is-FakePlan($payload){
  if(-not $payload){ return $false }
  try{
    $r=[string]$payload.reason
    if($r -match "forced_signal_test"){ return $true }
    $e=[double]$payload.entry; $s=[double]$payload.stop; $t=[double]$payload.tp
    if([Math]::Abs($e-100.0)-lt 0.0001 -and [Math]::Abs($s-99.0)-lt 0.0001 -and [Math]::Abs($t-102.0)-lt 0.0001){ return $true }
  } catch {}
  return $false
}

# ----- Meta incremental reader -----
function Read-NewMetaLines([ref]$st){
  if(-not (Test-Path $META)){ return @() }
  $enc=[Text.Encoding]::UTF8
  $pos=[int64]$st.Value.meta_pos
  $len=(Get-Item $META).Length
  if($pos -gt $len){ $pos=0; $st.Value.meta_pos=0 }
  if($pos -eq $len){ return @() }

  $fs=[IO.FileStream]::new($META,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
  $sr=$null
  try{
    $fs.Seek($pos,[IO.SeekOrigin]::Begin) | Out-Null
    $sr=[IO.StreamReader]::new($fs,$enc,$true,4096,$true)
    $text=$sr.ReadToEnd()
    $bytesRead=$fs.Position-$pos
  } finally {
    try{ if($sr){$sr.Dispose()} } catch {}
    try{ $fs.Dispose() } catch {}
  }

  if(-not $text){ return @() }
  $endsWithNl=$text.EndsWith("`n") -or $text.EndsWith("`r`n")
  $lines=$text -split "`r?`n"
  if(-not $endsWithNl){
    $partial=$lines[-1]
    if($lines.Count -gt 1){ $lines=$lines[0..($lines.Count-2)] } else { $lines=@() }
    $bytesRead=$bytesRead - $enc.GetByteCount($partial)
  }
  $st.Value.meta_pos = $st.Value.meta_pos + $bytesRead
  return $lines | Where-Object { $_ -and $_.Trim().Length -gt 0 }
}

function Apply-MetaLine([ref]$st,[string]$line,[datetimeoffset]$nowPt){
  $today=$nowPt.Date
  try{ $j=$line | ConvertFrom-Json } catch { return }
  if(-not $j.kind -or -not $j.ts){ return }

  $tPt=Parse-MetaTsPT ([string]$j.ts)
  if($tPt.Date -ne $today){ return }

  $kind=[string]$j.kind

  if($kind -eq "boot"){
    $rid=[string]$j.run_id
    if($rid -and -not ($st.Value.run_ids -contains $rid)){ $st.Value.run_ids += $rid }
    $st.Value.boots_today = @($st.Value.run_ids).Count
    if([int]$st.Value.boots_today -gt $MaxBootsPerDay){
      $st.Value.audit_ok=$false
      if(-not ($st.Value.audit_notes -contains "boots_today_gt_${MaxBootsPerDay}")){ $st.Value.audit_notes += "boots_today_gt_${MaxBootsPerDay}" }
    }
    return
  }

  # Kill-switch fires on plan too
  if($kind -eq "shadow_plan"){
    if(Is-FakePlan $j.payload){
      $st.Value.kill_tripped=$true
      $st.Value.kill_reason="fake_price_detected"
    }
    return
  }

  # COUNT ONLY shadow_accept (prevents double-count)
  if($kind -ne "shadow_accept"){ return }

  $p=$j.payload
  if(Is-FakePlan $p){
    $st.Value.kill_tripped=$true
    $st.Value.kill_reason="fake_price_detected"
    return
  }

  $st.Value.accepted_total=[int]$st.Value.accepted_total + 1
  $sym=[string]$p.symbol
  if($sym){
    if(-not ($st.Value.per_symbol.PSObject.Properties.Name -contains $sym)){
      $st.Value.per_symbol | Add-Member -NotePropertyName $sym -NotePropertyValue 0 -Force
    }
    $st.Value.per_symbol.$sym=[int]$st.Value.per_symbol.$sym + 1
  }

  $bid=Bucket-Id $tPt
  if($bid -ge 0 -and $bid -le 2){
    $arr=@($st.Value.per_bucket)
    $arr[$bid]=[int]$arr[$bid] + 1
    $st.Value.per_bucket=$arr
  }

  $st.Value.last_accept_ts=$tPt.ToString("s")
}

function Rebuild-FromMeta([ref]$st,[datetimeoffset]$nowPt){
  if(-not (Test-Path $META)){ throw "META missing: $META" }
  $st.Value.meta_pos=0
  $st.Value.accepted_total=0
  $st.Value.per_symbol=[pscustomobject]@{}
  $st.Value.per_bucket=@(0,0,0)
  $st.Value.run_ids=@()
  $st.Value.boots_today=0
  $st.Value.audit_ok=$true
  $st.Value.audit_notes=@()
  $st.Value.kill_tripped=$false
  $st.Value.kill_reason=$null
  $st.Value.last_accept_ts=$null

  Get-Content $META -ReadCount 4000 | ForEach-Object {
    foreach($ln in $_){ if($ln){ Apply-MetaLine $st $ln $nowPt } }
  }
  $st.Value.meta_pos=(Get-Item $META).Length
}

function Start-Tbot([string[]]$syms,[int]$runMax,[int]$cool,[string]$out,[string]$err){
  $symArg=($syms -join ",")
  $args=@(
    "-u","-m","tbot.main",
    "--iters","999999",
    "--sleep","0.25",
    "--symbols",$symArg,
    "--shadow","1",
    "--shadow_path",$SHADOW,
    "--shadow_risk_usd","$ShadowRiskUsd",
    "--gate_min_rr","1.0",
    "--gate_min_conf","0.0",
    "--gate_cooldown_sec","$cool",
    "--gate_max_plans_per_day","$runMax",
    "--gate_max_risk_usd","$GateMaxRiskUsd"
  )
  Start-Process -FilePath $PY -WorkingDirectory $ROOT -ArgumentList $args -PassThru -NoNewWindow `
    -RedirectStandardOutput $out -RedirectStandardError $err
}

function Print-Report($st,[datetimeoffset]$nowPt){
  $sb=Session-Bounds $nowPt
  $bb=Bucket-Bounds $nowPt
  $bid=Bucket-Id $nowPt
  Write-Host ""
  Write-Host ("PT_NOW=" + $nowPt.ToString("yyyy-MM-dd HH:mm:ss zzz") + " bucket=" + $bid)
  Write-Host ("SESSION=06:30–13:00 HARD_STOP=" + $sb.hardStop.ToString("HH:mm:ss"))
  Write-Host ("BUCKET_ENDS B0e=" + $bb.b0e.ToString("HH:mm") + " B1e=" + $bb.b1e.ToString("HH:mm"))
  Write-Host ("TOTAL_ACCEPTED=" + $st.accepted_total + "/" + $TotalDaily)
  Write-Host ("BUCKETS B0=" + $st.per_bucket[0] + " B1=" + $st.per_bucket[1] + " B2=" + $st.per_bucket[2])
  Write-Host ("BOOTS_TODAY=" + $st.boots_today + " (max " + $MaxBootsPerDay + ")")
  Write-Host ("AUDIT_OK=" + $st.audit_ok)
  if($st.audit_notes.Count -gt 0){ Write-Host ("AUDIT_NOTES=" + ($st.audit_notes -join "; ")) }
  Write-Host ("KILL=" + $st.kill_tripped + " reason=" + $st.kill_reason)
  Write-Host ("LAST_ACCEPT_TS=" + $st.last_accept_ts)
}

function Show-Tasks {
  try{
    Get-ScheduledTask | Where-Object { $_.TaskName -like "TBOT_*" } | Select-Object TaskName,State | Format-Table -AutoSize
  } catch { Write-Host "TASKS=WARNING (run as Admin if needed)." }
}

# ================== Commands ==================
$nowPt = Now-PT

switch($Cmd){

  "Tasks" { Show-Tasks; break }

  "Disable0630" {
    try{ Disable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" | Out-Null; Write-Host "Disabled TBOT_RUN_SHADOW_DAILY_0630" }
    catch{ Write-Host "Disable0630 FAILED (run as Admin)"; }
    break
  }

  "Enable0630" {
    try{ Enable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" | Out-Null; Write-Host "Enabled TBOT_RUN_SHADOW_DAILY_0630" }
    catch{ Write-Host "Enable0630 FAILED (run as Admin)"; }
    break
  }

  "Stop" {
    $k=Stop-TbotAll
    Write-Host ("STOPPED=" + $k)
    break
  }

  "MetaStats" {
    if(-not (Test-Path $META)){ throw "META missing: $META" }
    $counts = @{
      boot=0; shadow_plan=0; shadow_accept=0; shadow_reject=0; fake_plans=0
    }
    $today = (Now-PT).Date
    Get-Content $META -ReadCount 4000 | ForEach-Object {
      foreach($ln in $_){
        if(-not $ln){ continue }
        try { $j = $ln | ConvertFrom-Json } catch { continue }
        if(-not $j.kind -or -not $j.ts){ continue }
        $tPt = Parse-MetaTsPT ([string]$j.ts)
        if($tPt.Date -ne $today){ continue }
        $k = [string]$j.kind
        if($counts.ContainsKey($k)){ $counts[$k] = [int]$counts[$k] + 1 }
        if($k -eq "shadow_plan" -and (Is-FakePlan $j.payload)){ $counts["fake_plans"] = [int]$counts["fake_plans"] + 1 }
      }
    }
    Write-Host ("META_STATS day=" + $today.ToString("yyyy-MM-dd") + " boot=" + $counts.boot + " shadow_plan=" + $counts.shadow_plan + " shadow_accept=" + $counts.shadow_accept + " shadow_reject=" + $counts.shadow_reject + " fake_plans=" + $counts.fake_plans)
    break
  }

  "Status" {
    Write-Host ("ROOT=" + $ROOT)
    Write-Host ("PY exists=" + (Test-Path $PY) + " => " + $PY)
    Write-Host ("META exists=" + (Test-Path $META) + " => " + $META)
    Write-Host ("SHADOW exists=" + (Test-Path $SHADOW) + " => " + $SHADOW)

    $ps=@(Get-TbotProcs)
    if($ps.Count -eq 0){ Write-Host "TBOT=NOT_RUNNING" } else { Write-Host "TBOT=RUNNING"; $ps | Format-Table -AutoSize }

    $st=Load-State $nowPt
    if(Test-Path $META){ Rebuild-FromMeta ([ref]$st) $nowPt }
    Save-State $st $nowPt
    Print-Report $st $nowPt
    break
  }

  "Report" {
    $st=Load-State $nowPt
    if(Test-Path $META){ Rebuild-FromMeta ([ref]$st) $nowPt }
    Save-State $st $nowPt
    Print-Report $st $nowPt
    break
  }

  "SetupAndCheck" {
    Write-Host ("NOW_PT=" + (Now-PT).ToString("yyyy-MM-dd HH:mm:ss zzz"))
    Write-Host ("ROOT=" + $ROOT)

    if(-not $NoTaskCheck){
      Write-Host ""
      Write-Host "TASKS:"
      Show-Tasks
      if($Disable0630){
        try{ Disable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" | Out-Null; Write-Host "TASK_ACTION: Disabled TBOT_RUN_SHADOW_DAILY_0630" }
        catch{ Write-Host "TASK_ACTION: Disable0630 FAILED (run as Admin)"; }
      }
      if($Enable0630){
        try{ Enable-ScheduledTask -TaskName "TBOT_RUN_SHADOW_DAILY_0630" | Out-Null; Write-Host "TASK_ACTION: Enabled TBOT_RUN_SHADOW_DAILY_0630" }
        catch{ Write-Host "TASK_ACTION: Enable0630 FAILED (run as Admin)"; }
      }
    }

    Write-Host ""
    Write-Host "LOCK_TEST:"
    $lf=Join-Path $LOCKD "WEEK2_GATE_WRAPPER.lock"
    $h1=$null
    try{
      $h1=[System.IO.FileStream]::new($lf,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
      try{
        $h2=[System.IO.FileStream]::new($lf,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
        $h2.Dispose()
        Write-Host "LOCK_TEST=FAIL (second lock unexpectedly succeeded)"
      } catch { Write-Host "LOCK_TEST=PASS" }
    } finally { if($h1){ $h1.Dispose() } }

    Write-Host ""
    & $PSCommandPath MetaStats

    Write-Host ""
    & $PSCommandPath Status

    Write-Host ""
    Write-Host "TOMORROW (Wed 2026-02-18 PT) RUN:"
    Write-Host ".\tools\WEEK2_ONECLICK.ps1 StartOps -TotalDaily $TotalDaily -CooldownSec $CooldownSec -ShadowRiskUsd $ShadowRiskUsd -MaxPerSymbol $MaxPerSymbol -Symbols `"$Symbols`" -Force"
    break
  }

  "StartResearch" {
    if(-not (Acquire-Lock)){ throw "LOCKED: another wrapper instance is running." }
    try{
      if((Get-TbotProcs).Count -gt 0){
        if(-not $Force){ throw "BLOCK: tbot already running. Use -Force." }
        Stop-TbotAll | Out-Null
      }
      if(-not (Test-Path $PY)){ throw "PY missing: $PY" }
      if(-not (Test-Path $META)){ throw "META missing: $META" }

      $syms=$Symbols.Split(",") | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
      $ts=Get-Date -Format "yyyyMMdd_HHmmss"
      $out=Join-Path $OPS ("RESEARCH_OUT_{0}.txt" -f $ts)
      $err=Join-Path $OPS ("RESEARCH_ERR_{0}.txt" -f $ts)

      $st=Load-State (Now-PT)
      Rebuild-FromMeta ([ref]$st) (Now-PT)
      Save-State $st (Now-PT)

      $p=Start-Tbot -syms $syms -runMax 999999 -cool 0 -out $out -err $err
      Write-Host ("RESEARCH pid=" + $p.Id + " minutes=" + $ResearchMinutes)

      $end=(Now-PT).AddMinutes($ResearchMinutes)
      while((Now-PT) -lt $end){
        $nowPt=Now-PT
        $st=Load-State $nowPt
        foreach($ln in (Read-NewMetaLines ([ref]$st))){ Apply-MetaLine ([ref]$st) $ln $nowPt }
        if($st.kill_tripped){
          Write-Host ("KILL_TRIPPED => " + $st.kill_reason)
          Stop-TbotAll | Out-Null
          Save-State $st $nowPt
          throw ("STOPPED: " + $st.kill_reason)
        }
        Save-State $st $nowPt
        Start-Sleep -Seconds 5
      }

      Stop-TbotAll | Out-Null
      Write-Host "RESEARCH_DONE"
      Write-Host ("Tail OUT: Get-Content -Tail 60 `"$out`"")
      Write-Host ("Tail ERR: Get-Content -Tail 60 `"$err`"")
    } finally { Release-Lock }
    break
  }

  "StartOps" {
    if(-not (Acquire-Lock)){ throw "LOCKED: another wrapper instance is running." }
    try{
      if((Get-TbotProcs).Count -gt 0){
        if(-not $Force){ throw "BLOCK: tbot already running. Use -Force." }
        Stop-TbotAll | Out-Null
      }
      if(-not (Test-Path $PY)){ throw "PY missing: $PY" }
      if(-not (Test-Path $META)){ throw "META missing: $META" }

      $symsAll=$Symbols.Split(",") | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
      if($symsAll.Count -eq 0){ throw "Symbols empty" }

      while($true){
        $nowPt=Now-PT
        $sb=Session-Bounds $nowPt
        if($nowPt -lt $sb.start){
          $wait=[int][Math]::Max(5, ($sb.start-$nowPt).TotalSeconds)
          Write-Host ("WAIT until 06:30 PT ... " + $wait + "s")
          Start-Sleep -Seconds $wait
          continue
        }
        break
      }

      $st=Load-State (Now-PT)
      Rebuild-FromMeta ([ref]$st) (Now-PT)
      Save-State $st (Now-PT)

      Write-Host ("OPS_START TotalDaily=" + $TotalDaily + " Cooldown=" + $CooldownSec + " ShadowRiskUsd=" + $ShadowRiskUsd + " Symbols=" + ($symsAll -join ","))

      while($true){
        $nowPt=Now-PT
        $sb=Session-Bounds $nowPt
        if($nowPt -ge $sb.hardStop){
          Write-Host "HARD_STOP reached -> stopping"
          Stop-TbotAll | Out-Null
          break
        }

        $bid=Bucket-Id $nowPt
        if($bid -eq 99){
          Write-Host "OPS_DONE (after 13:00 window)"
          Stop-TbotAll | Out-Null
          break
        }

        $st=Load-State $nowPt
        foreach($ln in (Read-NewMetaLines ([ref]$st))){ Apply-MetaLine ([ref]$st) $ln $nowPt }

        if($st.kill_tripped){
          Write-Host ("KILL_TRIPPED => " + $st.kill_reason)
          Stop-TbotAll | Out-Null
          $st.audit_ok=$false
          $st.audit_notes += ("kill=" + $st.kill_reason)
          Save-State $st $nowPt
          throw ("STOPPED: " + $st.kill_reason)
        }

        if([int]$st.boots_today -gt $MaxBootsPerDay){
          Write-Host "NON_AUDITABLE: too many boots today => stopping"
          Stop-TbotAll | Out-Null
          $st.audit_ok=$false
          Save-State $st $nowPt
          break
        }

        $dailyRem=$TotalDaily - [int]$st.accepted_total
        if($dailyRem -le 0){
          Write-Host ("DAY_CAP_REACHED " + $st.accepted_total + "/" + $TotalDaily)
          Stop-TbotAll | Out-Null
          Save-State $st $nowPt
          break
        }

        $bq=Bucket-Quota $bid
        $bu=[int]$st.per_bucket[$bid]
        $bucketRem=$bq - $bu
        if($bucketRem -le 0){
          Stop-TbotAll | Out-Null
          $bb=Bucket-Bounds $nowPt
          $end = $(if($bid -eq 0){$bb.b0e} elseif($bid -eq 1){$bb.b1e} else {$bb.b2e})
          $wait=[int][Math]::Max(5, ($end-$nowPt).TotalSeconds)
          Write-Host ("BUCKET_FULL bid=" + $bid + " used=" + $bu + "/" + $bq + " sleep " + $wait + "s")
          Save-State $st $nowPt
          Start-Sleep -Seconds $wait
          continue
        }

        $active=@()
        foreach($s in $symsAll){
          $used=0
          try{ $used=[int]$st.per_symbol.$s } catch { $used=0 }
          if($used -lt $MaxPerSymbol){ $active += $s }
        }
        if($active.Count -eq 0){
          Write-Host "ALL_SYMBOLS_CAPPED"
          Stop-TbotAll | Out-Null
          $st.audit_ok=$false
          $st.audit_notes += "all_symbols_capped"
          Save-State $st $nowPt
          break
        }

        $ps=@(Get-TbotProcs)
        if($ps.Count -gt 1){
          Stop-TbotAll | Out-Null
          $st.audit_ok=$false
          $st.audit_notes += "multi_instance_detected"
          Save-State $st $nowPt
          throw "STOPPED: multiple tbot instances detected"
        }

        if($ps.Count -eq 0){
          $ts=Get-Date -Format "yyyyMMdd_HHmmss"
          $out=Join-Path $OPS ("OPS_OUT_B{0}_{1}.txt" -f $bid,$ts)
          $err=Join-Path $OPS ("OPS_ERR_B{0}_{1}.txt" -f $bid,$ts)
          $runMax=[Math]::Min($dailyRem,$bucketRem)
          Write-Host ("START bid=" + $bid + " runMax=" + $runMax + " symbols=" + ($active -join ","))

          $p=Start-Tbot -syms $active -runMax $runMax -cool $CooldownSec -out $out -err $err
          Write-Host ("PID=" + $p.Id + " OUT=" + $out)
          Start-Sleep -Seconds 3
        } else {
          Print-Report $st $nowPt
          Save-State $st $nowPt
          Start-Sleep -Seconds 10
        }
      }

      Save-State (Load-State (Now-PT)) (Now-PT)
      Write-Host "OPS_FINISHED"
    } finally { Release-Lock }
    break
  }
}
