param()
$ErrorActionPreference="SilentlyContinue"
$lst = Get-CimInstance Win32_Process -Filter "Name='python.exe'" |
  Where-Object { $_.CommandLine -match "tbot\.main" } |
  Select-Object ProcessId,ParentProcessId,CommandLine
$cnt=@($lst).Count
if($cnt -le 1){
  "OK PID_COUNT=$cnt PIDS=" + (($lst|% ProcessId)-join ",")
  exit 0
}
"DUALPID_DETECTED PID_COUNT=$cnt PIDS=" + (($lst|% ProcessId)-join ",")
foreach($p in $lst){ try{ Stop-Process -Id $p.ProcessId -Force }catch{} }
exit 86