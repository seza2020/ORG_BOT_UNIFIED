param()

function Get-ApcaBaseUrl {
  $u = ([string]$env:APCA_API_BASE_URL).Trim()
  if([string]::IsNullOrWhiteSpace($u)){ $u = "https://paper-api.alpaca.markets" }
  return $u.TrimEnd("/")
}

function Get-ApcaHeaders {
  $k = ([string]$env:APCA_API_KEY_ID).Trim()
  $s = ([string]$env:APCA_API_SECRET_KEY).Trim()
  if([string]::IsNullOrWhiteSpace($k) -or [string]::IsNullOrWhiteSpace($s)){
    throw "APCA_KEYS_MISSING (set APCA_API_KEY_ID/APCA_API_SECRET_KEY in secrets)"
  }
  return @{
    "APCA-API-KEY-ID"     = $k
    "APCA-API-SECRET-KEY" = $s
    "Content-Type"        = "application/json"
  }
}

function Invoke-Apca {
  param(
    [ValidateSet("GET","POST")] [string]$Method,
    [string]$Path,
    [hashtable]$Query = @{},
    [object]$Body = $null
  )
  $base = Get-ApcaBaseUrl
  $uri = "$base$Path"
  if($Query.Count -gt 0){
    $qs = ($Query.GetEnumerator() | ForEach-Object {
      "{0}={1}" -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$_.Value)
    }) -join "&"
    $uri = "$uri`?$qs"
  }

  $headers = Get-ApcaHeaders

  if($Method -eq "GET"){
    return Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 30
  } else {
    $json = $null
    if($Body -ne $null){ $json = ($Body | ConvertTo-Json -Depth 20) }
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $json -TimeoutSec 30
  }
}

function Get-ApcaAccount { Invoke-Apca -Method GET -Path "/v2/account" }

function Submit-ApcaOrder {
  param(
    [string]$Symbol,
    [int]$Qty,
    [ValidateSet("buy","sell")] [string]$Side,
    [ValidateSet("market","limit")] [string]$Type="market",
    [ValidateSet("day","gtc")] [string]$TIF="day",
    [string]$ClientOrderId=""
  )
  $body = @{
    symbol = $Symbol
    qty = $Qty
    side = $Side
    type = $Type
    time_in_force = $TIF
  }
  if(-not [string]::IsNullOrWhiteSpace($ClientOrderId)){
    $body["client_order_id"] = $ClientOrderId
  }
  return Invoke-Apca -Method POST -Path "/v2/orders" -Body $body
}

function List-ApcaOrders {
  param(
    [string]$Status="all",
    [string]$After="",
    [string]$Until="",
    [int]$Limit=500
  )
  $q=@{ status=$Status; limit=$Limit }
  if($After){ $q["after"]=$After }
  if($Until){ $q["until"]=$Until }
  return Invoke-Apca -Method GET -Path "/v2/orders" -Query $q
}
