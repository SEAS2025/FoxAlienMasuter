param(
  # Only XY move to approximate machine-table centre ($130/$131 midpoint in G53). Z unchanged.
  [switch]$OnlyCenterTable,
  # Skip Step 1 (use AFTER you jogged/zero G54 XY on the board centre manually).
  [switch]$SkipTableCenter,
  # Regenerate NC from defaults (overwrite samples/smiley-face-soft-pine-G54.mm.nc)
  [switch]$RegenerateNc,
  # Non-interactive: stream spindle carve immediately (implies you accept risk).
  [switch]$Cut,
  [string]$Com,
  [string]$NcPath = $(Join-Path $PSScriptRoot 'samples/smiley-face-soft-pine-G54.mm.nc')
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Fox Alien Masuter -- shallow smiley carve (pine) ==="

if (-not $Com) {
  # Propagate resolved COM inside child scripts unless already set:
  try {
    if (-not $env:MASUTER_COM) {
      foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
        if ($name -match '\(COM(\d+)\)') { $env:MASUTER_COM = "COM$($matches[1])"; break }
      }
      if (-not $env:MASUTER_COM) {
        foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
          if ($name -match '\(COM(\d+)\)') { $env:MASUTER_COM = "COM$($matches[1])"; break }
        }
      }
    }
  }
  catch { }
}

if (-not [string]::IsNullOrWhiteSpace($Com)) {
  $env:MASUTER_COM = $Com
}

if ($RegenerateNc) {
  & (Join-Path $PSScriptRoot 'New-SmileyFacePineNc.ps1') -OutFile $NcPath
}

if (-not (Test-Path $NcPath)) {
  & (Join-Path $PSScriptRoot 'New-SmileyFacePineNc.ps1') -OutFile $NcPath
}

if (-not $SkipTableCenter) {
  Write-Host @'

About to XY jog to MACHINE table midpoint (not your board centre unless coincident).
SKIP with -SkipTableCenter if you already set G54 on the pine.

'@
  Write-Host "--- Step 1: Move XY to EEPROM table midpoint (disconnect Candle first)... ---`n"

  & (Join-Path $PSScriptRoot 'Move-To-Table-Center.ps1')
}
else {
  Write-Host "--- Skipped Move-To-Table-Center (--SkipTableCenter). Using current position + G54. ---`n"
}

if ($OnlyCenterTable) {
  Write-Host "`nOnlyCenterTable: DONE. Clamp pine, jog to board centre, zero XY and Z top, reload Candle and/or run carve."
  exit 0
}

Write-Host @"

==============================================================================
READY TO CARVE WARNING
  Clamp is secure. Clearing path cleared. Roughly 68 mm OD face carve at -2 mm.
  Spindle will START (M3) from the G-code file unless you stripped it manually.
==============================================================================

"@

if (-not $Cut) {
  $r = Read-Host "Type CUT (exact uppercase) to stream carve from PowerShell ; anything else quits safely"

  if ($r -ne 'CUT') {
    Write-Host "`nSkipped streaming. Open $($NcPath) in Candle Preview when ready.`n"
    exit 0
  }
}
else {
  Write-Host "`n--Cut: skipping Read-Host (--Cut). STREAMING spindle job.`n"
}

Write-Host "`nStarting stream (close Candle disconnect serial first)..."

& (Join-Path $PSScriptRoot 'DryRun-WebCircle.ps1') -NcPath $NcPath

Write-Host "`nStream script finished.`n"
