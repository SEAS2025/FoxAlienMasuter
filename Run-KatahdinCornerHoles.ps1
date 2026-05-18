# Raise Z, spindle on, drill four 3 mm holes at Katahdin map rectangle corners (G54).
# Stock top = Z0. Corners: (0,0) (185,0) (185,171) (0,171) — matches finish bbox (~186 x 172 mm job).
# REQUIREMENTS: 3 mm drill in collet; clamps clear; vacuum; eyes/ears; COM free.

param(
  [string]$Com,
  [double]$PreLiftMm = 1,
  [switch]$SkipPreLift,
  [switch]$Force,
  [string]$NcPath = $(Join-Path $PSScriptRoot 'samples/katahdin-corner-holes-3mm.nc')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $NcPath)) { throw "Missing: $NcPath" }

if (-not $Force) {
  Write-Host ''
  Write-Host 'REAL CUT: spindle ON, four plunges @ corners. Tool must be a 3 mm DRILL.' -ForegroundColor Yellow
  Write-Host 'Type CORNER-HOLES to proceed (or use -Force).' -ForegroundColor Yellow
  $r = Read-Host 'Confirm'
  if ($r -ne 'CORNER-HOLES') { Write-Host 'Aborted.'; exit 2 }
}

if (-not $SkipPreLift -and $PreLiftMm -ne 0) {
  Write-Host "`n--- Pre-lift Z +$PreLiftMm mm ---"
  $jz = Join-Path $PSScriptRoot 'Jog-Z-Relative.ps1'
  if (-not $Com) {
    & $jz -DeltaMm $PreLiftMm
  } else {
    & $jz -Com $Com -DeltaMm $PreLiftMm
  }
}

Write-Host "`n--- Streaming corner holes ---"
$dry = Join-Path $PSScriptRoot 'DryRun-WebCircle.ps1'
if (-not $Com) {
  & $dry -NcPath $NcPath
} else {
  & $dry -NcPath $NcPath -Com $Com
}
