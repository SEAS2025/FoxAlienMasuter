param(
  [string]$Com,
  # Homed-machine Z toward the spindle / limit (this Masuter session: MPos Z ~ -1 at home).
  [decimal]$MachineZTop = -1
)

$ErrorActionPreference = 'Stop'

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw 'No CH340 COM port found. Set -Com manually or reconnect USB.'
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}

Write-Host "`n=== Disconnect Candle first (COM: $Com) ==="
& (Join-Path $PSScriptRoot 'Disconnect-Candle.ps1')
Start-Sleep -Milliseconds 1500

$sp = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$sp.DtrEnable = $false
$sp.RtsEnable = $false
try { $sp.Open() } catch {
  Write-Host ($_ | Out-String)
  Write-Host "`nCannot open $Com (still busy or wrong port).`n"
  exit 1
}
Start-Sleep -Milliseconds 2100

function Drain($port, [int]$ms) {
  $acc = ''
  $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead) {
    if ($port.BytesToRead) { $acc += $port.ReadExisting() }
    Start-Sleep -Milliseconds 35
  }
  Start-Sleep -Milliseconds 180
  while ($port.BytesToRead) { $acc += $port.ReadExisting(); Start-Sleep -Milliseconds 25 }
  $acc
}

function Send-Line($port, [string]$line, [int]$waitMs) {
  $port.DiscardInBuffer()
  $b = [System.Text.Encoding]::ASCII.GetBytes($line + [char]13)
  $port.Write($b, 0, $b.Length)
  Start-Sleep -Milliseconds 140
  (Drain $port $waitMs).TrimEnd()
}

Write-Host 'Unlock (harmless if not needed):'
Write-Host (Send-Line $sp '$X' 4500)

Write-Host 'Spindle off:'
Write-Host (Send-Line $sp 'M5' 900)

$zFmt = "{0:G29}" -f [double]$MachineZTop
$cmd = ('G21 G90 G53 G0 Z{0}' -f $zFmt)
Write-Host "`nCOMMAND: $cmd`n(status before)`n"
Write-Host (Send-Line $sp '?' 1600)

$response = Send-Line $sp $cmd 60000
Write-Host $response
if ($response -match 'error:|ALARM:') {
  throw $response
}

Write-Host "`nStatus after:"
Write-Host (Send-Line $sp '?' 1800)

$sp.Close(); $sp.Dispose()
Write-Host ("`nDone. Z rapid to homed-top: machine Z={0}. Alarm? retry with -MachineZTop -2.`n" -f $zFmt)
