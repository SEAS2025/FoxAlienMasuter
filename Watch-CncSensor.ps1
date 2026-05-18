# Local webcam + microphone bench monitor for heuristic CNC alerts.
# Not a safety device. Requires Python 3 + packages from requirements-cnc-watch.txt.
#
# Example:
#   .\Watch-CncSensor.ps1
#   .\Watch-CncSensor.ps1 -Com COM7
#   .\Watch-CncSensor.ps1 -Com COM7 -Camera 1 -MotionDropS 60 -LogCsv .\samples\cnc-watch-log.csv -NoAudio

param(
  [int]$Camera = 0,
  [double]$MotionDropS = 45,
  [string]$LogCsv = '',
  [string]$Com = '',
  [switch]$NoAudio
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) {
  Write-Host 'Python not found on PATH. Install Python 3 and retry.' -ForegroundColor Red
  exit 1
}

$req = Join-Path $root 'requirements-cnc-watch.txt'
Write-Host 'Installing / updating watch dependencies (quiet)...' -ForegroundColor Cyan
& python -m pip install -q -r $req
if ($LASTEXITCODE -ne 0) {
  Write-Host 'pip install failed.' -ForegroundColor Red
  exit $LASTEXITCODE
}

$script = Join-Path $root 'tools\cnc_sensor_watch.py'
$argsList = @('--camera', "$Camera", '--motion-drop-s', "$MotionDropS")
if ($LogCsv) {
  $argsList += @('--log-csv', $LogCsv)
}
if ($NoAudio) {
  $argsList += '--no-audio'
}
if (-not $Com) { $Com = $env:MASUTER_COM }
if ($Com) {
  $argsList += @('--com', $Com)
}

if ($Com) {
  Write-Host "GRBL serial $Com — exclusive port; stop Candle / DryRun streamers on this COM first." -ForegroundColor DarkYellow
}

Write-Host 'Starting sensor watch — terminal updates; stop with Ctrl+C.' -ForegroundColor Yellow
& python $script @argsList
