param(
  [string]$Com = $(if ($env:MASUTER_COM) { $env:MASUTER_COM } else { 'COM7' }),
  [double]$MaxProbeMm = 55,
  [int]$ProbeFeed = 120
)

$ErrorActionPreference = 'Stop'

$serial = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$serial.DtrEnable = $false
$serial.RtsEnable = $false
try {
  $serial.Open()
} catch {
  Write-Host ($_ | Out-String)
  Write-Host "Close Candle / disconnect serial on $Com, then rerun."
  exit 1
}
Start-Sleep -Milliseconds 2000

function SendLine([System.IO.Ports.SerialPort]$sp, [string]$line) {
  $sp.DiscardInBuffer()
  $wb = [System.Text.Encoding]::ASCII.GetBytes($line + [char]13)
  $sp.Write($wb, 0, $wb.Length)
}

function Slurp([System.IO.Ports.SerialPort]$sp, [int]$ms) {
  $a = ''
  $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead -or $sp.BytesToRead) {
    if ($sp.BytesToRead) { $a += $sp.ReadExisting() }
    Start-Sleep -Milliseconds 40
  }
  return $a
}

Write-Host "=== `$X ==="
SendLine $serial '$X'
Write-Host (Slurp $serial 4000).Trim()

Write-Host "=== ? before ==="
SendLine $serial '?'
Write-Host (Slurp $serial 1500).Trim()

Write-Host ""
Write-Host "=== G38.2 (rel) Z-$MaxProbeMm F$ProbeFeed  (probe toward deck --- DO NOT MOVE XY) ==="
SendLine $serial 'G21'
Slurp $serial 900 | Out-Null
SendLine $serial 'G91'
Slurp $serial 900 | Out-Null

SendLine $serial ("G38.2 Z-{0} F{1}" -f $MaxProbeMm, $ProbeFeed)

$buf = ''
$dead = (Get-Date).AddMilliseconds([int](90000 + $MaxProbeMm / $ProbeFeed * 60000))
while ((Get-Date) -lt $dead) {
  Start-Sleep -Milliseconds 120
  if ($serial.BytesToRead) { $buf += $serial.ReadExisting() }

  # Grbl echoes [PRB:x,y,z:1|0]
  if ($buf -match '\[PRB:') {

    Write-Host "--- probe Rx ---"

    Write-Host $buf.TrimEnd()

    break
  }


  if ($buf -match 'error:|ALARM:') {

    Write-Host "--- stop ---"

    Write-Host $buf.TrimEnd()

    break
  }


}

if (-not ($buf -match '\[PRB:|error:|ALARM:')) {
  Write-Host "--- timeout / no PRB/error line ---"

  Write-Host $buf


}

SendLine $serial 'G90'
Slurp $serial 800 | Out-Null

Write-Host ""

Write-Host "=== ? after ==="

SendLine $serial '?'

Write-Host (Slurp $serial 1800).Trim()


Write-Host ""

Write-Host '=== $# (offsets; includes [PRB]) ==='

$d = '$' + '#'


SendLine $serial $d

Write-Host (Slurp $serial 3500).Trim()

$serial.Close()

$serial.Dispose()

Write-Host "`nNote: This machine tripped Z hard limit on G91 Z+ (up). Do not pre-lift with +Z from home; probe only with G38 downward."
