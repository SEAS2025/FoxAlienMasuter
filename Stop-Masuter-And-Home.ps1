# Alias for the canonical Masuter shutdown workflow.
# See Close-Candle-Stop-And-Home.ps1 for the full three-step process.

param(
  [string]$Com
)

$ErrorActionPreference = 'Stop'
$splat = @{}
if ($Com) { $splat.Com = $Com }
& (Join-Path $PSScriptRoot 'Close-Candle-Stop-And-Home.ps1') @splat
