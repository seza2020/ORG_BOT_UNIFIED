# tools\WEEK2_GATE_WRAPPER.ps1
# PS 7+ | Week2 Shadow Gate Wrapper (NO python changes)
[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [ValidateSet("StartOps","StartResearch","Status","Report","Stop","Freeze")]
  [string]$Cmd = "Status",

  [int]$TotalDaily = 100,          # baseline: 100
  [int]$CooldownSec = 90,          # baseline: 90
  [int]$MaxPerSymbol = 25,         # baseline: 25
  [string]$Symbols = "SPY,QQQ,NVDA",

  [int]$ResearchMinutes = 10,      # for StartResearch only
  [int]$MaxBootsPerDay = 3,        # if >3 => Non-Auditable + stop starting
  [switch]$StrictMismatch,         # if set => mismatch => stop
  [switch]$Force
)

$ErrorActionPreference="Stop"

# -------- Paths --------
$ROOT   = Split-Path -Parent $PSScriptRoot
$PY     = Join-Path $ROOT ".venv\Scripts\python.exe"
$META   = Join-Path $ROOT "logs\meta.jsonl"
$SHADOW = Join-Path $ROOT "logs\shadow_plans.jsonl"
$OPS    = Join-Path $ROOT "logs\ops"
$LOCKD  = Join-Path $ROOT "logs\locks"
New-Item -ItemType Directory -Force -Path $OPS,$LOCKD | Out-Null

# -------- Timezone (California / PT) --------
$TZ = [TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")

function Now-PT {
  return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $TZ)
}
function Make-Dto-PT([datetime]$dtUnspec) {
  $u = [DateTime]::SpecifyKind($dtUnspec,[DateTimeKind]::Unspecified)
  $off = $TZ.GetUtcOffset($u)
  return [DateTimeOffset]::new($u,$off)
}
function Parse-MetaTs([string]$ts, [string]$mode) {
  # meta ts usually local PT like 2026-02-17T11:21:57
  $dt = [DateTime]::Parse($ts)
  if($mode -eq "UTC"){
    $dtoUtc = [DateTimeOffset]::new([DateTime]::SpecifyKind($dt,[DateTimeKind]::Utc))
    return [TimeZoneInfo]::ConvertTime($dtoUtc, $TZ)
  }
  return Make-Dto-PT $dt
}
function Parse-ShadowUtc([string]$tsNoZ) {
  # shadow_plans ts looks like UTC without Z -> assume UTC
  return [datetimeoffset]::Parse($tsNoZ + "Z")
}

function Bucket-Bounds([datetimeoffset]$nowPt){
  $d = $nowPt.Date
  $b0s = [datetimeoffset]::new($d.Year,$d.Month,$d.Day, 6,30,0, $nowPt.Offset)
  $b0e = [datetimeoffset]::new($d.Year,$d.Month,$d.Day, 7,30,0, $nowPt.Offset)
  $b1s = $b0e
  $b1e = [datetimeoffset]::new($d.Year,$d.Month,$d.Day, 9,30,0, $nowPt.Offset)
  $b2s = $b1e
  $b2e = [datetimeoffset]::new($d.Year,$d.Month,$d.Day,13, 0,0, $nowPt.Offset)
  return @{ b0s=$b0s; b0e=$b0e; b1s=$b1s; b1e=$b1e; b2s=$b2s; b2e=$b2e }
}
function Bucket-Id([datetimeoffset]$tPt){
  $bb = Bucket-Bounds $tPt
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

# -------- Single instance lock (file handle held open) --------
$global:LockHandle = $null
function Acquire-Lock {
  $lf = Join-Path $LOCKD "WEEK2_GATE_WRAPPER.lock"
  try{
    $fs = [System.IO.FileStream]::new($lf,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    $global:LockHandle = $fs
    $msg = "pid=$PID start=" + (Get-Date).ToString("s")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $fs.SetLength(0); $fs.Write($bytes,0,$bytes.Length); $fs.Flush()
    return $true
  } catch {
    return $false
  }
}
function Release-Lock {
  if($global:LockHandle){
    try{ $global:LockHandle.Dispose() } catch {}
    $global:LockHandle = $null
  }
}

# -------- TBOT processes --------
function Get-TbotProcs {
  if(-not (Test-Path $PY)) { return @() }
  return Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
    Where-Object { $_.ExecutablePath -eq $PY -and $_.CommandLine -match " -m tbot\.main\b" }
}
function Stop-TbotAll {
  $ps = Get-TbotProcs
  foreach($p in $ps){
    try{ Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }
  return $ps.Count
}

# -------- State (restart-safe) --------
function State-Path([datetimeoffset]$nowPt){
  $d = $nowPt.ToString("yyyyMMdd")
  return (Join-Path $OPS ("gate_state_{0}.json" -f $d))
}
function New-State([datetimeoffset]$nowPt){
  return @{
    day = $nowPt.ToString("yyyy-MM-dd")
    tz = "PT"
    meta_ts_mode = "AUTO"     # AUTO/LOCAL/UTC
    meta_pos = 0
    accepted_total = 0
    per_symbol = @{}
    per_bucket = @(0,0,0)
    boots_today = 0
    run_ids = @()
    last_accept_ts = $null
    audit_ok = $true
    audit_notes = @()
    kill_tripped = $false
    kill_reason = $null
  }
}
function Load-State([datetimeoffset]$nowPt){
  $sp = State-Path $nowPt
  if(Test-Path $sp){
    try { return (Get-Content $sp -Raw | ConvertFrom-Json) } catch {}
  }
  return (New-State $nowPt)
}
function Save-State($st,[datetimeoffset]$nowPt){
  $sp = State-Path $nowPt
  ($st | ConvertTo-Json -Depth 12) | Set-Content -Encoding UTF8 $sp
}

# -------- Meta incremental reader (commit only full lines) --------
function Read-NewMetaLines([ref]$st){
  if(-not (Test-Path $META)){ return @() }
  $enc = [System.Text.Encoding]::UTF8
  $pos = [int64]$st.Value.meta_pos
  $len = (Get-Item $META).Length
  if($pos -gt $len){ $pos = 0; $st.Value.meta_pos = 0 } # rotated/truncated
  if($pos -eq $len){ return @() }

  $fs = [System.IO.FileStream]::new($META,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
  try{
    $fs.Seek($pos,[System.IO.SeekOrigin]::Begin) | Out-Null
    $sr = [System.IO.StreamReader]::new($fs,$enc,$true,4096,$true)
    $text = $sr.ReadToEnd()
    $bytesRead = $fs.Position - $pos
  } finally {
    try{ $fs.Dispose() } catch {}
  }

  if(-not $text){ return @() }
  $endsWithNl = $text.EndsWith("`n") -or $text.EndsWith("`r`n")
  $lines = $text -split "`r?`n"
  if(-not $endsWithNl){
    # drop last partial
    $partial = $lines[-1]
    if($lines.Count -gt 1){ $lines = $lines[0..($lines.Count-2)] } else { $lines = @() }
    $bytesRead = $bytesRead - $enc.GetByteCount($partial)
  }
  $st.Value.meta_pos = $st.Value.meta_pos + $bytesRead
  return $lines | Where-Object { $_ -and $_.Trim().Length -gt 0 }
}

# -------- Kill-switch: fake pricing --------
function Is-FakePlan($payload){
  if(-not $payload){ return $false }
  try{
    $r = [string]$payload.reason
    if($r -match "forced_signal_test"){ return $true }
    $e = [double]$payload.entry
    $s = [double]$payload.stop
    $t = [double]$payload.tp
    # detect common fake template 100/99/102 with small tolerance
    if([Math]::Abs($e-100.0) -lt 0.0001 -and [Math]::Abs($s-99.0) -lt 0.0001 -and [Math]::Abs($t-102.0) -lt 0.0001){ return $true }
  } catch {}
  return $false
}

# -------- Apply meta line to state --------
function Apply-MetaLine([ref]$st,[string]$line,[datetimeoffset]$nowPt){
  $today = $nowPt.Date
  try{
    $j = $line | ConvertFrom-Json
  } catch { return }

  if(-not $j.kind -or -not $j.ts){ return }
  $kind = [string]$j.kind

  # auto-detect ts mode once
  if($st.Value.meta_ts_mode -eq "AUTO"){
    try{
      $dt = [DateTime]::Parse([string]$j.ts)
      $ptGuess = Make-Dto-PT $dt
      $deltaMin = [Math]::Abs(($nowPt - $ptGuess).TotalMinutes)
      $st.Value.meta_ts_mode = ($(if($deltaMin -gt 180){"UTC"} else {"LOCAL"}))
    } catch { $st.Value.meta_ts_mode = "LOCAL" }
  }

  $tPt = Parse-MetaTs ([string]$j.ts) $st.Value.meta_ts_mode
  if($tPt.Date -ne $today){ return }

  if($kind -eq "boot"){
    $rid = [string]$j.run_id
    if($rid -and -not ($st.Value.run_ids -contains $rid)){
      $st.Value.run_ids += $rid
      $st.Value.boots_today = [int]$st.Value.boots_today + 1
      if([int]$st.Value.boots_today -gt $MaxBootsPerDay){
        $st.Value.audit_ok = $false
        $st.Value.audit_notes += "boots_today_gt_${MaxBootsPerDay}"
      }
    }
    return
  }

  if($kind -eq "shadow_plan"){
    $p = $j.payload

    # kill-switch
    if(Is-FakePlan $p){
      $st.Value.kill_tripped = $true
      $st.Value.kill_reason = "fake_price_detected"
      return
    }

    # counts
    $st.Value.accepted_total = [int]$st.Value.accepted_total + 1
    $sym = [string]$p.symbol
    if($sym){
      if(-not $st.Value.per_symbol.$sym){ $st.Value.per_symbol | Add-Member -NotePropertyName $sym -NotePropertyValue 0 -Force }
      $st.Value.per_symbol.$sym = [int]$st.Value.per_symbol.$sym + 1
    }

    $bid = Bucket-Id $tPt
    if($bid -ge 0 -and $bid -le 2){
      $arr = @($st.Value.per_bucket)
      $arr[$bid] = [int]$arr[$bid] + 1
      $st.Value.per_bucket = $arr
    }

    $st.Value.last_accept_ts = $tPt.ToString("s")
  }
}

# -------- shadow/meta mismatch check (lightweight) --------
function Check-Mismatch([ref]$st,[datetimeoffset]$nowPt){
  if(-not (Test-Path $SHADOW)){ return }
  $today = $nowPt.Date
  $metaCount = [int]$st.Value.accepted_total

  $shadowToday = 0
  Get-Content $SHADOW -ReadCount 4000 | ForEach-Object {
    foreach($ln in $_){
      if(-not $ln){ continue }
      try{
        $j = $ln | ConvertFrom-Json
        $utc = Parse-ShadowUtc ([string]$j.ts)
        $pt = [TimeZoneInfo]::ConvertTime($utc,$TZ)
        if($pt.Date -ne $today){ continue }
        $shadowToday++
      } catch {}
    }
  }

  if($metaCount -gt 0){
    $diff = [Math]::Abs($shadowToday - $metaCount)
    $ratio = $diff / [double]$metaCount
    if($diff -ge 3 -and $ratio -ge 0.02){
      $st.Value.audit_ok = $false
      $st.Value.audit_notes += ("mismatch_meta_vs_shadow meta={0} shadow={1}" -f $metaCount,$shadowToday)
      if($StrictMismatch){
        $st.Value.kill_tripped = $true
        $st.Value.kill_reason = "mismatch_meta_shadow_strict"
      }
    }
  }
}

# -------- Allowlist per bucket (non-destructive) --------
function Write-Allowlist([string[]]$syms,[int]$bid,[datetimeoffset]$nowPt){
  $d = $nowPt.ToString("yyyyMMdd")
  $p = Join-Path $OPS ("symbols_allowlist_bucket_{0}_{1}.txt" -f $bid,$d)
  ($syms -join "`r`n") | Set-Content -Encoding UTF8 $p
  return $p
}

# -------- Start TBOT with params (no forced signals) --------
function Start-Tbot([string[]]$syms,[int]$runMax,[int]$cool,[string]$out,[string]$err){
  # ENV: MVP on + alpha thresholds open (for your current testing)
  $env:TBOT_ENABLE_S11_MVP     = "1"
  $env:TBOT_S11_MIN_STRENGTH   = "0"
  $env:TBOT_S11_MIN_CONF       = "0.55"
  $env:TBOT_ALPHA_TREND_ON_TH  = "0"
  $env:TBOT_ALPHA_TREND_CAP_TH = "0"
  $env:TBOT_MARKET_DEBUG       = "0"

  $symArg = ($syms -join ",")
  $args = @(
    "-u","-m","tbot.main",
    "--iters","999999",
    "--sleep","0.25",
    "--symbols",$symArg,
    "--shadow","1",
    "--shadow_path",$SHADOW,
    "--shadow_risk_usd","250",
    "--shadow_max_qty","5000",
    "--gate_min_rr","1.0",
    "--gate_min_conf","0.0",
    "--gate_cooldown_sec","$cool",
    "--gate_max_plans_per_day","$runMax",
    "--gate_max_risk_usd","500.0"
  )

  return Start-Process -FilePath $PY -ArgumentList $args -PassThru -NoNewWindow `
      -RedirectStandardOutput $out -RedirectStandardError $err
}

function Print-Report($st,[datetimeoffset]$nowPt){
  $bb = Bucket-Bounds $nowPt
  $bid = Bucket-Id $nowPt
  Write-Host ""
  Write-Host ("PT_NOW=" + $nowPt.ToString("yyyy-MM-dd HH:mm:ss zzz") + "  bucket=" + $bid)
  Write-Host ("TOTAL=" + $st.accepted_total + "/" + $TotalDaily)
  Write-Host ("BUCKETS  B0=" + $st.per_bucket[0] + "  B1=" + $st.per_bucket[1] + "  B2=" + $st.per_bucket[2])
  Write-Host ("BOOTS_TODAY=" + $st.boots_today + " (max " + $MaxBootsPerDay + ")")
  Write-Host ("AUDIT_OK=" + $st.audit_ok)
  if($st.audit_notes.Count -gt 0){ Write-Host ("AUDIT_NOTES=" + ($st.audit_notes -join "; ")) }
  Write-Host ("KILL=" + $st.kill_tripped + " reason=" + $st.kill_reason)
  Write-Host "PER_SYMBOL:"
  $props = $st.per_symbol.PSObject.Properties.Name | Sort-Object
  if($props.Count -eq 0){ Write-Host "  (none yet)" }
  foreach($k in $props){
    Write-Host ("  " + $k + " = " + $st.per_symbol.$k + " / " + $MaxPerSymbol)
  }
  if(Test-Path $SHADOW){
    $fi = Get-Item $SHADOW
    Write-Host ("SHADOW_FILE size=" + $fi.Length + " mtime=" + $fi.LastWriteTime)
    Write-Host "SHADOW_TAIL:"
    Get-Content -Tail 3 $SHADOW | ForEach-Object { Write-Host ("  " + $_) }
  }
}

# -------- Commands --------
$nowPt = Now-PT

switch($Cmd){

  "Stop" {
    $k = Stop-TbotAll
    Write-Host ("STOPPED=" + $k)
    break
  }

  "Status" {
    Write-Host ("ROOT=" + $ROOT)
    Write-Host ("PY=" + $PY + " exists=" + (Test-Path $PY))
    Write-Host ("META=" + $META + " exists=" + (Test-Path $META))
    Write-Host ("SHADOW=" + $SHADOW + " exists=" + (Test-Path $SHADOW))
    $ps = Get-TbotProcs
    if($ps.Count -eq 0){ Write-Host "TBOT=NOT_RUNNING" }
    else{
      Write-Host "TBOT=RUNNING"
      $ps | Select ProcessId,CreationDate,CommandLine | Format-Table -AutoSize
    }
    $st = Load-State $nowPt
    Print-Report $st $nowPt
    break
  }

  "Report" {
    $st = Load-State $nowPt
    Print-Report $st $nowPt
    break
  }

  "Freeze" {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $dst = Join-Path $OPS ("FREEZE_{0}.zip" -f $ts)
    Compress-Archive -Force -Path ".\logs\*.jsonl",".\logs\ops\*.txt",".\tools\*.ps1" -DestinationPath $dst
    Write-Host ("FREEZE_OK => " + $dst)
    break
  }

  "StartResearch" {
    if(-not (Acquire-Lock)){ throw "LOCKED: another wrapper instance is running." }
    try{
      if((Get-TbotProcs).Count -gt 0){
        if(-not $Force){ throw "BLOCK: tbot already running. Use -Force." }
        Stop-TbotAll | Out-Null
      }

      $ts = Get-Date -Format "yyyyMMdd_HHmmss"
      $out = Join-Path $OPS ("RESEARCH_OUT_{0}.txt" -f $ts)
      $err = Join-Path $OPS ("RESEARCH_ERR_{0}.txt" -f $ts)

      $syms = $Symbols.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
      if($syms.Count -eq 0){ throw "Symbols empty" }

      # Research: cooldown=0, huge cap, but limited time. (shadow file separate not required here; meta-based analysis anyway)
      $p = Start-Tbot -syms $syms -runMax 999999 -cool 0 -out $out -err $err
      Write-Host ("RESEARCH pid=" + $p.Id + " minutes=" + $ResearchMinutes)
      Start-Sleep -Seconds ([Math]::Max(30, $ResearchMinutes*60))
      try{ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
      Write-Host "RESEARCH_DONE"
      Write-Host ("Tail OUT: Get-Content -Tail 60 `"$out`"")
      Write-Host ("Tail ERR: Get-Content -Tail 60 `"$err`"")
    } finally {
      Release-Lock
    }
    break
  }

  "StartOps" {
    if(-not (Acquire-Lock)){ throw "LOCKED: another wrapper instance is running." }
    try{
      if((Get-TbotProcs).Count -gt 0){
        if(-not $Force){ throw "BLOCK: tbot already running. Use -Force." }
        Stop-TbotAll | Out-Null
      }

      $symsAll = $Symbols.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
      if($symsAll.Count -eq 0){ throw "Symbols empty" }

      $st = Load-State $nowPt

      # if meta missing, cannot gate safely
      if(-not (Test-Path $META)){ throw "META missing: $META" }

      # Wait until 06:30 PT
      while($true){
        $nowPt = Now-PT
        $bb = Bucket-Bounds $nowPt
        if($nowPt -lt $bb.b0s){
          $wait = [int][Math]::Max(5, ($bb.b0s - $nowPt).TotalSeconds)
          Write-Host ("WAIT until 06:30 PT ... " + $wait + "s")
          Start-Sleep -Seconds $wait
          continue
        }
        break
      }

      Write-Host ("OPS_START TotalDaily=" + $TotalDaily + " Cooldown=" + $CooldownSec + " MaxPerSymbol=" + $MaxPerSymbol + " Symbols=" + ($symsAll -join ","))

      $currentPid = $null
      while($true){
        $nowPt = Now-PT
        $bid = Bucket-Id $nowPt
        if($bid -eq 99){
          Write-Host "OPS_DONE (after 13:00 PT)"
          break
        }

        # ingest new meta lines
        $new = Read-NewMetaLines ([ref]$st)
        foreach($ln in $new){ Apply-MetaLine ([ref]$st) $ln $nowPt }

        # kill-switch
        if($st.kill_tripped){
          Write-Host ("KILL_TRIPPED => " + $st.kill_reason)
          Stop-TbotAll | Out-Null
          $st.audit_ok = $false
          $st.audit_notes += ("kill=" + $st.kill_reason)
          Save-State $st $nowPt
          throw ("STOPPED: " + $st.kill_reason)
        }

        # too many boots => stop starting
        if([int]$st.boots_today -gt $MaxBootsPerDay){
          Write-Host "NON_AUDITABLE: too many boots today"
          Stop-TbotAll | Out-Null
          Save-State $st $nowPt
          break
        }

        # mismatch check occasionally
        Check-Mismatch ([ref]$st) $nowPt
        if($st.kill_tripped){
          Write-Host ("KILL_TRIPPED => " + $st.kill_reason)
          Stop-TbotAll | Out-Null
          Save-State $st $nowPt
          throw ("STOPPED: " + $st.kill_reason)
        }

        $dailyRem = $TotalDaily - [int]$st.accepted_total
        if($dailyRem -le 0){
          Write-Host ("DAY_CAP_REACHED " + $st.accepted_total + "/" + $TotalDaily)
          Stop-TbotAll | Out-Null
          Save-State $st $nowPt
          break
        }

        $bq = Bucket-Quota $bid
        $bu = [int]$st.per_bucket[$bid]
        $bucketRem = $bq - $bu
        if($bucketRem -le 0){
          # stop process & wait for next bucket
          Stop-TbotAll | Out-Null
          $bb = Bucket-Bounds $nowPt
          $end = $(if($bid -eq 0){$bb.b0e} elseif($bid -eq 1){$bb.b1e} else {$bb.b2e})
          $wait = [int][Math]::Max(5, ($end - $nowPt).TotalSeconds)
          Write-Host ("BUCKET_FULL bid=" + $bid + " used=" + $bu + "/" + $bq + " sleep " + $wait + "s")
          Save-State $st $nowPt
          Start-Sleep -Seconds $wait
          continue
        }

        # active symbols (non-destructive)
        $active = @()
        foreach($s in $symsAll){
          $used = 0
          try { $used = [int]($st.per_symbol.$s) } catch { $used = 0 }
          if($used -lt $MaxPerSymbol){ $active += $s }
        }
        if($active.Count -eq 0){
          Write-Host "ALL_SYMBOLS_CAPPED"
          Stop-TbotAll | Out-Null
          $st.audit_ok = $false
          $st.audit_notes += "all_symbols_capped"
          Save-State $st $nowPt
          break
        }

        $allowPath = Write-Allowlist $active $bid $nowPt

        # ensure only one TBOT instance
        $ps = Get-TbotProcs
        if($ps.Count -gt 1){
          Stop-TbotAll | Out-Null
          $st.audit_ok = $false
          $st.audit_notes += "multi_instance_detected"
          Save-State $st $nowPt
          throw "STOPPED: multiple tbot instances detected"
        }

        # start if not running
        if($ps.Count -eq 0){
          $ts = Get-Date -Format "yyyyMMdd_HHmmss"
          $out = Join-Path $OPS ("OPS_OUT_B{0}_{1}.txt" -f $bid,$ts)
          $err = Join-Path $OPS ("OPS_ERR_B{0}_{1}.txt" -f $bid,$ts)

          $runMax = [Math]::Min($dailyRem,$bucketRem)
          Write-Host ("START bid=" + $bid + " runMax=" + $runMax + " allow=" + $allowPath)

          $p = Start-Tbot -syms $active -runMax $runMax -cool $CooldownSec -out $out -err $err
          $currentPid = $p.Id
          Write-Host ("PID=" + $currentPid + " OUT=" + $out)

          # small settle
          Start-Sleep -Seconds 3
          continue
        }

        # running: monitor periodically
        Print-Report $st $nowPt
        Save-State $st $nowPt
        Start-Sleep -Seconds 10
      }

      Save-State $st (Now-PT)
      Write-Host "OPS_FINISHED"
    } finally {
      Release-Lock
    }
    break
  }
}
