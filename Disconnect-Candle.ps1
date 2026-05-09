# Stops Candle so another program can open the CH340 COM port.
$names = @('Candle', 'candle')
foreach ($n in $names) {
  Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}
Write-Host "Candle stop attempted. If COM is still busy, unplug/replug USB or close other serial tools (Putty, Arduino Serial Monitor, etc.)."
