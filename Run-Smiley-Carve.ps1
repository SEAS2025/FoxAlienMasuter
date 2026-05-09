param(
  # Only XY move to approximate machine-table center ($130/$131 midpoint in G53). Z unchanged.
  [switch]$OnlyCenterTable,
  # Regenerate NC from defaults (overwrite samples/smiley-face-soft-pine-G54.mm.nc)
  [switch]$RegenerateNc,
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

Write-Host @'

Table-centre move aligns the spindle to approximate machine-table middle (G53 from EEPROM limits).
YOUR PINE BOARD may still need a jog until the tool sits above the CENTRE DOT you want for the emoji.

  Then in Candle: set G54 XY ZERO at that spindle centre.

  Probe or touch TOP of pine and SET G54 Z ZERO on top surface (+Z upward away from spoilboard convention).

'@

Write-Host "--- Step 1: Move XY to EEPROM table midpoint (disconnect Candle first)... ---`n"

& (Join-Path $PSScriptRoot 'Move-To-Table-Center.ps1')

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

$r = Read-Host "Type CUT (exact uppercase) to stream carve from PowerShell ; anything else quits safely"

if ($r -ne 'CUT') {
  Write-Host "`nSkipped streaming. Open $($NcPath) in Candle Preview when ready.`n"
  exit 0
}

Write-Host "`nStarting stream (close Candle disconnect serial first)..."

& (Join-Path $PSScriptRoot 'DryRun-WebCircle.ps1') -NcPath $NcPath

Write-Host "`nStream script finished.`n"
