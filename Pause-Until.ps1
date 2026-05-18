# Block this PowerShell session until a wall-clock time (local timezone).
# Default: next occurrence of 08:00 today, or tomorrow if it is already past.
#
# Examples:
#   .\Pause-Until.ps1                    # wait until 8:00 AM local
#   .\Pause-Until.ps1 -Hour 9 -Minute 30
#
# Does not stop GRBL or kill streamers — run Close-Candle-Stop-And-Home.ps1 first if needed.

param(
  [int]$Hour = 8,
  [int]$Minute = 0
)

$ErrorActionPreference = 'Stop'

if ($Hour -lt 0 -or $Hour -gt 23) { throw '-Hour must be 0..23' }
if ($Minute -lt 0 -or $Minute -gt 59) { throw '-Minute must be 0..59' }

$now = Get-Date
$target = $now.Date.AddHours($Hour).AddMinutes($Minute)
if ($target -le $now) {
  $target = $target.AddDays(1)
}

$wait = $target - $now
Write-Host ("Pausing until {0:yyyy-MM-dd HH:mm} local (~{1:N1} hours)." -f $target, $wait.TotalHours) -ForegroundColor Cyan

# Start-Sleep accepts fractional seconds; cap per iteration so Ctrl+C stays responsive.
$chunk = [TimeSpan]::FromMinutes(1)
$end = $target
while ((Get-Date) -lt $end) {
  $remaining = $end - (Get-Date)
  if ($remaining -le [TimeSpan]::Zero) { break }
  $sleep = if ($remaining -lt $chunk) { $remaining } else { $chunk }
  Start-Sleep -Seconds ([int][Math]::Ceiling($sleep.TotalSeconds))
}

Write-Host ("Resume at {0:yyyy-MM-dd HH:mm:ss} local." -f (Get-Date)) -ForegroundColor Green
