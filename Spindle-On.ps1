# Spindle on (GRBL M3). Close Candle connection first, or run this from a second machine only if COM is free.
param(
  [string]$Com = $(if ($env:MASUTER_COM) { $env:MASUTER_COM } else { "COM5" }),
  [int]$Rpm = 8000
)

$ErrorActionPreference = "Stop"
$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false
try {
  $port.Open()
} catch {
  Write-Host ($_.Exception.Message)
  Write-Host "Free the port (disconnect Candle) or set MASUTER_COM."
  exit 1
}
Start-Sleep -Milliseconds 800
function Drain($p,$ms=600){ $a=''; $d=(Get-Date).AddMilliseconds($ms); while((Get-Date)-lt $d){ if($p.BytesToRead){$a+=$p.ReadExisting()}; Start-Sleep -Milliseconds 35 }; $a }
$line = "M3 S$Rpm"
$b=[Text.Encoding]::ASCII.GetBytes($line+[char]13)
$port.DiscardInBuffer()
$port.Write($b,0,$b.Length)
Start-Sleep -Milliseconds 250
Write-Host (Drain $port 800)
$port.Close(); $port.Dispose()
Write-Host "Sent: $line (M5 = spindle off)"
