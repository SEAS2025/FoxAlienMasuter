param(
  [string]$Com = $(if ($env:MASUTER_COM) { $env:MASUTER_COM } else { 'COM5' }),
  [int]$Feed = 4500
)

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Disconnect Candle (or COM tools), then rerun. Optional Candle-process stop follows ==="
& (Join-Path $PSScriptRoot 'Disconnect-Candle.ps1')
Start-Sleep -Milliseconds 1500

$sp = New-Object System.IO.Ports.SerialPort $Com,115200,None,8,One
$sp.DtrEnable = $false
$sp.RtsEnable = $false
try { $sp.Open() } catch { Write-Host ($_ | Out-String); Write-Host "`nStill cannot open $Com.`n"; exit 1 }
Start-Sleep -Milliseconds 2100

function Drain($p,[int]$ms){
  $acc = ''
  $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead) {
    if ($p.BytesToRead) { $acc += $p.ReadExisting() }
    Start-Sleep -Milliseconds 35
  }
  Start-Sleep -Milliseconds 180
  while ($p.BytesToRead) { $acc += $p.ReadExisting(); Start-Sleep -Milliseconds 25 }
  return $acc
}

function Send($p,[string]$line,[int]$wait){
  $p.DiscardInBuffer()
  $b=[System.Text.Encoding]::ASCII.GetBytes($line+[char]13)
  $p.Write($b,0,$b.Length)
  Start-Sleep -Milliseconds 140
  (Drain $p $wait).TrimEnd()
}

[void](Send $sp '$X' 4000)

$dd = '$'+'$'
$settings = Send $sp $dd 4500

$m130 = [double][regex]::Match($settings,'\$130=([0-9.]+)').Groups[1].Value
$m131 = [double][regex]::Match($settings,'\$131=([0-9.]+)').Groups[1].Value
if (-not $m130 -or -not $m131) {
  Write-Host $settings
  throw 'Cannot parse $130/$131 limits from EEPROM dump — power-cycle and reconnect.'
}

# Homed Firmware style used on this Masuter GRBL snapshot: XY machine coords sweep ~negative toward 0; center ≈ -travel/2
$xg = [math]::Round(-$m130 / 2, 3)
$yg = [math]::Round(-$m131 / 2, 3)

Write-Host ('EEPROM $130={0} $131={1}' -f $m130,$m131)
Write-Host ('Target table-center (G53): X {0}, Y {1}' -f $xg,$yg)
Write-Host 'Status before:'
Write-Host (Send $sp '?' 1400)

$cmd=('G21 G90 G53 G0 X{0} Y{1} F{2}' -f $xg,$yg,$Feed)
Write-Host "`nCOMMAND: $cmd`n"
$response = Send $sp $cmd 90000

Write-Host $response

if ($response -match 'error:|ALARM:') { throw $response }

Write-Host "`nStatus after:"
Write-Host (Send $sp '?' 1500)

$sp.Close(); $sp.Dispose()
Write-Host "`n(Z unchanged — only XY table-center in machine coords. Re-home with `$H if limits/references drift.)"
