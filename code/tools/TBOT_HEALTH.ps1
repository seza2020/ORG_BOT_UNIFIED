Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_tbot_env.ps1"
$null = Set-TbotPaths

"ROOT=$ROOT"
"PY=$PY"
"META=$META EXISTS=" + (Test-Path $META)
"SHADOW=$SHADOW EXISTS=" + (Test-Path $SHADOW)

$rid = Get-TbotRid
"`nRID=$rid"

"`n--- ERRORS (last 20) ---"
if($rid -and (Test-Path $META)){
  $errs = Get-Content $META -Tail 200000 | Select-String $rid | Select-String '"kind"\s*:\s*"error"' | Select-Object -Last 20
  if($errs){ $errs | ForEach-Object { $_.Line } } else { "OK: no error" }
}else{
  "WARN: RID/META not available"
}

"`n--- SHADOW_REJECT (last 20) ---"
if($rid -and (Test-Path $META)){
  $rej = Get-Content $META -Tail 200000 | Select-String $rid | Select-String '"kind"\s*:\s*"shadow_reject"' | Select-Object -Last 20
  if($rej){ $rej | ForEach-Object { $_.Line } } else { "OK: no shadow_reject" }
}

"`n--- LAST shadow_plan (last 10) ---"
if($rid -and (Test-Path $META)){
  $plans = Get-Content $META -Tail 200000 | Select-String $rid | Select-String '"kind"\s*:\s*"shadow_plan"' | Select-Object -Last 10
  if($plans){ $plans | ForEach-Object { $_.Line } } else { "WARN: no shadow_plan yet" }
}

"`n--- SHADOW FILE tail ---"
if(Test-Path $SHADOW){
  Get-Item $SHADOW | Format-List FullName,Length,LastWriteTime
  "TAIL:"
  Get-Content -Tail 5 $SHADOW
}else{
  "WARN: SHADOW FILE NOT FOUND"
}
