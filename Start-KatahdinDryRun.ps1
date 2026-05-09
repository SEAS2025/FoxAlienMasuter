param(
  [ValidateSet('Rough', 'Finish')]
  [string]$Which = 'Finish',
  [string]$Com,
  [switch]$NoCloseCandle,
  [switch]$SkipHome,
  [switch]$RegenerateAirDry,
  [int]$HomeTimeoutSec = 180,
  [int]$IdleTimeoutSec = 120
)

$ErrorActionPreference = 'Stop'

function Stop-CandleIfNeeded {
  if ($NoCloseCandle) { return }
  $candle = Get-Process | Where-Object {
    $_.ProcessName -match '^candle$' -or $_.MainWindowTitle -match 'Candle'
  }
  if ($candle) {
    $candle | Stop-Process -Force
    Start-Sleep -Seconds 2
    Write-Host 'Closed Candle so this script can own the serial port.'
  }
}

function Resolve-MasuterCom {
  if ($Com) { return $Com }
  if ($env:MASUTER_COM) { return $env:MASUTER_COM }

  $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
  foreach ($p in $ports) {
    $dev = Get-CimInstance Win32_PnPEntity | Where-Object {
      $_.Name -match "\($p\)" -and $_.Name -match 'CH340|CH34|USB-SERIAL'
    } | Select-Object -First 1
    if ($dev) { return $p }
  }

  if ($ports.Count -eq 1) { return $ports[0] }
  throw "No CH340 COM port found. Reconnect USB, close Candle, or pass -Com COM7."
}

function New-GrblPort([string]$PortName) {
  $p = New-Object System.IO.Ports.SerialPort $PortName, 115200, None, 8, One
  $p.DtrEnable = $false
  $p.RtsEnable = $false
  $p.ReadTimeout = 5000
  $p.WriteTimeout = 5000
  return $p
}

function Read-Grbl([System.IO.Ports.SerialPort]$Port, [int]$Ms = 1000) {
  $acc = ''
  $deadline = (Get-Date).AddMilliseconds($Ms)
  while ((Get-Date) -lt $deadline) {
    if ($Port.BytesToRead -gt 0) { $acc += $Port.ReadExisting() }
    Start-Sleep -Milliseconds 40
  }
  return $acc
}

function Send-GrblLine([System.IO.Ports.SerialPort]$Port, [string]$Line, [int]$WaitMs = 1500) {
  $Port.DiscardInBuffer()
  $bytes = [Text.Encoding]::ASCII.GetBytes($Line + [char]13)
  $Port.Write($bytes, 0, $bytes.Length)
  Start-Sleep -Milliseconds 250
  return Read-Grbl $Port $WaitMs
}

function Get-GrblStatus([System.IO.Ports.SerialPort]$Port) {
  $Port.DiscardInBuffer()
  $bytes = [Text.Encoding]::ASCII.GetBytes('?')
  $Port.Write($bytes, 0, $bytes.Length)
  Start-Sleep -Milliseconds 600
  return (Read-Grbl $Port 500).Trim()
}

function Assert-ReadyStatus([string]$Status) {
  if ($Status -notmatch '<Idle') {
    throw "Controller is not Idle: $Status"
  }
  if ($Status -match 'Pn:') {
    throw "Limit/probe pins are active; refusing to stream near stops: $Status"
  }
}

function Wait-ForIdle([System.IO.Ports.SerialPort]$Port, [int]$TimeoutSec) {
  $deadline = (Get-Date).AddSeconds($TimeoutSec)
  $last = ''
  while ((Get-Date) -lt $deadline) {
    $last = Get-GrblStatus $Port
    Write-Host $last
    if ($last -match '<Idle|<Alarm|<Hold') { return $last }
    Start-Sleep -Seconds 2
  }
  throw "Timed out waiting for Idle. Last status: $last"
}

Stop-CandleIfNeeded
$resolvedCom = Resolve-MasuterCom
Write-Host "Using $resolvedCom"

$samplesDir = Join-Path $PSScriptRoot 'samples'
$airDryPath = Join-Path $samplesDir ("katahdin.{0}.air-dry.nc" -f $Which.ToLower())
if ($RegenerateAirDry -or -not (Test-Path $airDryPath)) {
  & (Join-Path $PSScriptRoot 'New-KatahdinAirDryNc.ps1') -Which $Which | Out-Null
}

$port = New-GrblPort $resolvedCom
try {
  $port.Open()
  Start-Sleep -Milliseconds 2200

  Write-Host '=== Initial status ==='
  $status = Get-GrblStatus $port
  Write-Host $status

  Write-Host '=== Clear alarm ($X) ==='
  Write-Host (Send-GrblLine $port ('$' + 'X') 2500)

  if (-not $SkipHome) {
    Write-Host '=== Home cycle ($H) ==='
    $port.DiscardInBuffer()
    $homeBytes = [Text.Encoding]::ASCII.GetBytes(('$' + 'H') + [char]13)
    $port.Write($homeBytes, 0, $homeBytes.Length)
    $homeStatus = Wait-ForIdle $port $HomeTimeoutSec
    Assert-ReadyStatus $homeStatus
  }
  else {
    Write-Host '=== Skipping home; checking current status ==='
    $status = Get-GrblStatus $port
    Write-Host $status
    Assert-ReadyStatus $status
  }
}
finally {
  if ($port.IsOpen) { $port.Close() }
  $port.Dispose()
}

Write-Host "=== Streaming $airDryPath ==="
& (Join-Path $PSScriptRoot 'DryRun-WebCircle.ps1') -Com $resolvedCom -NcPath $airDryPath

Write-Host '=== Waiting for buffered GRBL motion to return Idle ==='
$port = New-GrblPort $resolvedCom
try {
  $port.Open()
  Start-Sleep -Milliseconds 500
  $final = Wait-ForIdle $port $IdleTimeoutSec
  Assert-ReadyStatus $final
}
finally {
  if ($port.IsOpen) { $port.Close() }
  $port.Dispose()
}

Write-Host 'Katahdin air-dry workflow completed cleanly.'
