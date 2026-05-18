# Resume katahdin oak rough stream after a partial DryRun stop (same parsed line skip as DryRun-WebCircle).
# Default skip advances past PS resume killed at ~75/5291 with skip 1453 (~1519). Tune per session.
# Regenerates oak NC with 2x-ish rough feeds + retract G0 Z5 by default (see -RetractZMm).
# SPINDLE RUNS. Close Candle. G54 unchanged since setup. Review AGENTS.md envelope / limits.

param(
  [string]$Com,
  [ValidateRange(0, 99999999)]
  [int]$SkipParsedLines = 1519,
  [string]$NcPath = 'samples/katahdin.oak.rough.nc',
  [int]$RoughFeedXY = 156,
  [int]$FeedPlungeRough = 240,
  [ValidateRange(0.1, 50)]
  [double]$RetractZMm = 5
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not [string]::IsNullOrWhiteSpace($Com)) {
  $env:MASUTER_COM = $Com
}
if (-not $env:MASUTER_COM) {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { $env:MASUTER_COM = "COM$($matches[1])"; break }
  }
}
if (-not $env:MASUTER_COM) { throw 'Pass -Com or set MASUTER_COM.' }

& (Join-Path $root 'New-KatahdinOakFeeds.ps1') -RoughFeedXY $RoughFeedXY -FeedPlungeRough $FeedPlungeRough -RetractZMm $RetractZMm

$ncFull = Join-Path $root $NcPath
Write-Host "Resume oak rough: parsed skip=$SkipParsedLines (next line is index $SkipParsedLines); retract Z=${RetractZMm}mm  rough XY F$RoughFeedXY." -ForegroundColor Yellow

& (Join-Path $root 'DryRun-WebCircle.ps1') -NcPath $ncFull -Com $env:MASUTER_COM -SkipParsedLines $SkipParsedLines -ResumeRetractZMm $RetractZMm
