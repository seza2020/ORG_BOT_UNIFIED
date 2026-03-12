<# tools\WEEK2_GATE_WRAPPER_V2.ps1
# PS 7+ | Week2 Shadow Gate Wrapper (NO python changes)
[CmdletBinding()]
param(
  [Parameter(Position=0)]
  [ValidateSet("StartOps","Status","Report","Stop","StartResearch")]
  [string]$Cmd = "Status",

  [int]$TotalDaily = 120,
  [int]$CooldownSec = 45,
  [int]$MaxPerSymbol = 60,
  [string]$Symbols = "SPY,QQQ,NVDA",

  [double]$ShadowRiskUsd = 25.0,
  [double]$GateMaxRiskUsd = 500.0,

  [int]$MaxBootsPerDay = 3,

  # 06:30–13:00 PT, hard stop before pre-close safety task (12:58:30)
  [int]$HardStop_HH = 12,
  [int]$HardStop_MM = 58,
  [int]$HardStop_SS = 15,

  [int]$ResearchMinutes = 10,
  [switch]$Force
)

$ErrorActionPreference="Stop"

# -------- Paths (project-only) --------
$ROOT   = Split-Path -Parent $PSScriptRoot
$PY     = Join-Path $ROOT ".venv\Scripts\python.exe"
$META   = Join-Path $ROOT "logs\meta.jsonl"
$SHADOW = Join-Path $ROOT "logs\shadow_plans.jsonl"   # legacy writer; kill-tail only
$OPS    = Join-Path $ROOT "logs\ops"
$LOCKD  = Join-Path $ROOT "logs\locks"
$WRAPLOCK = Join-Path $LOCKD "WEEK2_GATE_WRAPPER.lock"
New-Item -ItemType Directory -Force -Path $OPS,$LOCKD | Out-Null

# -------- Timezone (California / PT) --------
$TZ = [TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
function Now-PT { [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $TZ) }
function Parse-MetaTsLocal([string]$ts){
  $dt = [DateTime]::Parse($ts)
  $u  = [DateTime]::SpecifyKind($dt,[DateTimeKind]::Unspecified)
  $off= $TZ.GetUtcOffset($u)
  [DateTimeOffset]::new($u,$off)
}

# -------- Session + buckets (40/40/20 across 06:30–13:00 PT) --------
function Session-Bounds([datetimeoffset]$nowPt){
  $d=$nowPt.Date; $o=$nowPt.Offset
  $s=[datetimeoffset]::new($d.Year,$d.Month,$d.Day, 6,30,0,$o)
  $e=[datetimeoffset]::new($d.Year,$d.Month,$d.Day,13, 0,0,$o)
  $hs=[datetimeoffset]::new($d.Year,$d.Month,$d.Day,$HardStop_HH,$HardStop_MM,$HardStop_SS,$o)
  return @{ start=$s; end=$e; hardStop=$hs }
}
function Bucket-Bounds([datetimeoffset]$nowPt){
  $sb = Session-Bounds $nowPt
  $s=$sb.start; $e=$sb.end
  $total = ($e - $s).TotalSeconds
  $b0e = $s.AddSeconds([Math]::Round($total*0.40))
  $b1e = $b0e.AddSeconds([Math]::Round($total*0.40))
  return @{ b0s=$s; b0e=$b0e; b1s=$b0e; b1e=$b1e; b2s=$b1e; b2e=$e }
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
  try{
    $fs = [System.IO.FileStream]::new($WRAPLOCK,[System.IO.FileMode]::OpenOrCreate,[System.IO.FileAccess]::ReadWrite,[System.IO.FileShare]::None)
    $global:LockHandle = $fs
    $msg = "pid=$PID start=" + (Get-Date).ToString("s")
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $fs.SetLength(0); $fs.Write($bytes,0,$bytes.Length); $fs.Flush()
    return $true
  } catch { return $false }
}
function Release-Lock { if($global:LockHandle){ try{$global:LockHandle.Dispose()}catch{}; $global:LockHandle=$null } }

# -------- TBOT process targeting (project-only) --------
function Get-TbotProcs {
  if(-not (Test-Path $PY)) { return @() }
  Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $PY -and ($_.CommandLine -like "*-m tbot.main*" -or $_.CommandLine -like "*tbot.main*") } |
    Select-Object ProcessId,CommandLine
}
function Stop-TbotAll {
  $ps = @(Get-TbotProcs)
  foreach($p in $ps){
    try{ Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue | Out-Null } catch {}
  }
  return $ps.Count
}

# -------- State (restart-safe + meta-backed) --------
function State-Path([datetimeoffset]$nowPt){
  $d = $nowPt.ToString("yyyyMMdd")
  Join-Path $OPS ("gate_state_{0}.json" -f $d)
}
function New-State([datetimeoffset]$nowPt){
  @{
    day = $nowPt.ToString("yyyy-MM-dd")
    tz  = "PT"
    meta_pos = 0
    accepted_total = 0
    per_symbol = [pscustomobject]@{}
    per_bucket = @(0,0,0)
    run_ids = @()
    boots_today = 0
    audit_ok = $true
    audit_notes = @()
    kill_tripped = $false
    kill_reason = $null
    last_accept_ts = $null
  }
}
function Load-State([datetimeoffset]$nowPt){
  $p = State-Path $nowPt
  if(Test-Path $p){ try { return (Get-Content $p -Raw | ConvertFrom-Json) } catch {} }
  return (New-State $nowPt)
}
function Save-State($st,[datetimeoffset]$nowPt){ ($st | ConvertTo-Json -Depth 12) | Set-Content -Encoding UTF8 (State-Path $nowPt) }

# -------- Fake-plan kill switch --------
function Is-FakePlan($payload){
  if(-not $payload){ return $false }
  try{
    $r = [string]$payload.reason
    if($r -match "forced_signal_test"){ return $true }
    $e = [double]$payload.entry
    $s = [double]$payload.stop
    $t = [double]$payload.tp
    if([Math]::Abs($e-100.0) -lt 0.0001 -and [Math]::Abs($s-99.0) -lt 0.0001 -and [Math]::Abs($t-102.0) -lt 0.0001){ return $true }
  } catch {}
  return $false
}

# -------- Meta incremental reader --------
function Read-NewMetaLines([ref]$st){
  if(-not (Test-Path $META)){ return @() }
  $enc = [System.Text.Encoding]::UTF8
  $pos = [int64]$st.Value.meta_pos
  $len = (Get-Item $META).Length
  if($pos -gt $len){ $pos = 0; $st.Value.meta_pos = 0 } # truncated
  if($pos -eq $len){ return @() }

  $fs = [System.IO.FileStream]::new($META,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
  $sr = $null
  try{
    $fs.Seek($pos,[System.IO.SeekOrigin]::Begin) | Out-Null
    $sr = [System.IO.StreamReader]::new($fs,$enc,$true,4096,$true)
    $text = $sr.ReadToEnd()
    $bytesRead = $fs.Position - $pos
  } finally {
    try{ if($sr){$sr.Dispose()} } catch {}
    try{ $fs.Dispose() } catch {}
  }

  if(-not $text){ return @() }
  $endsWithNl = $text.EndsWith("`n") -or $text.EndsWith("`r`n")
  $lines = $text -split "`r?`n"
  if(-not $endsWithNl){
    $partial = $lines[-1]
    if($lines.Count -gt 1){ $lines = $lines[0..($lines.Count-2)] } else { $lines = @() }
    $bytesRead = $bytesRead - $enc.GetByteCount($partial)
  }
  $st.Value.meta_pos = $st.Value.meta_pos + $bytesRead
  return $lines | Where-Object { $_ -and $_.Trim().Length -gt 0 }
}

function Apply-MetaLine([ref]$st,[string]$line,[datetimeoffset]$nowPt){
  $today = $nowPt.Date
  $accKinds = @("shadow_plan","shadow_accept")
  try{ $j = $line | ConvertFrom-Json } catch { return }
  if(-not $j.kind -or -not $j.ts){ return }

  $tPt = Parse-MetaTsLocal ([string]$j.ts)
  if($tPt.Date -ne $today){ return }

  $kind = [string]$j.kind
  if($kind -eq "boot"){
    $rid = [string]$j.run_id
    if($rid -and -not ($st.Value.run_ids -contains $rid)){ $st.Value.run_ids += $rid }
    $st.Value.boots_today = @($st.Value.run_ids).Count
    if([int]$st.Value.boots_today -gt $MaxBootsPerDay){
      $st.Value.audit_ok = $false
      if(-not ($st.Value.audit_notes -contains "boots_today_gt_${MaxBootsPerDay}")){ $st.Value.audit_notes += "boots_today_gt_${MaxBootsPerDay}" }
    }
    return
  }

  if($accKinds -contains $kind){
    $p = $j.payload
    if(Is-FakePlan $p){
      $st.Value.kill_tripped = $true
      $st.Value.kill_reason = "fake_price_detected"
      return
    }

    $st.Value.accepted_total = [int]$st.Value.accepted_total + 1
    $sym = [string]$p.symbol
    if($sym){
      if(-not ($st.Value.per_symbol.PSObject.Properties.Name -contains $sym)){
        $st.Value.per_symbol | Add-Member -NotePropertyName $sym -NotePropertyValue 0 -Force
      }
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

function Rebuild-FromMeta([ref]$st,[datetimeoffset]$nowPt){
  if(-not (Test-Path $META)){ throw "META missing: $META" }
  $st.Value.meta_pos = 0
  $st.Value.accepted_total = 0
  $st.Value.per_symbol = [pscustomobject]@{}
  $st.Value.per_bucket = @(0,0,0)
  $st.Value.run_ids = @()
  $st.Value.boots_today = 0
  $st.Value.audit_ok = $true
  $st.Value.audit_notes = @()
  $st.Value.kill_tripped = $false
  $st.Value.kill_reason = $null
  $st.Value.last_accept_ts = $null

  Get-Content $META -ReadCount 4000 | ForEach-Object {
    foreach($ln in $_){ if($ln){ Apply-MetaLine $st $ln $nowPt } }
  }
  $st.Value.meta_pos = (Get-Item $META).Length
}

# -------- Shadow tail kill (fast) --------
function Tail-Shadow-Kill([ref]$st){
  if(-not (Test-Path $SHADOW)){ return }
  try{
    $tail = Get-Content -Tail 5 $SHADOW
    foreach($ln in $tail){
      if(-not $ln){ continue }
      try{
        $j = $ln | ConvertFrom-Json
        if(Is-FakePlan $j){
          $st.Value.kill_tripped = $true
          $st.Value.kill_reason = "fake_price_detected_shadow_tail"
          return
        }
      } catch {}
    }
  } catch {}
}

# -------- Start bot (NO --symbols; use TBOT_SYMBOLS env) --------
function Start-Tbot([string[]]$syms,[int]$runMax,[int]$cool,[string]$out,[string]$err){
  $env:TBOT_SYMBOLS = ($syms -join ",") # allowlist per run (non-destructive)

  $args = @(
    "-u","-m","tbot.main",
    "--run","--iters","999999","--sleep","0.25",
    "--shadow",
    "--shadow_path",$SHADOW,
    "--shadow_risk_usd","$ShadowRiskUsd",
    "--shadow_max_qty","5000",
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
  $bid = Bucket-Id $nowPt
  $bb = Bucket-Bounds $nowPt
  $sb = Session-Bounds $nowPt
  Write-Host ""
  Write-Host ("PT_NOW=" + $nowPt.ToString("yyyy-MM-dd HH:mm:ss zzz") + "  bucket=" + $bid)
  Write-Host ("SESSION=" + $sb.start.ToString("HH:mm") + "–" + $sb.end.ToString("HH:mm") + "  HARD_STOP=" + $sb.hardStop.ToString("HH:mm:ss"))
  Write-Host ("BUCKET_BOUNDS B0e=" + $bb.b0e.ToString("HH:mm") + " B1e=" + $bb.b1e.ToString("HH:mm"))
  Write-Host ("TOTAL_ACCEPTED=" + $st.accepted_total + "/" + $TotalDaily)
  Write-Host ("BUCKETS  B0=" + $st.per_bucket[0] + "  B1=" + $st.per_bucket[1] + "  B2=" + $st.per_bucket[2])
  Write-Host ("BOOTS_TODAY=" + $st.boots_today + " (max " + $MaxBootsPerDay + ")")
  Write-Host ("AUDIT_OK=" + $st.audit_ok)
  if($st.audit_notes.Count -gt 0){ Write-Host ("AUDIT_NOTES=" + ($st.audit_notes -join "; ")) }
  Write-Host ("KILL=" + $st.kill_tripped + " reason=" + $st.kill_reason)
  Write-Host ("LAST_ACCEPT_TS=" + $st.last_accept_ts)
}

$nowPt = Now-PT

switch($Cmd){

  "Stop" {
    $k = Stop-TbotAll
    Write-Host ("STOPPED=" + $k)
  }

  "Status" {
    Write-Host ("ROOT=" + $ROOT)
    Write-Host ("PY=" + $PY + " exists=" + (Test-Path $PY))
    Write-Host ("META=" + $META + " exists=" + (Test-Path $META))
    Write-Host ("SHADOW=" + $SHADOW + " exists=" + (Test-Path $SHADOW))

    $ps = @(Get-TbotProcs)
    if($ps.Count -eq 0){ Write-Host "TBOT=NOT_RUNNING" }
    else{ Write-Host "TBOT=RUNNING"; $ps | Format-Table -AutoSize }

    $st = Load-State $nowPt
    Rebuild-FromMeta ([ref]$st) $nowPt
    Tail-Shadow-Kill ([ref]$st)
    Save-State $st $nowPt
    Print-Report $st $nowPt
  }

  "Report" {
    $st = Load-State $nowPt
    Rebuild-FromMeta ([ref]$st) $nowPt
    Tail-Shadow-Kill ([ref]$st)
    Save-State $st $nowPt
    Print-Report $st $nowPt
  }

  "StartResearch" {
    if(-not (Acquire-Lock)){ throw "LOCKED: another wrapper instance is running ($WRAPLOCK)" }
    try{
      if((Get-TbotProcs).Count -gt 0){
        if(-not $Force){ throw "BLOCK: tbot already running. Use -Force." }
        Stop-TbotAll | Out-Null
      }

      $syms = $Symbols.Split(",") | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
      $ts = Get-Date -Format "yyyyMMdd_HHmmss"
      $out = Join-Path $OPS ("RESEARCH_OUT_{0}.txt" -f $ts)
      $err = Join-Path $OPS ("RESEARCH_ERR_{0}.txt" -f $ts)

      $st = Load-State (Now-PT)
      Rebuild-FromMeta ([ref]$st) (Now-PT)
      Save-State $st (Now-PT)

      $p = Start-Tbot -syms $syms -runMax 999999 -cool 0 -out $out -err $err
      Write-Host ("RESEARCH pid=" + $p.Id + " minutes=" + $ResearchMinutes)

      $end = (Now-PT).AddMinutes($ResearchMinutes)
      while((Now-PT) -lt $end){
        $nowPt = Now-PT
        $st = Load-State $nowPt
        $new = Read-NewMetaLines ([ref]$st)
        foreach($ln in $new){ Apply-MetaLine ([ref]$st) $ln $nowPt }
        Tail-Shadow-Kill ([ref]$st)
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
  }

  "StartOps" {
    if(-not (Acquire-Lock)){ throw "LOCKED: another wrapper instance is running ($WRAPLOCK)" }
    try{
      if((Get-TbotProcs).Count -gt 0){
        if(-not $Force){ throw "BLOCK: tbot already running. Use -Force." }
        Stop-TbotAll | Out-Null
      }

      if(-not (Test-Path $META)){ throw "META missing: $META" }

      $symsAll = $Symbols.Split(",") | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ }
      if($symsAll.Count -eq 0){ throw "Symbols empty" }

      while($true){
        $nowPt = Now-PT
        $sb = Session-Bounds $nowPt
        if($nowPt -lt $sb.start){
          $wait = [int][Math]::Max(5, ($sb.start - $nowPt).TotalSeconds)
          Write-Host ("WAIT until 06:30 PT ... " + $wait + "s")
          Start-Sleep -Seconds $wait
          continue
        }
        break
      }

      $st = Load-State (Now-PT)
      Rebuild-FromMeta ([ref]$st) (Now-PT)
      Save-State $st (Now-PT)

      Write-Host ("OPS_START TotalDaily=" + $TotalDaily + " Cooldown=" + $CooldownSec + " ShadowRiskUsd=" + $ShadowRiskUsd + " Symbols=" + ($symsAll -join ","))

      while($true){
        $nowPt = Now-PT
        $sb = Session-Bounds $nowPt
        if($nowPt -ge $sb.hardStop){
          Write-Host "HARD_STOP reached -> stopping"
          Stop-TbotAll | Out-Null
          break
        }

        $bid = Bucket-Id $nowPt
        if($bid -eq 99){
          Write-Host "OPS_DONE (after 13:00 PT)"
          Stop-TbotAll | Out-Null
          break
        }

        $st = Load-State $nowPt
        $new = Read-NewMetaLines ([ref]$st)
        foreach($ln in $new){ Apply-MetaLine ([ref]$st) $ln $nowPt }
        Tail-Shadow-Kill ([ref]$st)

        if($st.kill_tripped){
          Write-Host ("KILL_TRIPPED => " + $st.kill_reason)
          Stop-TbotAll | Out-Null
          $st.audit_ok = $false
          $st.audit_notes += ("kill=" + $st.kill_reason)
          Save-State $st $nowPt
          throw ("STOPPED: " + $st.kill_reason)
        }

        if([int]$st.boots_today -gt $MaxBootsPerDay){
          Write-Host "NON_AUDITABLE: too many boots today => stopping"
          Stop-TbotAll | Out-Null
          $st.audit_ok = $false
          Save-State $st $nowPt
          break
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
          Stop-TbotAll | Out-Null
          $bb = Bucket-Bounds $nowPt
          $end = $(if($bid -eq 0){$bb.b0e} elseif($bid -eq 1){$bb.b1e} else {$bb.b2e})
          $wait = [int][Math]::Max(5, ($end - $nowPt).TotalSeconds)
          Write-Host ("BUCKET_FULL bid=" + $bid + " used=" + $bu + "/" + $bq + " sleep " + $wait + "s")
          Save-State $st $nowPt
          Start-Sleep -Seconds $wait
          continue
        }

        $active = @()
        foreach($s in $symsAll){
          $used = 0
          try { $used = [int]$st.per_symbol.$s } catch { $used = 0 }
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

        $ps = @(Get-TbotProcs)
        if($ps.Count -gt 1){
          Stop-TbotAll | Out-Null
          $st.audit_ok = $false
          $st.audit_notes += "multi_instance_detected"
          Save-State $st $nowPt
          throw "STOPPED: multiple tbot instances detected"
        }

        if($ps.Count -eq 0){
          $ts = Get-Date -Format "yyyyMMdd_HHmmss"
          $out = Join-Path $OPS ("OPS_OUT_B{0}_{1}.txt" -f $bid,$ts)
          $err = Join-Path $OPS ("OPS_ERR_B{0}_{1}.txt" -f $bid,$ts)

          $runMax = [Math]::Min($dailyRem,$bucketRem)
          Write-Host ("START bid=" + $bid + " runMax=" + $runMax + " allow=" + ($active -join ","))

          $p = Start-Tbot -syms $active -runMax $runMax -cool $CooldownSec -out $out -err $err
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
  }
}
>
