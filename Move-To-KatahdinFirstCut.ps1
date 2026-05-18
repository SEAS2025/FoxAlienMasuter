# Move to first programmed cut position for table-fit Katahdin (samples/katahdin.*.nc).
# After G54: both rough and finish use G0 Z10, G0 X0 Y<top-row>, then G1 Z... for first engagement.
#
# If the rough job spends many mm cutting air before chips appear: G54 Z0 is usually above the real
# stock top — re-touch Z on the surface at first XY, or regenerate terrain with New-TerrainNc.py
# --deepen-cuts-mm <measured gap> then oak feeds script.
#
# Default XY matches terrain NC; Z is read from the first G1 Z line in the rough/finish file when present.
# Use -ApproachOnly to stop at Z10 above first XY (no plunge).

param(
  [string]$Com,
  [ValidateSet('Rough', 'Finish')]
  [string]$Which = 'Rough',
  [switch]$ApproachOnly,
  [string]$RoughNcPath = 'samples/katahdin.rough.nc',
  [string]$FinishNcPath = 'samples/katahdin.finish.nc'
)

$ErrorActionPreference = 'Stop'

function Get-FirstG1Z([string]$RelativeNcPath) {
  $full = Join-Path $PSScriptRoot $RelativeNcPath
  if (-not (Test-Path -LiteralPath $full)) { return $null }
  foreach ($line in [System.IO.File]::ReadLines($full)) {
    $trim = $line.TrimStart()
    if ($trim -match '^G1\s+Z([\-\d\.]+)') {
      return [double]$matches[1]
    }
  }
  return $null
}

$first = @{
  Rough  = @{ X = 0; Y = 171; Z = -2.0 }
  Finish = @{ X = 0; Y = 171; Z = -14.8076 }
}
$parsedZ = if ($Which -eq 'Rough') { Get-FirstG1Z $RoughNcPath } else { Get-FirstG1Z $FinishNcPath }
if ($null -ne $parsedZ) {
  $first[$Which].Z = $parsedZ
}
$t = $first[$Which]

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw 'No CH340 COM found. Set -Com or MASUTER_COM.'
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}

Write-Host "Using $Com  (first cut: $Which -> X=$($t.X) Y=$($t.Y) Z=$(if ($ApproachOnly) { '10 approach only' } else { $t.Z })$(if (($null -ne $parsedZ) -and (-not $ApproachOnly)) { '  [from NC]' }))"

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false

try {
  $port.Open()
} catch {
  Write-Host ("Cannot open {0}: {1}" -f $Com, $_.Exception.Message)
  Write-Host 'Close Candle / other senders on this COM port, then rerun.'
  exit 1
}

Start-Sleep -Milliseconds 900

function Drain([System.IO.Ports.SerialPort]$p, [int]$ms) {
  $acc = ''
  $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead) {
    if ($p.BytesToRead -gt 0) { $acc += $p.ReadExisting() }
    Start-Sleep -Milliseconds 35
    if ($acc -match '(?m)(^|\r|\n)ok(\r|\n|$)') { break }
    if ($acc -match '(?msi)error:\d+') { break }
    if ($acc -match '(?msi)ALARM:\d+') { break }
  }
  Start-Sleep -Milliseconds 120
  while ($p.BytesToRead -gt 0) {
    $acc += $p.ReadExisting()
    Start-Sleep -Milliseconds 28
  }
  $acc
}

function Cmd([System.IO.Ports.SerialPort]$p, [string]$line, [int]$waitMs = 12000) {
  $p.DiscardInBuffer()
  $wb = [Text.Encoding]::ASCII.GetBytes($line.TrimEnd() + "`r")
  $p.Write($wb, 0, $wb.Length)
  Start-Sleep -Milliseconds 70
  Drain $p $waitMs
}

$st = Cmd $port '?' 900
Write-Host ('Status (trim): ' + ([regex]::Replace($st.Trim(), '\s+', ' ')))

if ($st -match '<Alarm') {
  Write-Host 'Alarm -> $X'
  Cmd $port '$X' 4000 | Out-Null
}

[void](Cmd $port 'M5' 2500)

$lines = @(
  'G21',
  'G90',
  'G54',
  'G0 Z10',
  ('G0 X{0} Y{1}' -f $t.X, $t.Y)
)
if (-not $ApproachOnly) {
  $lines += ('G1 Z{0:F4} F200' -f $t.Z)
}

foreach ($g in $lines) {
  Write-Host ">> $g"
  $r = Cmd $port $g 90000
  if ($r -match '(?i)error:\d+') {
    Write-Host $r
    throw "GRBL error on: $g"
  }
}

Start-Sleep -Milliseconds 400
$end = Cmd $port '?' 2000
Write-Host ('Final (trim): ' + ([regex]::Replace($end.Trim(), '\s+', ' ')))
if ($ApproachOnly) {
  Write-Host "Done: G54 X=$($t.X) Y=$($t.Y) work Z=10 (same first XY as $($Which.ToLower()).nc; no plunge)."
} else {
  Write-Host "Done: first $($Which.ToLower()) cut point X=$($t.X) Y=$($t.Y) Z=$($t.Z) mm (stock top = Z0). Spindle left off (M5)."
}

$port.Close()
$port.Dispose()
