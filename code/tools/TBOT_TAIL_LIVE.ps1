Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_tbot_env.ps1"
$null = Set-TbotPaths

$out = Get-ChildItem $OPS -Filter "LIVE_OUT_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$err = Get-ChildItem $OPS -Filter "LIVE_ERR_*.txt" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if($out){
  "TAIL OUT: " + $out.FullName
  Get-Content -Wait -Tail 80 $out.FullName
}else{
  "LIVE_OUT not found"
}
