# Regenerate oak toolpaths and open the LIVE rough file in Candle (spindle-on feeds; real cut program).
# Use after homing/unlock in Candle; connect COM (e.g. 115200). Finish file: same folder, katahdin.oak.finish.nc

param(
  # End repo PowerShell streamers so Candle can open COM (DryRun / Resume scripts).
  [bool]$StopStreamingPowerShell = $true,
  [int]$RoughFeedXY = 156,
  [int]$FeedPlungeRough = 240,
  [ValidateRange(0.1, 50)]
  [double]$RetractZMm = 5,
  [string]$RoughRelative = 'samples\katahdin.oak.rough.nc'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if ($StopStreamingPowerShell) {
  Write-Host 'Stopping PowerShell G-code streamers (DryRun / Katahdin)...' -ForegroundColor Yellow
  $streamRx = '(?i)DryRun-WebCircle\.ps1|Resume-KatahdinOakRough\.ps1|Resume-OakRough-In-Candle\.ps1|Start-KatahdinDryRun\.ps1|Run-KatahdinOakAirTestSequential\.ps1|Run-KatahdinOakSequential\.ps1|Run-KatahdinRoughLayer1\.ps1|Run-KatahdinCornerHoles\.ps1|Move-To-KatahdinG54Origin\.ps1|Move-To-KatahdinFirstCut\.ps1|Jog-Z-Relative\.ps1|Jog-X-Relative\.ps1'
  foreach ($procName in @('powershell.exe', 'pwsh.exe')) {
    Get-CimInstance Win32_Process -Filter "Name='$procName'" | ForEach-Object {
      $cl = $_.CommandLine
      if (-not $cl) { return }
      if ($cl -match '(?i)AppData\\Local\\Temp\\ps-script-') { return }
      if ($cl -notmatch $streamRx) { return }
      if ($_.ProcessId -eq $PID) { return }
      Write-Host "  Stop-Process -Id $($_.ProcessId)"
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
  Start-Sleep -Seconds 2
}

& (Join-Path $root 'New-KatahdinOakFeeds.ps1') -RoughFeedXY $RoughFeedXY -FeedPlungeRough $FeedPlungeRough -RetractZMm $RetractZMm

$rough = Join-Path $root $RoughRelative
if (-not (Test-Path $rough)) { throw "Missing: $rough" }
$roughFull = (Resolve-Path $rough).Path

$candleExe = Join-Path $root 'candle-11.2\Candle\candle.exe'
if (-not (Test-Path $candleExe)) {
  throw ('Candle not found at {0} - run .\install-candle.ps1' -f $candleExe)
}

Write-Host "Opening Candle with live rough:`n  $roughFull" -ForegroundColor Cyan
Write-Host "  (XY F$RoughFeedXY  plunge F$FeedPlungeRough  retract Z=${RetractZMm}mm)" -ForegroundColor DarkGray
$candleDir = Split-Path $candleExe
Start-Process -FilePath $candleExe -ArgumentList @($roughFull) -WorkingDirectory $candleDir

Write-Host ''
Write-Host 'If the file does not appear, use File > Open and choose the path above.'
Write-Host 'Connect COM (115200), unlock/home if needed, then Send. Finish pass: samples\katahdin.oak.finish.nc'
