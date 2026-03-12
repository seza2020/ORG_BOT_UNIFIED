param(
[string]$Profile,
[string]$UnifiedRoot,
[string]$RunRoot,
[string]$PyExe
)

Write-Host "TBOT_RUNTIME_GUARD_CHECK"

$existing = Get-CimInstance Win32_Process |
Where-Object { $_.CommandLine -match "tbot\.main" }

if($existing){
Write-Host "TBOT_SINGLE_INSTANCE_GUARD_TRIGGERED"
exit 0
}

Write-Host "TBOT_RUNTIME_GUARD_OK"
exit 0
