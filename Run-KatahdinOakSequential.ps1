param(
  [string]$Com,
  [switch]$SkipHome
)

# Sequential Masuter run: rough then finish for katahdin.oak.*.nc
# SPINDLE RUNS. This cuts real stock — not an air-only dry run.
# Close Candle first. Clamp white oak. G54 = same as your tests. Collet tight.

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not [string]::IsNullOrWhiteSpace($Com)) {
  $env:MASUTER_COM = $Com
}

& (Join-Path $root 'New-KatahdinOakFeeds.ps1')

$rough = Join-Path $root 'samples/katahdin.oak.rough.nc'
$finish = Join-Path $root 'samples/katahdin.oak.finish.nc'

if (-not $SkipHome) {
  & (Join-Path $root 'Send-HOME.ps1')
}

Write-Host @'

==============================================================================
OAK CARVE / SPINDLE-ON TEST
  Next: streams katahdin.oak.rough.nc then katahdin.oak.finish.nc
  Feeds: conservative white oak (620 / 720 mm/min XY — see New-KatahdinOakFeeds.ps1)
  E-stop must be free. Hearing protection. Vacuum recommended.
==============================================================================

'@

$r = Read-Host "Type CUT-WHITE-OAK to start both programs (exact case)"

if ($r -ne 'CUT-WHITE-OAK') {
  Write-Host 'Aborted.'
  exit 0
}

Write-Host "`n--- Rough ---`n"
$dryArgs = @{ NcPath = $rough }
if (-not [string]::IsNullOrWhiteSpace($Com)) { $dryArgs.Com = $Com }
& (Join-Path $root 'DryRun-WebCircle.ps1') @dryArgs

Write-Host "`n--- Finish ---`n"
$dryArgs.NcPath = $finish
& (Join-Path $root 'DryRun-WebCircle.ps1') @dryArgs

Write-Host "`nBoth streams finished (check GRBL for buffered motion tail)."
