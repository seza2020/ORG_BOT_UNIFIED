param()

$ErrorActionPreference="Stop"
$PROJECT_ROOT="C:\alpaca-bot\org_bot"
$PAPER_RUNROOT="C:\alpaca-bot\org_bot_runtime\paper"
$API_BASE="http://127.0.0.1:8008"
$PHASE="PHASE_1_ADVISORY_ONLY"

$STAMP=Get-Date -Format "yyyyMMdd_HHmmss"
$OUTDIR=Join-Path $PROJECT_ROOT "_MYGPT_UPLOAD\LLM_LOOP_AUDIT_PACK_$STAMP"
New-Item -ItemType Directory -Force $OUTDIR | Out-Null

$EVID=Join-Path $OUTDIR "evidence"
$CODE=Join-Path $OUTDIR "code"
$CONF=Join-Path $OUTDIR "config"
New-Item -ItemType Directory -Force $EVID,$CODE,$CONF | Out-Null

# Policy doc
@(
  "# LLM Loop Access Policy"
  "TS=$STAMP"
  "PHASE=$PHASE"
  "PROJECT_ROOT=$PROJECT_ROOT"
  "PAPER_RUNROOT=$PAPER_RUNROOT"
  "API_BASE=$API_BASE"
) | Set-Content -Encoding utf8 (Join-Path $OUTDIR "ACCESS_POLICY.md")

# Collect minimal evidence
schtasks /query /fo LIST | Set-Content -Encoding utf8 (Join-Path $EVID "tasks_full.txt")
Get-ChildItem env:* | Sort-Object Name | Set-Content -Encoding utf8 (Join-Path $EVID "env_dump.txt")

# API health + sample decide
$val=Join-Path $EVID "validation.txt"
$healthOk=0; $decideOk=0

try{
  $h=Invoke-RestMethod "$API_BASE/health" -TimeoutSec 2
  if($h.ok -eq $true){ $healthOk=1 }
}catch{}

try{
  $body=@{
    symbol="SPY"; side="BUY"; confidence=0.70;
    features=@{ rsi=55; vwap_state="ABOVE" };
    meta=@{ phase=$PHASE; ts=(Get-Date).ToString("o") }
  } | ConvertTo-Json -Depth 10

  $d=Invoke-RestMethod -Method Post -Uri "$API_BASE/decide" -ContentType "application/json" -Body $body -TimeoutSec 2
  if($d){ $decideOk=1 }
}catch{}

@(
  "TS=$STAMP"
  "PHASE=$PHASE"
  "API_BASE=$API_BASE"
  "HEALTH_OK=$healthOk"
  "DECIDE_OK=$decideOk"
) | Set-Content -Encoding utf8 $val

# Zip
$ZIP="$OUTDIR.zip"
if(Test-Path $ZIP){ Remove-Item $ZIP -Force }
Compress-Archive -Path "$OUTDIR\*" -DestinationPath $ZIP -Force

"PACK_READY=$ZIP"