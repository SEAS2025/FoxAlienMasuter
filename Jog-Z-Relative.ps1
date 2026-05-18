# Incremental Z jog in current work plane (G54, etc.). Negative = down.

param(
  [Parameter(Mandatory = $true)]
  [double]$DeltaMm,
  [string]$Com,
  [double]$Feed = 200
)

$ErrorActionPreference = 'Stop'

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

Write-Host "Using $Com  (Z += $DeltaMm mm work coords, F$Feed)"

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false
try { $port.Open() } catch {
  Write-Host ("Cannot open {0}: {1}" -f $Com, $_.Exception.Message)
  exit 1
}
Start-Sleep -Milliseconds 2000

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
  while ($p.BytesToRead -gt 0) { $acc += $p.ReadExisting(); Start-Sleep -Milliseconds 28 }
  $acc
}

function Cmd([System.IO.Ports.SerialPort]$p, [string]$line, [int]$waitMs = 60000) {
  $p.DiscardInBuffer()
  $wb = [Text.Encoding]::ASCII.GetBytes($line.TrimEnd() + "`r")
  $p.Write($wb, 0, $wb.Length)
  Start-Sleep -Milliseconds 70
  Drain $p $waitMs
}

function Wait-GrblIdle([System.IO.Ports.SerialPort]$p, [int]$timeoutMs = 180000) {
  $dead = (Get-Date).AddMilliseconds($timeoutMs)
  while ((Get-Date) -lt $dead) {
    Start-Sleep -Milliseconds 200
    while ($p.BytesToRead -gt 0) { [void]$p.ReadExisting() }
    $wb = [Text.Encoding]::ASCII.GetBytes('?' + "`r")
    $p.Write($wb, 0, $wb.Length)
    Start-Sleep -Milliseconds 130
    $resp = ''
    $inner = (Get-Date).AddMilliseconds(800)
    while ((Get-Date) -lt $inner) {
      if ($p.BytesToRead -gt 0) {
        $resp += $p.ReadExisting()
        if ($resp -match '(?m)(^|\r|\n)ok(\r|\n|$)') { break }
      }
      Start-Sleep -Milliseconds 25
    }
    while ($p.BytesToRead -gt 0) { $resp += $p.ReadExisting(); Start-Sleep -Milliseconds 15 }
    if ($resp -match '<Idle[\|>]') { return }
    if ($resp -match '<Alarm') { throw "GRBL Alarm while waiting for Idle: $($resp.Trim())" }
  }
  throw 'Timeout waiting for GRBL Idle after Z jog.'
}

$st = Cmd $port '?' 4000
Write-Host ('Status: ' + ([regex]::Replace($st.Trim(), '\s+', ' ')))
if ($st -match '<Alarm') { Cmd $port '$X' 4000 | Out-Null }

# Unlock before any G-code (avoids error:9 after reset / banner noise).
[void](Cmd $port '$X' 2500)

[void](Cmd $port 'M5' 1500)

foreach ($g in @('G21', 'G91')) {
  Write-Host ">> $g"
  $r = Cmd $port $g 8000
  if ($r -match '(?i)error:\d+') {
    if ($g -eq 'G21' -and $r -match 'error:9') {
      Write-Host '(retry after `$X)'
      [void](Cmd $port '$X' 2500)
      $r = Cmd $port $g 8000
    }
    if ($r -match '(?i)error:\d+') { Write-Host $r; throw "GRBL error on: $g" }
  }
}

$zLine = ('G1 Z{0:F4} F{1:F0}' -f $DeltaMm, $Feed)
Write-Host ">> $zLine"
$r = Cmd $port $zLine 15000
if ($r -match '(?i)error:\d+') { Write-Host $r; throw "GRBL error on: $zLine" }

Write-Host 'Waiting for Z jog to finish (Idle)...'
Wait-GrblIdle $port 180000

Write-Host '>> G90'
[void](Cmd $port 'G90' 8000)
Wait-GrblIdle $port 60000

Start-Sleep -Milliseconds 400
Write-Host ('Final: ' + ([regex]::Replace((Cmd $port '?' 2000).Trim(), '\s+', ' ')))
Write-Host 'Done (incremental Z in work coords).'

$port.Close()
$port.Dispose()
