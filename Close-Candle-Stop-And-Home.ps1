# Canonical shutdown / safe restart position for the Masuter (GRBL).
#
# Workflow (run this anytime you need a clean COM port and machine at limit home):
#   1) Close Candle — frees the CH340 port from the GUI sender.
#   2) Stop activity — feed hold, soft reset, unlock, spindle off (clears planner).
#   3) Return to starting point — `$H` homing cycle to limit-switch home.
#
# If COM is still denied after step 1: stop any PowerShell/other sender streaming
# G-code on the same port, then run this script again.

param(
  [string]$Com,
  [int]$ComOpenRetries = 8,
  [int]$ComOpenRetrySeconds = 2
)

$ErrorActionPreference = 'Stop'

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw 'No CH340 COM found. Pass -Com (e.g. COM7).'
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}

Write-Host ''
Write-Host '========== 1/3 Close Candle (free COM port) ==========' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'Disconnect-Candle.ps1')
Start-Sleep -Seconds 2

function Drain([System.IO.Ports.SerialPort]$p, [int]$ms) {
  $a = ''
  $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead) {
    if ($p.BytesToRead) { $a += $p.ReadExisting() }
    Start-Sleep -Milliseconds 40
  }
  while ($p.BytesToRead) { $a += $p.ReadExisting(); Start-Sleep -Milliseconds 25 }
  $a
}

function Cmd([System.IO.Ports.SerialPort]$p, [string]$s, [int]$waitMs = 8000) {
  $p.DiscardInBuffer()
  $b = [System.Text.Encoding]::ASCII.GetBytes($s + [char]13)
  $p.Write($b, 0, $b.Length)
  Start-Sleep -Milliseconds 280
  Drain $p $waitMs
}

$port = $null
$opened = $false
for ($attempt = 1; $attempt -le $ComOpenRetries; $attempt++) {
  if ($port) {
    try { if ($port.IsOpen) { $port.Close() } } catch { }
    $port.Dispose()
    $port = $null
  }
  $port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
  $port.DtrEnable = $false
  $port.RtsEnable = $false
  try {
    $port.Open()
    $opened = $true
    break
  } catch {
    Write-Host "COM open attempt $attempt/$ComOpenRetries failed: $($_.Exception.Message)"
    Write-Host "  Close Candle if it reopened; stop any G-code streamer on $Com; retrying in ${ComOpenRetrySeconds}s..."
    Start-Sleep -Seconds $ComOpenRetrySeconds
  }
}

if (-not $opened) {
  throw "Could not open $Com after $ComOpenRetries tries. Close Candle and any sender using $Com, then run Close-Candle-Stop-And-Home.ps1 again."
}

try {
  Start-Sleep -Milliseconds 2200

  Write-Host ''
  Write-Host '========== 2/3 Stop activity (hold, reset, unlock, M5) ==========' -ForegroundColor Cyan
  Write-Host '--- Feed hold (!) then GRBL soft reset (Ctrl-X)'
  $port.Write([byte[]]@(0x21), 0, 1)
  Start-Sleep -Milliseconds 400
  $port.Write([byte[]]@(0x18), 0, 1)
  Start-Sleep -Milliseconds 600
  Write-Host (Drain $port 1800)

  Write-Host '--- `$X unlock'
  Write-Host (Cmd $port ('$' + 'X') 3500)

  Write-Host '--- M5 spindle off'
  Write-Host (Cmd $port 'M5' 1500)

  Write-Host ''
  Write-Host '========== 3/3 Return to starting point ($H homing) ==========' -ForegroundColor Cyan
  Write-Host (Cmd $port ('$' + 'H') 95000)

  $deadline = (Get-Date).AddMinutes(4)
  $ok = $false
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    $st = Cmd $port '?' 1500
    Write-Host $st
    if ($st -match '<Idle' -and $st -notmatch 'Pn:') { $ok = $true; break }
    if ($st -match '<Alarm') { throw "Still in alarm after home: $st" }
  }
  if (-not $ok) { throw 'Timeout waiting for Idle after $H' }

  Write-Host ''
  Write-Host 'Done: Candle closed (or was not running), motion stopped, machine homed.' -ForegroundColor Green
}
finally {
  if ($port) {
    try { if ($port.IsOpen) { $port.Close() } } catch { }
    $port.Dispose()
  }
}
