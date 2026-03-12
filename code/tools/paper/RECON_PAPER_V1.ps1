param(
  [string]$ProjectRoot="C:\alpaca-bot\org_bot",
  [string]$RunRoot="C:\alpaca-bot\org_bot_runtime\paper",
  [string]$IsoDayOverride=""
)
$ErrorActionPreference="Stop"

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

# Load secrets from profile if needed
if([string]::IsNullOrWhiteSpace(([string]$env:APCA_API_KEY_ID).Trim())){
  $prof = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot "tools\profiles\paper.profile.json") | ConvertFrom-Json
  $sec = [string]$prof.secrets_ps1
  if($sec -and (Test-Path $sec)){ . $sec }
}

. (Join-Path $ProjectRoot "tools\paper\ALPACA_PAPER_REST_V1.ps1")

$ops = Join-Path $RunRoot "logs\ops"
$led = Join-Path $RunRoot "logs\ledger"
New-Item -ItemType Directory -Force -Path $ops,$led | Out-Null

if([string]::IsNullOrWhiteSpace($IsoDayOverride)){
  $IsoDayOverride=(Get-Date).ToString("yyyy-MM-dd")
}
$ymd=$IsoDayOverride.Replace("-","")
$ledgerPath = Join-Path $led ("LEDGER_REAL_{0}.jsonl" -f $ymd)

$after = "$IsoDayOverride" + "T00:00:00Z"
$until = "$IsoDayOverride" + "T23:59:59Z"

$orders=@()
try { $orders = @(List-ApcaOrders -Status "all" -After $after -Until $until -Limit 500) } catch { $orders=@() }

$ledgerIds=@{}
if(Test-Path $ledgerPath){
  Get-Content $ledgerPath | ForEach-Object {
    try{
      $o = $_ | ConvertFrom-Json
      if($o.client_order_id){ $ledgerIds[$o.client_order_id]=1 }
    } catch {}
  }
}

$byClient=@{}
foreach($o in $orders){
  if($o.client_order_id){ $byClient[$o.client_order_id]=$o }
}

$missingOnBroker=@()
foreach($k in $ledgerIds.Keys){
  if(-not $byClient.ContainsKey($k)){ $missingOnBroker += $k }
}

$summary=@{
  isoday=$IsoDayOverride
  ledger_path=$ledgerPath
  orders_count=$orders.Count
  ledger_client_ids=$ledgerIds.Count
  missing_on_broker=$missingOnBroker
  status = $( if($missingOnBroker.Count -gt 0){"WARN"} else {"PASS"} )
}

$out = Join-Path $led ("RECON_PAPER_{0}.json" -f $ymd)
($summary | ConvertTo-Json -Depth 20) | Set-Content -Encoding UTF8 -Path $out
$out


