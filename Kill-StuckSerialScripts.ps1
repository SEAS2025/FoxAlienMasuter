# Kill only hung repo serial jog/stream scripts (not all PowerShell).
$rx = '(?i)Jog-Z-Relative\.ps1|Jog-X-Relative\.ps1|DryRun-WebCircle\.ps1|Resume-KatahdinOakRough\.ps1|Start-KatahdinDryRun|Run-Katahdin|Run-KatahdinRoughLayer1'
$myId = $PID
foreach ($p in Get-CimInstance Win32_Process -Filter "Name='powershell.exe'") {
  $cl = $p.CommandLine
  if (-not $cl -or $cl -match '(?i)AppData\\Local\\Temp\\ps-script-') { continue }
  if ($cl -notmatch $rx) { continue }
  if ($p.ProcessId -eq $myId) { continue }
  Write-Host "Stop-Process -Id $($p.ProcessId)"
  Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
