param([string]$ProjectRoot="C:\alpaca-bot\org_bot")
$ErrorActionPreference="Stop"

# Load secrets from profile if env not set (does NOT print secrets)
if([string]::IsNullOrWhiteSpace(([string]$env:APCA_API_KEY_ID).Trim())){
  $prof = Get-Content -Raw -Encoding UTF8 (Join-Path $ProjectRoot "tools\profiles\paper.profile.json") | ConvertFrom-Json
  $sec = [string]$prof.secrets_ps1
  if($sec -and (Test-Path $sec)){ . $sec }
}

. (Join-Path $ProjectRoot "tools\paper\ALPACA_PAPER_REST_V1.ps1")

$acct = Get-ApcaAccount
"ACCOUNT_STATUS=$($acct.status)"
"OK=PAPER_SMOKE_CHECK_DONE"
