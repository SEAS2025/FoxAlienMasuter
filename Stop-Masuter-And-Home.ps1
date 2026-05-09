# Emergency stop + return to limit-switch home.
# Close anything streaming G-code to the Masuter first (Candle / PowerShell sender),
# or this may fail to open COM. Candle is stopped by Disconnect-Candle.

param(
  [string]$Com
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

& (Join-Path $PSScriptRoot 'Disconnect-Candle.ps1')
Start-Sleep -Seconds 1

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false

try {
  $port.Open()
} catch {
  Write-Host ($_ | Out-String)
  Write-Host "Cannot open $Com - stop the program that is streaming (Candle window or PowerShell DryRun), then run this again."
  exit 1
}

Start-Sleep -Milliseconds 2200

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

Write-Host '--- Homing `$H'
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

Write-Host 'Done. Machine should be at home (limit-switch home).'
$port.Close()
$port.Dispose()
