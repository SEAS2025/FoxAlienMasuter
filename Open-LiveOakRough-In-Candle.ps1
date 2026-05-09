# Regenerate oak toolpaths and open the LIVE rough file in Candle (spindle-on feeds; real cut program).
# Use after homing/unlock in Candle; connect COM (e.g. 115200). Finish file: same folder, katahdin.oak.finish.nc

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

& (Join-Path $root 'New-KatahdinOakFeeds.ps1')

$rough = Join-Path $root 'samples\katahdin.oak.rough.nc'
if (-not (Test-Path $rough)) { throw "Missing: $rough" }
$roughFull = (Resolve-Path $rough).Path

$candleExe = Join-Path $root 'candle-11.2\Candle\candle.exe'
if (-not (Test-Path $candleExe)) {
  throw ('Candle not found at {0} - run .\install-candle.ps1' -f $candleExe)
}

Write-Host "Opening Candle with live rough:`n  $roughFull" -ForegroundColor Cyan
$candleDir = Split-Path $candleExe
Start-Process -FilePath $candleExe -ArgumentList @($roughFull) -WorkingDirectory $candleDir

Write-Host ''
Write-Host 'If the file does not appear, use File > Open and choose the path above.'
Write-Host 'Finish pass (after rough): samples\katahdin.oak.finish.nc'
