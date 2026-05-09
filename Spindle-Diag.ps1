# Spindle diagnostic: send M5 (stop), then query $$ (settings) and $G (parser state).
# Read-only after the M5 stop. No motion, no homing.
param(
  [string]$Com
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
Write-Host "Using $Com"

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false
try { $port.Open() } catch { Write-Host $_.Exception.Message; exit 1 }
Start-Sleep -Milliseconds 800

function Drain($p, $ms = 1500) {
  $a = ''
  $d = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $d) {
    if ($p.BytesToRead) { $a += $p.ReadExisting() }
    Start-Sleep -Milliseconds 35
  }
  $a
}

function Send($p, $line, $waitMs = 1500) {
  Write-Host "`n>>> $line"
  $b = [Text.Encoding]::ASCII.GetBytes($line + [char]13)
  $p.DiscardInBuffer()
  $p.Write($b, 0, $b.Length)
  $resp = Drain $p $waitMs
  Write-Host $resp
}

Drain $port 400 | Out-Null

Send $port "M5" 1000
Send $port "?" 800
Send $port '$G' 800
Send $port '$$' 3000

$port.Close()
$port.Dispose()
Write-Host "`nKey settings to read above:"
Write-Host "  `$32  = laser mode (router should be 0)"
Write-Host "  `$30  = max spindle RPM (must be >= the S value you send)"
Write-Host "  `$31  = min spindle RPM"
