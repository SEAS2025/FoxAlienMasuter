# Return Masuter GRBL to limit-switch home: sends $H
# prerequisite: Close Candle (disconnect) / anything else holding the COM port.

$ErrorActionPreference = "Stop"
$com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { "COM5" }

$port = New-Object System.IO.Ports.SerialPort $com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false

try {
  $port.Open()
} catch {
  Write-Host ("Cannot open {0}: {1}" -f $com, $_.Exception.Message)
  Write-Host "Close Candle / serial terminal using this COM port and run again."
  exit 1
}

Start-Sleep -Milliseconds 2200

function Drain([System.IO.Ports.SerialPort]$p, $ms = 900) {
  $a = ""; $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead) {
    if ($p.BytesToRead) { $a += $p.ReadExisting() }
    Start-Sleep -Milliseconds 45
  }
  $a
}

function Cmd([System.IO.Ports.SerialPort]$p, [string]$s, [int]$waitMs = 95000) {
  $p.DiscardInBuffer()
  $b = [System.Text.Encoding]::ASCII.GetBytes($s + [char]13)
  $p.Write($b, 0, $b.Length)
  Start-Sleep -Milliseconds 350
  Drain $p $waitMs
}

Write-Host "--- Status (before)"
Write-Host (Cmd $port "?" 1000)

Write-Host "--- Homing `$H..."
Write-Host (Cmd $port ('$'+'H'))

Write-Host "--- Status (after)"
Write-Host (Cmd $port "?" 1500)

$port.Close(); $port.Dispose()
Write-Host "Done."
