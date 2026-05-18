# Jog to Katahdin job corner in G54 (X0 Y0) at safe Z, for aligning stock.
# Same convention as samples/katahdin*.nc: G54, stock top = Z0, safe rapids use Z10.

param(
  [string]$Com,
  [ValidateRange(5, 80)]
  [double]$SafeZ = 10
)

$ErrorActionPreference = "Stop"

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw "No CH340 COM found. Set -Com or MASUTER_COM."
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}

Write-Host "Using $Com"

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false

try {
  $port.Open()
} catch {
  Write-Host ("Cannot open {0}: {1}" -f $Com, $_.Exception.Message)
  Write-Host "Close Candle or disconnect the port, then rerun."
  exit 1
}

Start-Sleep -Milliseconds 900

function Drain([System.IO.Ports.SerialPort]$p, [int]$ms) {
  $acc = ""
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

$st = Cmd $port "?" 900
Write-Host ("Status (trim): " + ([regex]::Replace($st.Trim(), '\s+', ' ')))

if ($st -match '<Alarm') {
  Write-Host "Alarm -> `$X"
  Cmd $port '$X' 4000 | Out-Null
}

[void](Cmd $port 'M5' 2500)

$zcmd = 'G0 Z{0:F3}' -f $SafeZ
foreach ($g in @('G21', 'G90', 'G54', $zcmd, 'G0 X0 Y0')) {
  Write-Host ">> $g"
  $r = Cmd $port $g 90000
  if ($r -match '(?i)error:\d+') {
    Write-Host $r
    throw "GRBL error on: $g"
  }
}

Start-Sleep -Milliseconds 400
$end = Cmd $port "?" 2000
Write-Host ("Final (trim): " + ([regex]::Replace($end.Trim(), '\s+', ' ')))
Write-Host "Done: spindle off; tool at G54 X0 Y0, work Z=$SafeZ (place plank under XY; Z0 = stock top when you zero)."

$port.Close()
$port.Dispose()
