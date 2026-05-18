# STREAM ONLY — regenerates tier-1 oak rough NC then sends it (spindle ON, real cut).

param(
  [string]$Com,
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not $Force) {
  Write-Host ''
  Write-Host 'REAL CUT: first rough layer (~2 mm), spindle ON. Clamp oak; 3 mm flat bit; vacuum.' -ForegroundColor Yellow
  $t = Read-Host 'Type FIRST-LAYER-STREAM to proceed'
  if ($t -ne 'FIRST-LAYER-STREAM') {
    Write-Host 'Aborted.'
    exit 2
  }
}

& (Join-Path $root 'New-KatahdinRoughLayer1Nc.ps1') -Force
$nc = Join-Path $root 'samples/katahdin.oak.rough.layer1.nc'

Write-Host "`nClose Candle / free COM, then streaming..."
Start-Sleep -Seconds 2

$dry = Join-Path $root 'DryRun-WebCircle.ps1'
if (-not $Com) {
  & $dry -NcPath $nc
} else {
  & $dry -NcPath $nc -Com $Com
}
