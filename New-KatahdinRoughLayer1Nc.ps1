# Build katahdin.oak.rough.layer1.nc — only ROUGH tier 1 (single 2 mm depth pass), then M5.
# Source: samples/katahdin.oak.rough.nc (regenerate with .\New-KatahdinOakFeeds.ps1 first).
# REAL CUT: spindle on (M3), 3 mm flat roughing bit, G54 Z0 on stock top.

param(
  [string]$SourcePath = $(Join-Path $PSScriptRoot 'samples/katahdin.oak.rough.nc'),
  [string]$OutPath = $(Join-Path $PSScriptRoot 'samples/katahdin.oak.rough.layer1.nc'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $SourcePath)) {
  throw "Missing source: $SourcePath  Run .\New-KatahdinOakFeeds.ps1"
}

if (-not $Force) {
  Write-Host ''
  Write-Host 'REAL CUT: first rough tier only (~2 mm deep). Type FIRST-LAYER to write file + instructions.' -ForegroundColor Yellow
  if ((Read-Host 'Confirm') -ne 'FIRST-LAYER') { Write-Host 'Aborted.'; exit 2 }
}

$lines = @(Get-Content -LiteralPath $SourcePath)
$ti = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match '^\s*;\s*---\s*ROUGH tier 2/') {
    $ti = $i
    break
  }
}
if ($ti -lt 1) {
  throw 'Could not find "; --- ROUGH tier 2/" marker — regenerate katahdin.oak.rough.nc.'
}

$endExclusive = $ti - 1
while ($endExclusive -ge 0 -and $lines[$endExclusive].Trim() -eq '') {
  $endExclusive--
}
if ($endExclusive -lt 0) {
  throw 'Bad tier boundary.'
}

$slice = $lines[0..$endExclusive] + 'M5'
$slice | Set-Content -LiteralPath $OutPath -Encoding ascii

Write-Host "Wrote $OutPath ($($slice.Count) lines, tier 1 only)."
Write-Host 'Stream with Candle or:'
Write-Host "  .\DryRun-WebCircle.ps1 -NcPath `"$OutPath`" -Com COM7"
