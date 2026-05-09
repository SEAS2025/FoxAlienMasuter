# GRBL: spindle ON only — sends a single line `M3 S<rpm>` (no axis motion, no homing, no dwell).
# Close Candle / disconnect the port first, or set MASUTER_COM and pass -Com if needed.
param(
  [string]$Com,
  [int]$Rpm = 6000
)

$ErrorActionPreference = "Stop"

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw "No CH340 COM found. Disconnect Candle then pass -Com (e.g. COM7)."
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false
try {
  $port.Open()
} catch {
  Write-Host ($_.Exception.Message)
  Write-Host "Free the port (disconnect Candle) or set MASUTER_COM / -Com."
  exit 1
}
Start-Sleep -Milliseconds 800
function Drain($p, $ms = 600) {
  $a = ''
  $d = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $d) {
    if ($p.BytesToRead) { $a += $p.ReadExisting() }
    Start-Sleep -Milliseconds 35
  }
  $a
}
$line = "M3 S$Rpm"
$b = [Text.Encoding]::ASCII.GetBytes($line + [char]13)
$port.DiscardInBuffer()
$port.Write($b, 0, $b.Length)
Start-Sleep -Milliseconds 250
Write-Host (Drain $port 800)
$port.Close()
$port.Dispose()
Write-Host "Sent only: $line  (use M5 in Candle or a separate script to stop spindle)"
