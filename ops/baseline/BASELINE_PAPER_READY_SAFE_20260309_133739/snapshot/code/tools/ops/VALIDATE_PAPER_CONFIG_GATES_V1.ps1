# === AUDIT_GRADE_VALIDATOR_SAFE_V1 ===
param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride=""
)

# --- TBOT_PROFILE_COMPAT_V2 ---
# TBOT_PROFILE legacy may be NAME (PAPER|SHADOW) OR PATH to *.profile.json
$tbp = [string]$env:TBOT_PROFILE
$env:TBOT_PROFILE_NAME = [string]$env:TBOT_PROFILE_NAME
$env:TBOT_PROFILE_PATH = [string]$env:TBOT_PROFILE_PATH
if([string]::IsNullOrWhiteSpace($env:TBOT_PROFILE_PATH) -and -not [string]::IsNullOrWhiteSpace($ProfilePath)){ $env:TBOT_PROFILE_PATH = $ProfilePath }

# If TBOT_PROFILE looks like a path, normalize it and set NAME + legacy TBOT_PROFILE=NAME for backward checks
if(-not [string]::IsNullOrWhiteSpace($tbp) -and ($tbp -match "^[A-Za-z]:\\" -or $tbp -match "\\\\")){
  $env:TBOT_PROFILE_PATH = $tbp
  if($tbp -match "(?i)\\paper\.profile\.json$"){
    $env:TBOT_PROFILE_NAME = "PAPER"
    $env:TBOT_PROFILE = "PAPER"
  } elseif($tbp -match "(?i)\\shadow\.profile\.json$"){
    $env:TBOT_PROFILE_NAME = "SHADOW"
    $env:TBOT_PROFILE = "SHADOW"
  }
} else {
  # If TBOT_PROFILE is NAME, keep it and infer path if possible
  if($tbp -match "^(?i)(PAPER|SHADOW)$"){
    $env:TBOT_PROFILE_NAME = $tbp.ToUpper()
    if([string]::IsNullOrWhiteSpace($env:TBOT_PROFILE_PATH) -and -not [string]::IsNullOrWhiteSpace($ProfilePath)){ $env:TBOT_PROFILE_PATH = $ProfilePath }
  }
}

Write-Host ("PROFILE_NAME=" + [string]$env:TBOT_PROFILE_NAME)
Write-Host ("PROFILE_PATH=" + [string]$env:TBOT_PROFILE_PATH)
Write-Host ("TBOT_PROFILE_LEGACY=" + [string]$env:TBOT_PROFILE)
# --- TBOT_PROFILE_COMPAT_V2 END ---


# --- PROFILE_SPLIT_V1 ---
# Canonical:
#   TBOT_PROFILE_NAME = PAPER|SHADOW
#   TBOT_PROFILE_PATH = full path to *.profile.json
# Back-compat:
#   TBOT_PROFILE may be either NAME or PATH.
$tbp = [string]$env:TBOT_PROFILE
$env:TBOT_PROFILE_NAME = [string]$env:TBOT_PROFILE_NAME
$env:TBOT_PROFILE_PATH = [string]$env:TBOT_PROFILE_PATH

if([string]::IsNullOrWhiteSpace($env:TBOT_PROFILE_PATH) -and -not [string]::IsNullOrWhiteSpace($ProfilePath)){
  $env:TBOT_PROFILE_PATH = $ProfilePath
}

if([string]::IsNullOrWhiteSpace($env:TBOT_PROFILE_NAME)){
  if($tbp -match '^(?i)(PAPER|SHADOW)$'){
    $env:TBOT_PROFILE_NAME = $tbp.ToUpper()
  } elseif($env:TBOT_PROFILE_PATH -match '(?i)\\paper\.profile\.json$'){
    $env:TBOT_PROFILE_NAME = "PAPER"
  } elseif($env:TBOT_PROFILE_PATH -match '(?i)\\shadow\.profile\.json$'){
    $env:TBOT_PROFILE_NAME = "SHADOW"
  }
}

Write-Host ("PROFILE_NAME=" + $env:TBOT_PROFILE_NAME)
Write-Host ("PROFILE_PATH=" + $env:TBOT_PROFILE_PATH)
# --- PROFILE_SPLIT_V1 END ---
$ErrorActionPreference="Stop"

function Get-EnvSafeMap([string]$RunRoot){
  $ops = Join-Path $RunRoot "logs\ops"
  $f = Get-ChildItem $ops -Filter "env_TBOT_SAFE_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Desc | Select-Object -First 1
  $m=@{}
  if($f){
    foreach($line in (Get-Content $f.FullName -ErrorAction SilentlyContinue)){
      if($line -match '^\s*([^=]+)=(.*)\s*$'){
        $k=$matches[1].Trim(); $v=$matches[2].Trim()
        if($k){ $m[$k]=$v }
      }
    }
    $m["_SRC"]=$f.Name
  }
  return $m
}
function Try-Num($x){ try { return [double]$x } catch { return $null } }
function Try-Int($x){ try { return [int]$x } catch { return $null } }

if([string]::IsNullOrWhiteSpace($IsoDayOverride)){ $IsoDayOverride=(Get-Date).ToString("yyyy-MM-dd") }
$ymd=$IsoDayOverride.Replace("-","")

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
New-Item -ItemType Directory -Force -Path $ops,$ana | Out-Null

# Load profile
$pp = Join-Path $ProjectRoot "tools\profiles\paper.profile.json"
$pj = Get-Content -Raw -Encoding UTF8 $pp | ConvertFrom-Json
$envObj = $null
if($pj.PSObject.Properties.Match("env").Count -gt 0){ $envObj = $pj.env }

# Load env safe snapshot (best effort)
$envSafe = Get-EnvSafeMap $RunRoot
$envSafeSrc = [string]$envSafe["_SRC"]

function Get-Value([string[]]$keys){
  foreach($k in $keys){
    if($envObj -and $envObj.PSObject.Properties.Match($k).Count -gt 0){
      return @{v=$envObj.$k; src=("paper.profile.json:env.{0}" -f $k)}
    }
    if($pj.PSObject.Properties.Match($k).Count -gt 0){
      return @{v=$pj.$k; src=("paper.profile.json:{0}" -f $k)}
    }
    if($envSafe.ContainsKey($k)){
      return @{v=$envSafe[$k]; src=("{0}:{1}" -f $envSafeSrc,$k)}
    }
  }
  return $null
}

$errors=@()
$warnings=@()

function HardFailMissing([string]$name){ $script:errors += ("MISSING:{0}" -f $name) }
function HardFail([string]$msg){ $script:errors += ("INVALID:{0}" -f $msg) }

# ----------------------
# HARD GATES (must exist and be valid)
# ----------------------

# (A) Base config gates you already enforce
$mr = Get-Value @("max_risk_usd","TBOT_MAX_RISK_USD","MAX_RISK_USD")
$cd = Get-Value @("cooldown_sec","TBOT_COOLDOWN_SEC","COOLDOWN_SEC")
$en = Get-Value @("entry","TBOT_ENTRY","ENTRY")

$max_risk_usd = if($mr){ Try-Num $mr.v } else { $null }
$cooldown_sec = if($cd){ Try-Num $cd.v } else { $null }
$entry = if($en){ Try-Int $en.v } else { $null }

if($max_risk_usd -eq $null){ HardFailMissing "max_risk_usd (or TBOT_MAX_RISK_USD)" }
elseif($max_risk_usd -le 0){ HardFail ("max_risk_usd<=0 value=$max_risk_usd src=$($mr.src)") }

if($cooldown_sec -eq $null){ HardFailMissing "cooldown_sec (or TBOT_COOLDOWN_SEC)" }
elseif($cooldown_sec -le 0){ HardFail ("cooldown_sec<=0 value=$cooldown_sec src=$($cd.src)") }
elseif($cooldown_sec -lt 20){ HardFail ("cooldown_sec<20 value=$cooldown_sec src=$($cd.src)") }

if($entry -eq $null){ HardFailMissing "entry (or TBOT_ENTRY)" }
elseif($entry -ne 100){ HardFail ("entry!=100 value=$entry src=$($en.src)") }

# (B) Day-1 execution limits
$sleep = Get-Value @("sleep_sec","TBOT_SLEEP_SEC")
$maxConc = Get-Value @("max_concurrent_orders","TBOT_MAX_CONCURRENT_ORDERS")
$maxSymAct = Get-Value @("max_symbols_active","TBOT_MAX_SYMBOLS_ACTIVE")
$allowOOS = Get-Value @("allow_out_of_session","TBOT_ALLOW_OUT_OF_SESSION")

$sleep_sec = if($sleep){ Try-Num $sleep.v } else { $null }
$max_concurrent_orders = if($maxConc){ Try-Int $maxConc.v } else { $null }
$max_symbols_active = if($maxSymAct){ Try-Int $maxSymAct.v } else { $null }
$allow_out_of_session = if($allowOOS){ Try-Int $allowOOS.v } else { $null }

if($sleep_sec -eq $null){ HardFailMissing "sleep_sec" }
elseif($sleep_sec -le 0){ HardFail ("sleep_sec<=0 value=$sleep_sec src=$($sleep.src)") }
elseif($sleep_sec -gt 10){ HardFail ("sleep_sec>10 value=$sleep_sec src=$($sleep.src)") }

if($max_concurrent_orders -eq $null){ HardFailMissing "max_concurrent_orders" }
elseif($max_concurrent_orders -lt 1){ HardFail ("max_concurrent_orders<1 value=$max_concurrent_orders src=$($maxConc.src)") }
elseif($max_concurrent_orders -gt 5){ HardFail ("max_concurrent_orders>5 value=$max_concurrent_orders src=$($maxConc.src)") }

if($max_symbols_active -eq $null){ HardFailMissing "max_symbols_active" }
elseif($max_symbols_active -lt 1){ HardFail ("max_symbols_active<1 value=$max_symbols_active src=$($maxSymAct.src)") }
elseif($max_symbols_active -gt 20){ HardFail ("max_symbols_active>20 value=$max_symbols_active src=$($maxSymAct.src)") }

if($allow_out_of_session -eq $null){ HardFailMissing "allow_out_of_session" }
elseif($allow_out_of_session -notin 0,1){ HardFail ("allow_out_of_session not 0/1 value=$allow_out_of_session src=$($allowOOS.src)") }
elseif($allow_out_of_session -ne 0){ HardFail ("allow_out_of_session must be 0 for Day1 value=$allow_out_of_session src=$($allowOOS.src)") }

# (C) Gate quality
$gcd = Get-Value @("gate_cooldown_sec","TBOT_GATE_COOLDOWN_SEC")
$gmpd = Get-Value @("gate_max_plans_per_day","TBOT_GATE_MAX_PLANS_PER_DAY")
$gconf = Get-Value @("gate_min_conf","TBOT_GATE_MIN_CONF")
$grr = Get-Value @("gate_min_rr","TBOT_GATE_MIN_RR")

$gate_cooldown_sec = if($gcd){ Try-Num $gcd.v } else { $null }
$gate_max_plans_per_day = if($gmpd){ Try-Int $gmpd.v } else { $null }
$gate_min_conf = if($gconf){ Try-Num $gconf.v } else { $null }
$gate_min_rr = if($grr){ Try-Num $grr.v } else { $null }

if($gate_cooldown_sec -eq $null){ HardFailMissing "gate_cooldown_sec" }
elseif($gate_cooldown_sec -le 0){ HardFail ("gate_cooldown_sec<=0 value=$gate_cooldown_sec src=$($gcd.src)") }

if($gate_max_plans_per_day -eq $null){ HardFailMissing "gate_max_plans_per_day" }
elseif($gate_max_plans_per_day -lt 1){ HardFail ("gate_max_plans_per_day<1 value=$gate_max_plans_per_day src=$($gmpd.src)") }
elseif($gate_max_plans_per_day -gt 500){ HardFail ("gate_max_plans_per_day>500 value=$gate_max_plans_per_day src=$($gmpd.src)") }

if($gate_min_conf -eq $null){ HardFailMissing "gate_min_conf" }
elseif($gate_min_conf -le 0 -or $gate_min_conf -gt 1){ HardFail ("gate_min_conf not in (0,1] value=$gate_min_conf src=$($gconf.src)") }

if($gate_min_rr -eq $null){ HardFailMissing "gate_min_rr" }
elseif($gate_min_rr -lt 1.0){ HardFail ("gate_min_rr<1.0 value=$gate_min_rr src=$($grr.src)") }

# (D) Risk controls
$rpt = Get-Value @("risk_per_trade_usd","TBOT_RISK_PER_TRADE_USD")
$gmr = Get-Value @("gate_max_risk_usd","TBOT_GATE_MAX_RISK_USD")
$gday = Get-Value @("gate_max_risk_per_day_usd","TBOT_GATE_MAX_RISK_PER_DAY_USD")
$wmax = Get-Value @("weekly_max_risk_usd","TBOT_WEEKLY_MAX_RISK_USD")

$risk_per_trade_usd = if($rpt){ Try-Num $rpt.v } else { $null }
$gate_max_risk_usd = if($gmr){ Try-Num $gmr.v } else { $null }
$gate_max_risk_per_day_usd = if($gday){ Try-Num $gday.v } else { $null }
$weekly_max_risk_usd = if($wmax){ Try-Num $wmax.v } else { $null }

if($risk_per_trade_usd -eq $null){ HardFailMissing "risk_per_trade_usd" }
elseif($risk_per_trade_usd -le 0){ HardFail ("risk_per_trade_usd<=0 value=$risk_per_trade_usd src=$($rpt.src)") }

if($gate_max_risk_usd -eq $null){ HardFailMissing "gate_max_risk_usd" }
elseif($gate_max_risk_usd -le 0){ HardFail ("gate_max_risk_usd<=0 value=$gate_max_risk_usd src=$($gmr.src)") }

if($gate_max_risk_per_day_usd -eq $null){ HardFailMissing "gate_max_risk_per_day_usd" }
elseif($gate_max_risk_per_day_usd -le 0){ HardFail ("gate_max_risk_per_day_usd<=0 value=$gate_max_risk_per_day_usd src=$($gday.src)") }

if($weekly_max_risk_usd -eq $null){ HardFailMissing "weekly_max_risk_usd" }
elseif($weekly_max_risk_usd -le 0){ HardFail ("weekly_max_risk_usd<=0 value=$weekly_max_risk_usd src=$($wmax.src)") }

# cross-checks
if($risk_per_trade_usd -ne $null -and $gate_max_risk_usd -ne $null -and $risk_per_trade_usd -gt $gate_max_risk_usd){
  HardFail ("risk_per_trade_usd>gate_max_risk_usd risk=$risk_per_trade_usd max=$gate_max_risk_usd")
}
if($risk_per_trade_usd -ne $null -and $gate_max_risk_per_day_usd -ne $null -and $risk_per_trade_usd -gt $gate_max_risk_per_day_usd){
  HardFail ("risk_per_trade_usd>gate_max_risk_per_day_usd risk=$risk_per_trade_usd day=$gate_max_risk_per_day_usd")
}
if($gate_max_risk_per_day_usd -ne $null -and $weekly_max_risk_usd -ne $null -and $gate_max_risk_per_day_usd -gt $weekly_max_risk_usd){
  HardFail ("gate_max_risk_per_day_usd>weekly_max_risk_usd day=$gate_max_risk_per_day_usd week=$weekly_max_risk_usd")
}

# (E) Mandatory kill/quality flags (must be 1)
$mustOn = @(
  "kill_on_duplicate_orders","kill_on_stop_missing","kill_on_tp_missing","kill_on_price_synthetic","kill_on_config_invalid",
  "rotate_shadow_plans_at_start","enforce_single_instance","qc_must_pass_before_start","eod_freeze_required"
)
foreach($k in $mustOn){
  $v = Get-Value @($k, ("TBOT_{0}" -f $k.ToUpper()))
  $iv = if($v){ Try-Int $v.v } else { $null }
  if($iv -eq $null){ HardFailMissing $k }
  elseif($iv -ne 1){ HardFail ("{0} must be 1 value={1} src={2}" -f $k,$iv,$v.src) }
}

# (F) symbols must be non-empty
$sy = Get-Value @("symbols","TBOT_SYMBOLS")
$symbols=@()
if($sy){
  $raw=[string]$sy.v
  if($raw.Trim().StartsWith("[") -and $raw.Trim().EndsWith("]")){
    try { $symbols = @((ConvertFrom-Json $raw)) } catch { $symbols=@() }
  } else {
    $symbols = @($raw.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  }
}
if($symbols.Count -lt 1){ HardFail ("symbols empty src=" + ($(if($sy){$sy.src}else{"(missing)"}))) }

# FILELOG_PATH_GUARD_V1 (prevent cross-root log/state contamination)
$fl = Get-Value @("TBOT_FILELOG_PATH","filelog_path")
$flv = if($fl){ [string]$fl.v } else { "" }
if([string]::IsNullOrWhiteSpace($flv)){
  HardFailMissing "TBOT_FILELOG_PATH"
} else {
  $flv2 = $flv.ToLower()
  $rr2  = ([string]$RunRoot).ToLower()
  if($flv2 -like "*ibkr-bot*"){
    HardFail ("TBOT_FILELOG_PATH points to ibkr-bot value=" + $flv + " src=" + $fl.src)
  }
  if($rr2 -and ($flv2 -notlike ($rr2 + "*"))){
    HardFail ("TBOT_FILELOG_PATH not under RunRoot value=" + $flv + " runroot=" + $RunRoot + " src=" + $fl.src)
  }
}

# PROFILE_RUNROOT_MISMATCH_GUARD_V5 (hard fail on cross-profile)
$expectedProf = $null
try{
  $rr = ([string]$RunRoot).ToLower()
  if($rr -like "*\shadow*"){ $expectedProf="SHADOW" }
  elseif($rr -like "*\paper*"){ $expectedProf="PAPER" }
} catch {}
$actualProf = ([string]$env:TBOT_PROFILE).Trim().ToUpper()
if([string]::IsNullOrWhiteSpace($expectedProf)){
  if([string]::IsNullOrWhiteSpace($actualProf)){ HardFailMissing "TBOT_PROFILE" }
} else {
  if([string]::IsNullOrWhiteSpace($actualProf)){ HardFailMissing "TBOT_PROFILE" }
  elseif($actualProf -ne $expectedProf){
    HardFail ("TBOT_PROFILE mismatch expected=" + $expectedProf + " actual=" + $actualProf + " runroot=" + $RunRoot)
  }
}

$status = $(if($errors.Count -gt 0){"FAIL"} else {"PASS"})

$report = @{
  isoday=$IsoDayOverride
  status=$status
  values=@{
    max_risk_usd=$max_risk_usd; cooldown_sec=$cooldown_sec; entry=$entry
    sleep_sec=$sleep_sec; max_concurrent_orders=$max_concurrent_orders; max_symbols_active=$max_symbols_active; allow_out_of_session=$allow_out_of_session
    gate_cooldown_sec=$gate_cooldown_sec; gate_max_plans_per_day=$gate_max_plans_per_day; gate_min_conf=$gate_min_conf; gate_min_rr=$gate_min_rr
    risk_per_trade_usd=$risk_per_trade_usd; gate_max_risk_usd=$gate_max_risk_usd; gate_max_risk_per_day_usd=$gate_max_risk_per_day_usd; weekly_max_risk_usd=$weekly_max_risk_usd
    symbols=$symbols
  }
  errors=$errors
  warnings=$warnings
}

$rj_ops = Join-Path $ops ("CONFIG_GATES_{0}.json" -f $ymd)
$rt_ops = Join-Path $ops ("CONFIG_GATES_{0}.txt" -f $ymd)
$rj_ana = Join-Path $ana ("CONFIG_GATES_{0}.json" -f $ymd)
$rt_ana = Join-Path $ana ("CONFIG_GATES_{0}.txt" -f $ymd)

($report | ConvertTo-Json -Depth 40) | Set-Content -Encoding UTF8 -Path $rj_ops
($report | ConvertTo-Json -Depth 40) | Set-Content -Encoding UTF8 -Path $rj_ana

@(
  "CONFIG_GATES_STATUS=$status",
  "isoday=$IsoDayOverride",
  "errors_count=$($errors.Count)",
  "warnings_count=$($warnings.Count)"
) + ($errors | ForEach-Object { "ERR=$_"} ) + ($warnings | ForEach-Object { $_ }) |
  Set-Content -Encoding UTF8 -Path $rt_ops

Copy-Item $rt_ops $rt_ana -Force


# --- AUDIT PRINT/REPORT (injected) ---
try {
  if($errors -and $errors.Count -gt 0){
    Write-Host "=== VALIDATION_ERRORS_BEGIN ==="
    $errors | ForEach-Object { Write-Host $_ }
    Write-Host "=== VALIDATION_ERRORS_END ==="
  }
  if($warnings -and $warnings.Count -gt 0){
    Write-Host "=== VALIDATION_WARNINGS_BEGIN ==="
    $warnings | ForEach-Object { Write-Host $_ }
    Write-Host "=== VALIDATION_WARNINGS_END ==="
  }
  $rdir = Join-Path $ProjectRoot "logs\ops\validator_reports"
  New-Item -ItemType Directory -Force $rdir | Out-Null
  $rfile = Join-Path $rdir ("VALIDATOR_PAPER_{0}.txt" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
  ("RUNROOT=" + $RunRoot) | Out-File -LiteralPath $rfile -Encoding utf8
  ("ERRORS_COUNT=" + ($errors.Count)) | Out-File -LiteralPath $rfile -Append
  ("WARN_COUNT=" + ($warnings.Count)) | Out-File -LiteralPath $rfile -Append
  "---- ERRORS ----" | Out-File -LiteralPath $rfile -Append
  $errors | Out-File -LiteralPath $rfile -Append
  "---- WARNINGS ----" | Out-File -LiteralPath $rfile -Append
  $warnings | Out-File -LiteralPath $rfile -Append
  Write-Host ("VALIDATION_REPORT=" + $rfile)
} catch {
  Write-Host ("VALIDATION_REPORT_WRITE_FAILED: " + $_.Exception.Message)
}
# --- AUDIT PRINT/REPORT END ---

if($status -eq "FAIL"){ exit 1 } else { exit 0 }



# === LLM_GATE_VALIDATION_V1 ===
if($env:TBOT_LLM_GATE_ENABLED -eq "1"){
  if([string]::IsNullOrWhiteSpace($env:TBOT_LOCAL_API_URL)){
    throw "VALIDATE_FAIL: TBOT_LOCAL_API_URL missing while TBOT_LLM_GATE_ENABLED=1"
  }
  if($env:TBOT_LOCAL_API_URL -notmatch '^http://127\.0\.0\.1:8008/'){
    throw "VALIDATE_FAIL: TBOT_LOCAL_API_URL must be local 127.0.0.1:8008/* for Phase_1"
  }

  $gap = 0
  [int]::TryParse([string]$env:TBOT_LLM_GATE_MIN_GAP_SEC, [ref]$gap) | Out-Null
  if($gap -lt 5){
    throw "VALIDATE_FAIL: TBOT_LLM_GATE_MIN_GAP_SEC must be >= 5 (recommend 10+)"
  }

  $to = 0
  [int]::TryParse([string]$env:TBOT_LLM_GATE_TIMEOUT_SEC, [ref]$to) | Out-Null
  if($to -lt 1 -or $to -gt 10){
    throw "VALIDATE_FAIL: TBOT_LLM_GATE_TIMEOUT_SEC must be 1..10"
  }
}
# ============================

