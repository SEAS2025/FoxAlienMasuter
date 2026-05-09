param(
  [string]$Com,
  [switch]$SkipHome,
  # Non-interactive: skip AIR-TEST-SPINDLE confirmation (automation / agent use)
  [switch]$Force
)

# True air test: spindle ON at oak feeds, all Z lifted — no stock on deck.
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not [string]::IsNullOrWhiteSpace($Com)) {
  $env:MASUTER_COM = $Com
}

& (Join-Path $root 'Disconnect-Candle.ps1')
Start-Sleep -Seconds 1

& (Join-Path $root 'New-KatahdinOakFeeds.ps1')
& (Join-Path $root 'New-KatahdinOakAirTestNc.ps1') -Which Rough
& (Join-Path $root 'New-KatahdinOakAirTestNc.ps1') -Which Finish

$rough = Join-Path $root 'samples/katahdin.oak.rough.airtest.nc'
$finish = Join-Path $root 'samples/katahdin.oak.finish.airtest.nc'

$resolvedCom = if ($Com) { $Com } elseif ($env:MASUTER_COM) { $env:MASUTER_COM } else {
  $ports = [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object
  $found = $null
  foreach ($p in $ports) {
    $dev = Get-CimInstance Win32_PnPEntity | Where-Object {
      $_.Name -match "\($p\)" -and $_.Name -match 'CH340|CH34|USB-SERIAL'
    } | Select-Object -First 1
    if ($dev) { $found = $p; break }
  }
  if (-not $found) { $found = $ports | Select-Object -First 1 }
  if (-not $found) { throw 'No COM port found' }
  $found
}
Write-Host "Using $resolvedCom"

if (-not $SkipHome) {
  $port = New-Object System.IO.Ports.SerialPort $resolvedCom, 115200, None, 8, One
  $port.DtrEnable = $false
  $port.RtsEnable = $false
  function Drain($p, [int]$ms) {
    $a = ''
    $d = (Get-Date).AddMilliseconds($ms)
    while ((Get-Date) -lt $d) {
      if ($p.BytesToRead -gt 0) { $a += $p.ReadExisting() }
      Start-Sleep -Milliseconds 40
    }
    return $a
  }
  function Cmd($p, $s, $w) {
    $p.DiscardInBuffer()
    $b = [Text.Encoding]::ASCII.GetBytes($s + [char]13)
    $p.Write($b, 0, $b.Length)
    Start-Sleep -Milliseconds 200
    return Drain $p $w
  }
  try {
    $port.Open()
    Start-Sleep -Milliseconds 2200
    Write-Host (Cmd $port ('$' + 'X') 2500)
    $port.DiscardInBuffer()
    $hb = [Text.Encoding]::ASCII.GetBytes(('$' + 'H') + [char]13)
    $port.Write($hb, 0, $hb.Length)
    $deadline = (Get-Date).AddMinutes(3)
    $ok = $false
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 2
      $st = Cmd $port '?' 1200
      Write-Host $st
      if ($st -match '<Idle' -and $st -notmatch 'Pn:') { $ok = $true; break }
      if ($st -match '<Alarm') { throw "Homing/alarm: $st" }
    }
    if (-not $ok) { throw 'Timeout waiting for Idle after home' }
  }
  finally {
    if ($port.IsOpen) { $port.Close() }
    $port.Dispose()
  }
}

Write-Host @'

==============================================================================
OAK AIR TEST - spindle will RUN, Z is lifted (no wood on deck)
==============================================================================

'@

$r = 'AIR-TEST-SPINDLE'
if (-not $Force) {
  $r = Read-Host 'Type AIR-TEST-SPINDLE to stream rough then finish (exact case)'
}

if ($r -ne 'AIR-TEST-SPINDLE') {
  Write-Host 'Aborted.'
  exit 0
}

Write-Host "`n--- Rough air test ---`n"
& (Join-Path $root 'DryRun-WebCircle.ps1') -Com $resolvedCom -NcPath $rough

Write-Host "`n--- Finish air test ---`n"
& (Join-Path $root 'DryRun-WebCircle.ps1') -Com $resolvedCom -NcPath $finish

Write-Host "`nStreams finished; poll `?` in Candle if motion still running."
