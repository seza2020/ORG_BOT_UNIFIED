param(


  [string]$Root = 'C:\alpaca-bot\org_bot',


  [string]$IsoDayOverride = ''


)







# RUNROOT_LOGROOT_V1 (Paper/Shadow separation; PS5-safe)
$LogRoot = $Root
$__rr = [string]$env:TBOT_RUNROOT
if($__rr){ $__rr = $__rr.Trim() }
if(-not [string]::IsNullOrWhiteSpace($__rr)){
  $LogRoot = $__rr
}
$ErrorActionPreference = 'Stop'


Set-StrictMode -Version Latest





function SafeCount($x) { return @($x).Count }



function Extract-DayLinesTsRegex([string]$SrcPath, [string]$OutPath, [string]$IsoDay) {
  # Always ensure the output file exists (even if empty).
  New-Item -ItemType File -Force -Path $OutPath | Out-Null

  if ([string]::IsNullOrWhiteSpace($SrcPath)) { return 0 }
  if (-not (Test-Path -Path $SrcPath)) { return 0 }

  # Match: "ts" optional spaces ":" optional spaces "YYYY-MM-DDT
  $pat = '"ts"\s*:\s*"' + [regex]::Escape($IsoDay) + 'T'

  Select-String -Path $SrcPath -Pattern $pat -AllMatches -ErrorAction SilentlyContinue |
    ForEach-Object { $_.Line } |
    Set-Content -Encoding UTF8 -Path $OutPath

  try {
    return (SafeCount (Get-Content -Path $OutPath -ErrorAction SilentlyContinue))
  } catch {
    return 0
  }
}
function SafeTestPath([string]$p) { return (-not [string]::IsNullOrWhiteSpace($p)) -and (Test-Path -Path $p) }





function WriteText([string]$Path, [string[]]$Lines) {


  $Lines | Set-Content -Encoding UTF8 -Path $Path


}





function FindLatestByName([string]$RootDir, [string]$Name) {


  $hit = Get-ChildItem -Path $RootDir -Recurse -File -ErrorAction SilentlyContinue |


    Where-Object { $_.Name -ieq $Name } |


    Sort-Object LastWriteTime -Descending |


    Select-Object -First 1


  if ($hit) { return $hit.FullName }


  return $null


}





function ExtractDayLines([string]$SrcPath, [string]$OutPath, [string]$Needle) {


  New-Item -ItemType File -Force -Path $OutPath | Out-Null


  if (-not (SafeTestPath $SrcPath)) { return 0 }





  $matches = Select-String -Path $SrcPath -SimpleMatch $Needle -ErrorAction SilentlyContinue


  if ((SafeCount $matches) -gt 0) {


    $matches | ForEach-Object { $_.Line } | Set-Content -Encoding UTF8 -Path $OutPath


  }





  try { return (SafeCount (Get-Content -Path $OutPath -ErrorAction SilentlyContinue)) } catch { return 0 }


}





function RotateShadowIfNewDay([string]$ShadowPath, [string]$DayFile) {


  if (-not (Test-Path -Path $ShadowPath)) { return }





  $fi = Get-Item -Path $ShadowPath -ErrorAction SilentlyContinue


  if (-not $fi) { return }





  if ($fi.Length -le 0) { return }





  $lw = $fi.LastWriteTime


  $todayLocal = (Get-Date).Date


  if ($lw.Date -lt $todayLocal) {


    $archive = Join-Path (Split-Path $ShadowPath -Parent) ("shadow_plans_{0}_ARCHIVE.jsonl" -f $lw.ToString('yyyyMMdd'))


    if (Test-Path -Path $archive) {


      $archive = Join-Path (Split-Path $ShadowPath -Parent) ("shadow_plans_{0}_ARCHIVE_{1}.jsonl" -f $lw.ToString('yyyyMMdd'), (Get-Date).ToString('HHmmss'))


    }





    Move-Item -Force -Path $ShadowPath -Destination $archive


    New-Item -ItemType File -Force -Path $ShadowPath | Out-Null


  }


}





function RecoverShadowFromLiveOut([string[]]$LivePaths, [string]$IsoDay, [string]$OutPath, [string]$Mode) {


  # Mode: PLAN | REJECT


  # Parses lines like:


  # INFO/WARN  | 2026-02-12T06:30:31 | ... | shadow_reject {...}


  # INFO       | 2026-...           | ... | shadow_plan {...}


  # Writes JSONL with minimal schema.





  if ((SafeCount $LivePaths) -le 0) { return 0 }


  $rx = [regex]'^\w+\s+\|\s+(?<ts>\d{4}-\d{2}-\d{2}T[0-9:\.]+)\s+\|\s+[0-9a-f]+\s+\|\s+(?<kind>shadow_plan|shadow_accept|shadow_reject)\s+(?<payload>\{.*\})\s*$'





  $ok = 0


  New-Item -ItemType File -Force -Path $OutPath | Out-Null





  foreach ($p in $LivePaths) {


    if (-not (Test-Path -Path $p)) { continue }


    $lines = Get-Content -Path $p -ErrorAction SilentlyContinue


    foreach ($ln in $lines) {


      if ($ln -notlike "*$IsoDay*") { continue }


      $m = $rx.Match($ln)


      if (-not $m.Success) { continue }





      $kind = $m.Groups['kind'].Value


      if ($Mode -eq 'PLAN') {


        if ($kind -ne 'shadow_plan' -and $kind -ne 'shadow_accept') { continue }


      } elseif ($Mode -eq 'REJECT') {


        if ($kind -ne 'shadow_reject') { continue }


      }





      $ts = $m.Groups['ts'].Value


      $payloadText = $m.Groups['payload'].Value





      # payload is python dict style -> JSON normalize:


      # replace single quotes with double quotes, True/False/None


      $j = $payloadText


      $j = $j -replace "None", "null"


      $j = $j -replace "\bTrue\b", "true"


      $j = $j -replace "\bFalse\b", "false"


      $j = $j -replace "'", '"'





      try {


        $o = $j | ConvertFrom-Json -ErrorAction Stop





        $entry = [double]($o.entry)


        $stop  = [double]($o.stop)


        $tp    = $null


        if ($o.tp -ne $null) { $tp = [double]($o.tp) }





        $side = [string]$o.side


        if ([string]::IsNullOrWhiteSpace($side)) { $side = 'LONG' }





        if ($tp -eq $null -or $tp -eq 0) {


          # if tp missing, infer 2R using rr if present else 2.0


          $rr = 2.0


          if ($o.rr -ne $null) { try { $rr = [double]$o.rr } catch {} }


          $risk = [Math]::Abs($entry - $stop)


          if ($risk -le 0) { continue }


          if ($side -eq 'SHORT') { $tp = $entry - ($rr * $risk) } else { $tp = $entry + ($rr * $risk) }


        }





        $risk_ps = [Math]::Abs($entry - $stop)


        if ($risk_ps -le 0) { continue }





        $rr2 = [Math]::Abs($tp - $entry) / $risk_ps





        $qty = 0


        if ($o.qty -ne $null) { try { $qty = [int]$o.qty } catch {} }





        $risk_usd = 0.0


        if ($o.risk_usd -ne $null) { try { $risk_usd = [double]$o.risk_usd } catch {} }





        $conf = 0.0


        if ($o.confidence -ne $null) { try { $conf = [double]$o.confidence } catch {} }





        $ev = [ordered]@{


          ts = $ts


          env = 'PAPER'


          sid = [string]$o.sid


          symbol = [string]$o.symbol


          side = $side


          confidence = $conf


          reason = [string]$o.reason


          entry = [Math]::Round($entry, 5)


          stop  = [Math]::Round($stop, 5)


          tp    = [Math]::Round([double]$tp, 5)


          qty   = $qty


          risk_usd = $risk_usd


          per_share_risk = [Math]::Round($risk_ps, 8)


          rr = [Math]::Round($rr2, 8)


          notes = "recovered_from_live_out:$Mode"


        }





        ($ev | ConvertTo-Json -Compress -Depth 6) | Add-Content -Encoding UTF8 -Path $OutPath


        $ok++


      } catch {


        continue


      }


    }


  }





  return $ok


}





# ---- paths


$Logs   = Join-Path $LogRoot 'logs'


$Ops    = Join-Path $Logs 'ops'


$Freeze = Join-Path $Logs 'freeze'


New-Item -ItemType Directory -Force -Path $Ops, $Freeze | Out-Null





# ---- date


$Now = Get-Date


if ([string]::IsNullOrWhiteSpace($IsoDayOverride)) {


  $IsoDay = $Now.ToString('yyyy-MM-dd')


} else {


  $IsoDay = $IsoDayOverride.Trim()


}





try { $dt = [DateTime]::ParseExact($IsoDay,'yyyy-MM-dd',[System.Globalization.CultureInfo]::InvariantCulture) }


catch { throw "IsoDayOverride must be YYYY-MM-DD. Got: $IsoDay" }





$DayFile = $dt.ToString('yyyyMMdd')


$Stamp   = $Now.ToString('yyyyMMdd_HHmmss')





$Stage = Join-Path $Ops ("FREEZE_STAGE_{0}_{1}" -f $DayFile, $Stamp)


$BK    = Join-Path $Ops ("FREEZE_BACKUP_{0}_{1}" -f $DayFile, $Stamp)


New-Item -ItemType Directory -Force -Path $Stage, $BK | Out-Null





$qcResult = 'FAIL'


$shadow_was_recovered = $false





try {


  # ---- sources


  $ShadowPath = Join-Path $Logs 'shadow_plans.jsonl'


  RotateShadowIfNewDay $ShadowPath $DayFile





  $MetaSrc = FindLatestByName $Logs 'meta.jsonl'


  $AnnSrc  = FindLatestByName $Logs 'announce.log'





  # ---- LIVE_OUT (whole day list)


  $Live = @(Get-ChildItem -Path $Ops -File -Filter ("LIVE_OUT_{0}_*.txt" -f $DayFile) -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)


  $livePaths = @()


  if ((SafeCount $Live) -gt 0) { $livePaths = @($Live | ForEach-Object { $_.FullName }) }





  # copy all LIVE_OUT into stage


  if ((SafeCount $Live) -gt 0) {


    foreach ($f in $Live) { Copy-Item -Force -Path $f.FullName -Destination $Stage }


  }





  # ---- if shadow_plans empty OR contains no day lines -> recover from LIVE_OUT


  $ShadowDay   = Join-Path $Stage ("shadow_plans_{0}.jsonl" -f $DayFile)


  $ShadowFull  = Join-Path $Stage ("shadow_plans_FULL_{0}.jsonl" -f $DayFile)





  $NeedleShadow = '"ts": "' + $IsoDay + 'T'


  $shadow_lines = 0
# --- shadow full lines (source file) as a secondary truth (avoids ts/day-slice mismatch)
$shadow_lines_full = 0
try {
  if ($ShadowSrc -and (Test-Path -Path $ShadowSrc)) {
    Get-Content -Path $ShadowSrc -ErrorAction SilentlyContinue | ForEach-Object { $shadow_lines_full++ }
  }
} catch { $shadow_lines_full = 0 }





  if (SafeTestPath $ShadowPath) {


    Copy-Item -Force -Path $ShadowPath -Destination $ShadowFull


    $shadow_lines = ExtractDayLines $ShadowPath $ShadowDay $NeedleShadow


  } else {


    New-Item -ItemType File -Force -Path $ShadowFull | Out-Null


    New-Item -ItemType File -Force -Path $ShadowDay  | Out-Null


  }





  $shadowFileLen = 0


  try { $shadowFileLen = (Get-Item -Path $ShadowPath -ErrorAction SilentlyContinue).Length } catch { $shadowFileLen = 0 }





  if ($shadowFileLen -le 0 -or $shadow_lines -le 0) {


    $RecoveredPlans = Join-Path $Logs ("shadow_plans_RECOVERED_{0}.jsonl" -f $DayFile)


    $nrec = RecoverShadowFromLiveOut $livePaths $IsoDay $RecoveredPlans 'PLAN'


    if ($nrec -gt 0) {


      $shadow_was_recovered = $true


      Copy-Item -Force -Path $RecoveredPlans -Destination $ShadowPath


      Copy-Item -Force -Path $RecoveredPlans -Destination $ShadowFull


      $shadow_lines = ExtractDayLines $RecoveredPlans $ShadowDay $NeedleShadow


    }


  }





  # ---- meta/announce day extracts


  $MetaDay = Join-Path $Stage ("meta_{0}.jsonl" -f $DayFile)


  $AnnDay  = Join-Path $Stage ("announce_{0}.log" -f $DayFile)





  $meta_lines = 0


  if (SafeTestPath $MetaSrc) { $meta_lines = ExtractDayLines $MetaSrc $MetaDay ($IsoDay + 'T') } else { Remove-Item -Force -Path $MetaDay -ErrorAction SilentlyContinue }





  $ann_lines = 0


  if (SafeTestPath $AnnSrc)  { $ann_lines  = ExtractDayLines $AnnSrc  $AnnDay  ($IsoDay + 'T') } else { Remove-Item -Force -Path $AnnDay  -ErrorAction SilentlyContinue }





  # ---- env snapshot (TBOT only)


  $EnvSafe = Join-Path $Stage ("env_TBOT_SAFE_{0}.txt" -f $DayFile)


  Get-ChildItem env:TBOT* -ErrorAction SilentlyContinue |


    Sort-Object Name |


    ForEach-Object { "{0}={1}" -f $_.Name, $_.Value } |


    Set-Content -Encoding UTF8 -Path $EnvSafe





  # ---- boot_config (first boot line in latest LIVE_OUT)


  $BootCfg = Join-Path $Stage ("boot_config_{0}.txt" -f $DayFile)


  $bootLine = 'NO_BOOT_LINE_FOUND'


  if ((SafeCount $Live) -gt 0) {


    $last = $Live | Select-Object -Last 1


    $m = Select-String -Path $last.FullName -Pattern '\|\s+boot\s+\{' -ErrorAction SilentlyContinue | Select-Object -First 1


    if ($m) { $bootLine = $m.Line }


  }


  WriteText $BootCfg @($bootLine)





  # ---- git state


  $GitOut = Join-Path $Stage ("git_state_{0}.txt" -f $DayFile)


  try {


    if (Test-Path -Path (Join-Path $Root '.git')) {


      $gs = @()


      $gs += ("ROOT={0}" -f $Root)


      $gs += ("DATE={0}" -f $Now.ToString('s'))


      $head = (& git rev-parse HEAD 2>$null)


      $gs += ("HEAD=" + $head)


      $gs += "STATUS_PORCELAIN:"


      $gs += (& git status --porcelain 2>$null)


      $gs += "DIFF_STAT:"


      $gs += (& git diff --stat 2>$null)


      WriteText $GitOut $gs


    } else {


      WriteText $GitOut @('NO_GIT_REPO')


    }


  } catch {


    WriteText $GitOut @('GIT_ERROR', $_.Exception.Message)


  }





  # ---- compile check


  $CompileOut = Join-Path $Stage ("compile_check_{0}.txt" -f $DayFile)


  $compileLines = @()


  $compileLines += ("python=" + (& python -V 2>&1))





  $compileTargets = @(


    (Join-Path $Root 'tbot\main.py'),


    (Join-Path $Root 'tbot\runtime\orchestrator.py'),


    (Join-Path $Root 'tbot\runtime\shadow_pricing.py')


  )





  foreach ($t in $compileTargets) {


    if (Test-Path -Path $t) {


      try { & python -m py_compile $t 2>$null; $compileLines += ("OK: py_compile " + $t) }


      catch { $compileLines += ("FAIL: py_compile " + $t) }


    } else {


      $compileLines += ("MISSING: " + $t)


    }


  }


  WriteText $CompileOut $compileLines





  # ---- pip freeze


  $PipOut = Join-Path $Stage ("pip_freeze_{0}.txt" -f $DayFile)


  try { (& python -m pip freeze 2>$null) | Set-Content -Encoding UTF8 -Path $PipOut }


  catch { WriteText $PipOut @('PIP_FREEZE_ERROR', $_.Exception.Message) }





  # ---- file hashes


  $HashOut = Join-Path $Stage ("file_hashes_{0}.txt" -f $DayFile)


  $hashLines = @()


  foreach ($t in $compileTargets) {


    if (Test-Path -Path $t) {


      $h = (Get-FileHash -Algorithm SHA256 -Path $t).Hash


      $hashLines += ("SHA256 {0} {1}" -f $h, $t)


    } else {


      $hashLines += ("MISSING {0}" -f $t)


    }


  }


  WriteText $HashOut $hashLines





  # ---- errors (WHOLE DAY across all LIVE_OUT)


  $err = [ordered]@{ traceback=0; importerror=0; apca_keys_missing=0; rate_429=0; fires_429=0; timeout=0; exception=0 }


  if ((SafeCount $livePaths) -gt 0) {


    $err.traceback         = (SafeCount @((Select-String -Path $livePaths -Pattern 'Traceback' -ErrorAction SilentlyContinue)))


    $err.importerror       = (SafeCount @((Select-String -Path $livePaths -Pattern 'ImportError' -ErrorAction SilentlyContinue)))


    $err.apca_keys_missing = (SafeCount @((Select-String -Path $livePaths -Pattern 'APCA_KEYS_MISSING' -ErrorAction SilentlyContinue)))


    # OLD_429_DETECTOR_DISABLED:     $err.rate_429          = (SafeCount @((Select-String -Path $livePaths -Pattern '\b429\b' -ErrorAction SilentlyContinue)))
    # RATE_LIMIT_429_STRICT_V2 (avoid false positives like 'fires: 429')
    # Only count real HTTP/API rate-limit signals
    $pat429 = '(?i)(\bHTTP\b.*\b429\b|\b429\b.*\btoo\s+many\s+requests\b|\btoo\s+many\s+requests\b.*\b429\b|\bstatus[_ ]?code\b\s*[:=]\s*429|\bcode\b\s*[:=]\s*429|\bretry-after\b|\brate[_ -]?limit(ed)?\b.*\b429\b|\b429\b.*\brate[_ -]?limit(ed)?\b)'
    $err.rate_429  = (SafeCount @((Select-String -Path $livePaths -Pattern $pat429 -ErrorAction SilentlyContinue)))
    # Track 'fires: 429' separately (NOT an HTTP 429)
    $err.fires_429 = (SafeCount @((Select-String -Path $livePaths -Pattern '(?i)\bfires:\s*429\b' -ErrorAction SilentlyContinue)))


    $err.timeout           = (SafeCount @((Select-String -Path $livePaths -Pattern 'timeout' -ErrorAction SilentlyContinue)))


    $err.exception         = (SafeCount @((Select-String -Path $livePaths -Pattern 'exception' -ErrorAction SilentlyContinue)))


  }





  # ---- daily summary (before run_index)


  $Summary  = Join-Path $Stage ("daily_summary_{0}.json" -f $DayFile)


  $QCOut    = Join-Path $Stage ("QC_{0}.txt" -f $DayFile)


  $Readme   = Join-Path $Stage ("README_{0}.txt" -f $DayFile)





  $MetaSrcValue = $null


  if (SafeTestPath $MetaSrc) { $MetaSrcValue = $MetaSrc }





  $AnnSrcValue = $null


  if (SafeTestPath $AnnSrc) { $AnnSrcValue = $AnnSrc }





  $sum = [ordered]@{


    dayfile = $DayFile


    iso_day = $IsoDay


    created = $Now.ToString('s')


    root = $Root





    live_out_count = (SafeCount $Live)


    shadow_src = $ShadowPath


    shadow_was_recovered = $shadow_was_recovered


    meta_src   = $MetaSrcValue


    announce_src = $AnnSrcValue





    shadow_lines = $shadow_lines


    meta_lines = $meta_lines


    announce_lines = $ann_lines





    errors = $err


  }





  ($sum | ConvertTo-Json -Depth 8) | Set-Content -Encoding UTF8 -Path $Summary





  # ---- QC


  $fail = @()


  $warn = @()





  if ((SafeCount $Live) -eq 0) { $fail += 'NO LIVE_OUT for today' }


  if (-not (Test-Path -Path $ShadowDay)) { $fail += 'NO shadow_plans day file produced' }





  if ($shadow_lines -lt 10) {
  if ($shadow_lines_full -ge 10) {
    $warn += 'shadow_plans DAY-SLICE low but FULL ok (ts/day filter mismatch)'
  } else {
    $warn += 'shadow_plans today is very low (<10 lines)'
  }
}


  if ($shadow_lines -eq 0)  {
  if ($shadow_lines_full -ge 10) {
    $warn += 'shadow_plans DAY-SLICE is ZERO but FULL ok (ts/day filter mismatch)'
  } else {
    $warn += 'shadow_plans today is ZERO'
  }
}





  if ($meta_lines -eq 0) { $warn += 'meta lines is ZERO (meta missing or no entries today)' }


  if ($ann_lines  -eq 0) { $warn += 'announce lines is ZERO (announce missing or no entries today)' }





  if ($err.traceback -gt 0 -or $err.importerror -gt 0) { $warn += 'Traceback/ImportError detected in LIVE_OUT (whole day)' }


  if ($err.apca_keys_missing -gt 0) { $warn += 'APCA_KEYS_MISSING found' }


  if ($err.rate_429 -gt 0) { $warn += 'HTTP 429 rate limit found' }





  $qcResult = 'PASS'


  if ((SafeCount $fail) -gt 0) { $qcResult = 'FAIL' }


  elseif ((SafeCount $warn) -gt 0) { $qcResult = 'WARN' }





  $qc = @()


  $qc += ("QC DATE={0}" -f $IsoDay)


  $qc += ("LIVE_OUT_COUNT={0}" -f (SafeCount $Live))


  $qc += ("SHADOW_LINES={0}" -f $shadow_lines)


  $qc += ("META_LINES={0}" -f $meta_lines)


  $qc += ("ANNOUNCE_LINES={0}" -f $ann_lines)


  $qc += ("SHADOW_SRC={0}" -f $ShadowPath)


  $qc += ("SHADOW_RECOVERED={0}" -f ($(if ($shadow_was_recovered) { 1 } else { 0 })))


  $qc += ("META_SRC={0}" -f ($(if ($MetaSrcValue) { $MetaSrcValue } else { 'NONE' })))


  $qc += ("ANNOUNCE_SRC={0}" -f ($(if ($AnnSrcValue) { $AnnSrcValue } else { 'NONE' })))


  $qc += ("ERRORS={0}" -f (($err | ConvertTo-Json -Compress)))


  $qc += ("FAIL={0}" -f ($fail -join ' | '))


  $qc += ("WARN={0}" -f ($warn -join ' | '))


  $qc += ("QC_RESULT={0}" -f $qcResult)


  WriteText $QCOut $qc





  # README


  WriteText $Readme @(


    'TBOT ENTERPRISE FREEZE PACKAGE',


    ("ISO_DAY={0}" -f $IsoDay),


    ("CREATED={0}" -f $Now.ToString('s')),


    ("ROOT={0}" -f $Root),


    ("QC_RESULT={0}" -f $qcResult),


    'See: daily_summary + run_index + QC for details.'


  )





  # ---- run_index (GENERATE LAST)


  $RunIndex = Join-Path $Stage ("run_index_{0}.json" -f $DayFile)


  $files = Get-ChildItem -Path $Stage -File | Select-Object Name, Length, LastWriteTime


  ($files | ConvertTo-Json -Depth 4) | Set-Content -Encoding UTF8 -Path $RunIndex





  # ---- ZIP + backup


  $Zip = Join-Path $Freeze ("FREEZE_TODAY_{0}_{1}.zip" -f $DayFile, $Stamp)


  Compress-Archive -Path (Join-Path $Stage '*') -DestinationPath $Zip -Force





  Copy-Item -Force -Path $Zip -Destination $BK


  Get-ChildItem -Path $Stage -File | ForEach-Object { Copy-Item -Force -Path $_.FullName -Destination $BK }





  # ---- Self verify: QC_RESULT must exist


  Add-Type -AssemblyName System.IO.Compression.FileSystem


  $z = [System.IO.Compression.ZipFile]::OpenRead($Zip)


  try {


    $qcEntry = $z.Entries | Where-Object { $_.FullName -like 'QC_*.txt' } | Select-Object -First 1


    if (-not $qcEntry) { throw "Self-verify failed: QC_*.txt missing" }





    $sr = New-Object System.IO.StreamReader($qcEntry.Open(), [System.Text.Encoding]::UTF8, $true)


    try { $qcText = $sr.ReadToEnd() } finally { $sr.Dispose() }





    $qcLine = ($qcText -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^QC_RESULT=' } | Select-Object -First 1)


    if ([string]::IsNullOrWhiteSpace($qcLine)) { throw "Self-verify failed: QC_RESULT missing inside QC file" }





    Write-Host "`nSELF_VERIFY=PASS"


    Write-Host ("ZIP CREATED: " + $Zip)


    Write-Host ("BACKUP FOLDER: " + $BK)


    Write-Host ("QC_RESULT: " + $qcResult)


  } finally {


    if ($z) { $z.Dispose() }


  }





} finally {


  if (Test-Path -Path $Stage) {


    Remove-Item -Recurse -Force -Path $Stage -ErrorAction SilentlyContinue


  }


}





$code = 0


if ($qcResult -eq 'WARN') { $code = 1 }


elseif ($qcResult -eq 'FAIL') { $code = 2 }


Write-Host ("FREEZE_EXIT_CODE=" + $code)


exit $code









