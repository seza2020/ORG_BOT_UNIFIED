param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride="",
  [int]$MaxOrders=1,
  [int]$DefaultQty=1
)
$ErrorActionPreference="Stop"

if(Test-Path (Join-Path $RunRoot "KILL_SWITCH")){
  "KILL_SWITCH_PRESENT=1 (no execute)"; exit 0
}

# Load secrets from profile if needed
if([string]::IsNullOrWhiteSpace(([string]$env:APCA_API_KEY_ID).Trim())){
  $prof = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot "tools\profiles\paper.profile.json") | ConvertFrom-Json
  $sec = [string]$prof.secrets_ps1
  if($sec -and (Test-Path $sec)){ . $sec }
}

. (Join-Path $ProjectRoot "tools\paper\ALPACA_PAPER_REST_V1.ps1")

$ops = Join-Path $RunRoot "logs\ops"
$ana = Join-Path $RunRoot "logs\analytics"
$led = Join-Path $RunRoot "logs\ledger"
New-Item -ItemType Directory -Force -Path $ops,$ana,$led | Out-Null

# Determine ISO day if missing (prefer LIVE_OUT filename)
if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  $lo = Get-ChildItem -Path $ops -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if($lo){
    $m=[regex]::Match($lo.Name,"^LIVE_OUT_(\d{4})(\d{2})(\d{2})")
    if($m.Success){ $IsoDayOverride = "{0}-{1}-{2}" -f $m.Groups[1].Value,$m.Groups[2].Value,$m.Groups[3].Value }
  }
  if([string]::IsNullOrWhiteSpace($IsoDayOverride)){ $IsoDayOverride=(Get-Date).ToString("yyyy-MM-dd") }
}
$ymd = $IsoDayOverride.Replace("-","")

$selPath = Join-Path $ana ("PLAN_SELECTION_{0}.json" -f $ymd)
if(!(Test-Path $selPath)){ "NO_SELECTION_FILE=$selPath"; exit 0 }

$sel = Get-Content -Raw -Encoding UTF8 $selPath | ConvertFrom-Json
$selected = @($sel.selected)
if($selected.Count -eq 0){ "SELECTION_EMPTY=1"; exit 0 }

$ledgerPath = Join-Path $led ("LEDGER_REAL_{0}.jsonl" -f $ymd)

# Existing client IDs to avoid duplicates
$existing=@{}
if(Test-Path $ledgerPath){
  Get-Content $ledgerPath -ErrorAction SilentlyContinue | ForEach-Object {
    try{
      $o = $_ | ConvertFrom-Json
      if($o.client_order_id){ $existing[$o.client_order_id]=1 }
    } catch {}
  }
}

$submitted=0; $skipped=0; $errors=0
$ts=(Get-Date).ToString("s")

foreach($i in 0..($selected.Count-1)){
  if($submitted -ge $MaxOrders){ break }

  $c=$selected[$i]
  $sym=[string]$c.sym
  if([string]::IsNullOrWhiteSpace($sym)){ $skipped++; continue }

  $sideRaw=([string]$c.side).ToLowerInvariant()
  $side="buy"
  if($sideRaw -match "sell|short"){ $side="sell" }

  $clientId = ("TBOT-PAPER-{0}-{1}-{2}-{3}" -f $ymd,$i,$sym,$side)
  if($existing.ContainsKey($clientId)){ $skipped++; continue }

  @{ ts=$ts; kind="order_intent"; isoday=$IsoDayOverride; sym=$sym; side=$side; qty=$DefaultQty; client_order_id=$clientId } |
    ConvertTo-Json -Compress | Add-Content -Encoding UTF8 -Path $ledgerPath

  try {
    $o = Submit-ApcaOrder -Symbol $sym -Qty $DefaultQty -Side $side -Type "market" -TIF "day" -ClientOrderId $clientId
    $submitted++
    @{ ts=$ts; kind="order_submitted"; isoday=$IsoDayOverride; sym=$sym; side=$side; qty=$DefaultQty; client_order_id=$clientId; order_id=$o.id; status=$o.status } |
      ConvertTo-Json -Compress | Add-Content -Encoding UTF8 -Path $ledgerPath
    $existing[$clientId]=1
  } catch {
    $errors++
    @{ ts=$ts; kind="order_error"; isoday=$IsoDayOverride; sym=$sym; side=$side; qty=$DefaultQty; client_order_id=$clientId; err=$_.Exception.Message } |
      ConvertTo-Json -Compress | Add-Content -Encoding UTF8 -Path $ledgerPath
  }
}

"ISO_DAY_USED=$IsoDayOverride"
"SUBMITTED=$submitted SKIPPED=$skipped ERRORS=$errors"
"LEDGER_REAL=$ledgerPath"
"OK=EXECUTE_PLAN_SELECTION_PAPER_DONE"
