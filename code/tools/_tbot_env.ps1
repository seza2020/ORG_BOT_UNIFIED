Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Set-TbotPaths {
  param([string]$Root = "C:\alpaca-bot\org_bot")

  if(-not (Test-Path $Root)) { $Root = (Resolve-Path .).Path }
  Set-Location $Root

  $script:ROOT   = $Root
  $script:PY     = Join-Path $Root ".venv\Scripts\python.exe"
  $script:META   = Join-Path $Root "logs\meta.jsonl"
  $script:SHADOW = Join-Path $Root "logs\shadow_plans.jsonl"
  $script:OPS    = Join-Path $Root "logs\ops"

  [pscustomobject]@{
    ROOT=$script:ROOT; PY=$script:PY; META=$script:META; SHADOW=$script:SHADOW; OPS=$script:OPS
  }
}

function Get-TbotRid {
  param([int]$Tail = 50000)
  if(-not (Test-Path $script:META)) { return $null }
  $line = (Get-Content $script:META -Tail $Tail | Select-String '"kind"\s*:\s*"boot"' | Select-Object -Last 1)
  if(-not $line) { return $null }
  try { return ($line.Line | ConvertFrom-Json).run_id } catch { return $null }
}

function Get-TbotEnvSnapshot {
  # DO NOT persist secrets. Only record presence/length.
  $keys = @(
    "TBOT_ENABLE_S11_MVP","TBOT_S11_MIN_STRENGTH","TBOT_S11_MIN_CONF",
    "TBOT_ALPHA_TREND_ON_TH","TBOT_ALPHA_TREND_CAP_TH","TBOT_ALPHA_CHOP_CAP_TH",
    "TBOT_DATA_FEED","TBOT_MARKET_DEBUG"
  )
  $snap = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $snap.Add(("{0}={1}" -f $k, ($env:$k)))
  }

  $kid = $env:APCA_API_KEY_ID
  $sec = $env:APCA_API_SECRET_KEY
  $snap.Add(("APCA_API_KEY_ID_PRESENT={0} LEN={1}" -f ([bool]$kid), ($(if($kid){$kid.Length}else{0}))))
  $snap.Add(("APCA_API_SECRET_KEY_PRESENT={0} LEN={1}" -f ([bool]$sec), ($(if($sec){$sec.Length}else{0}))))
  return $snap
}
