# Diagnostic: GRBL settings ($$ spindle-related), tiny axis jogs (G91), stepped spindle speeds with status FS logging.
# CLEAR THE TABLE / AIR CUT ONLY. Collet tight; eyes and ears; E-stop ready.
# Close Candle before running (script disconnects it unless -NoDisconnectCandle).

param(
  [string]$Com,
  [bool]$StopStreamingPowerShell = $true,
  [bool]$DisconnectCandle = $true,
  [switch]$SkipHome,
  # Skip all axis motion (only $$ + M3/M5 sequence). Use when limits/homing block motion tests.
  [switch]$SpindleOnly,
  [ValidateRange(0.5, 25)]
  [double]$TravelMm = 4,
  [ValidateRange(50, 6000)]
  [double]$JogFeed = 400,
  [ValidateRange(2, 120)]
  [int]$SpindleDwellSeconds = 10,
  # Commanded S values to try (last should match your CAM max, e.g. 24000).
  [int[]]$SpindleSpeeds = @(4000, 8000, 12000, 16000, 20000, 24000),
  [switch]$DumpAllSettings
)

$ErrorActionPreference = 'Stop'

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw 'No CH340 COM found. Pass -Com (e.g. COM7) or set MASUTER_COM.'
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}

$root = $PSScriptRoot
if ($DisconnectCandle) {
  & (Join-Path $root 'Disconnect-Candle.ps1')
  Start-Sleep -Seconds 1
}

if ($StopStreamingPowerShell) {
  Write-Host 'Stopping PowerShell G-code streamers...' -ForegroundColor Yellow
  $streamRx = '(?i)DryRun-WebCircle\.ps1|Resume-KatahdinOakRough\.ps1|Resume-OakRough-In-Candle\.ps1|Start-KatahdinDryRun\.ps1|Run-KatahdinOakAirTestSequential\.ps1|Run-KatahdinOakSequential\.ps1|Run-KatahdinRoughLayer1\.ps1|Run-KatahdinCornerHoles\.ps1'
  foreach ($procName in @('powershell.exe', 'pwsh.exe')) {
    Get-CimInstance Win32_Process -Filter "Name='$procName'" | ForEach-Object {
      $cl = $_.CommandLine
      if (-not $cl) { return }
      if ($cl -match '(?i)AppData\\Local\\Temp\\ps-script-') { return }
      if ($cl -notmatch $streamRx) { return }
      if ($_.ProcessId -eq $PID) { return }
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
  Start-Sleep -Seconds 2
}

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
  Start-Sleep -Milliseconds 140
  while ($p.BytesToRead -gt 0) { $acc += $p.ReadExisting(); Start-Sleep -Milliseconds 28 }
  $acc
}

function Cmd([System.IO.Ports.SerialPort]$p, [string]$line, [int]$waitMs = 60000) {
  $p.DiscardInBuffer()
  $wb = [Text.Encoding]::ASCII.GetBytes($line.TrimEnd() + "`r")
  $p.Write($wb, 0, $wb.Length)
  Start-Sleep -Milliseconds 80
  Drain $p $waitMs
}

function Wait-GrblIdle([System.IO.Ports.SerialPort]$p, [int]$timeoutMs = 180000) {
  $dead = (Get-Date).AddMilliseconds($timeoutMs)
  while ((Get-Date) -lt $dead) {
    Start-Sleep -Milliseconds 220
    while ($p.BytesToRead -gt 0) { [void]$p.ReadExisting() }
    $wb = [Text.Encoding]::ASCII.GetBytes('?' + "`r")
    $p.Write($wb, 0, $wb.Length)
    Start-Sleep -Milliseconds 150
    $resp = ''
    $inner = (Get-Date).AddMilliseconds(900)
    while ((Get-Date) -lt $inner) {
      if ($p.BytesToRead -gt 0) {
        $resp += $p.ReadExisting()
        if ($resp -match '(?m)(^|\r|\n)ok(\r|\n|$)') { break }
      }
      Start-Sleep -Milliseconds 25
    }
    while ($p.BytesToRead -gt 0) { $resp += $p.ReadExisting(); Start-Sleep -Milliseconds 15 }
    if ($resp -match '<Idle[\|>]') { return $resp }
    if ($resp -match '<Alarm') { throw "GRBL Alarm while waiting for Idle: $($resp.Trim())" }
  }
  throw 'Timeout waiting for GRBL Idle.'
}

function Get-StatusFs([System.IO.Ports.SerialPort]$p) {
  $raw = Cmd $p '?' 1200
  $one = [regex]::Replace($raw.Trim(), '\s+', ' ')
  $fs = ''
  if ($one -match '\|FS:([^|]+)\|') { $fs = $matches[1].Trim() }
  [pscustomobject]@{ Raw = $one; FS = $fs }
}

Write-Host ''
Write-Host '=== Masuter axis + spindle diagnostic ===' -ForegroundColor Cyan
Write-Host "COM=$Com   Travel=${TravelMm}mm each axis (G91)   Spindle dwell=${SpindleDwellSeconds}s per step"
Write-Host 'If Grbl $30 (max RPM) is lower than your M3 S commands, FS may cap below commanded speed.'
Write-Host ''

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false
try {
  $port.Open()
} catch {
  Write-Host ("Cannot open {0}: {1}" -f $Com, $_.Exception.Message)
  exit 1
}

try {
  Start-Sleep -Milliseconds 2200
  [void](Drain $port 400)

  Write-Host '--- Unlock ($X) ---' -ForegroundColor Yellow
  Write-Host ([regex]::Replace((Cmd $port ('$' + 'X') 3500).Trim(), '\s+', ' '))

  if (-not $SkipHome) {
    Write-Host '--- Homing ($H) ---' -ForegroundColor Yellow
    $port.DiscardInBuffer()
    $hb = [Text.Encoding]::ASCII.GetBytes(('$' + 'H') + [char]13)
    $port.Write($hb, 0, $hb.Length)
    $deadline = (Get-Date).AddMinutes(4)
    $ok = $false
    while ((Get-Date) -lt $deadline) {
      Start-Sleep -Seconds 2
      $st = Cmd $port '?' 1500
      Write-Host ([regex]::Replace($st.Trim(), '\s+', ' '))
      if ($st -match '<Idle' -and $st -notmatch 'Pn:') { $ok = $true; break }
      if ($st -match '<Alarm') {
        Write-Host 'Homing hit Alarm - fix limits (e.g. jog Z off switch), then rerun.' -ForegroundColor Red
        Write-Host 'For spindle RPM check only (no motion): -SkipHome -SpindleOnly' -ForegroundColor Yellow
        throw "Alarm during home: $st"
      }
    }
    if (-not $ok) { throw 'Timeout waiting for Idle after $H' }
  }
  else {
    Write-Host 'WARN: -SkipHome set - machine may not be referenced.' -ForegroundColor DarkYellow
    Write-Host ([regex]::Replace((Cmd $port '?' 1200).Trim(), '\s+', ' '))
  }

  Write-Host ''
  Write-Host '--- Grbl $$ (spindle-related) ---' -ForegroundColor Yellow
  $port.DiscardInBuffer()
  $wb = [Text.Encoding]::ASCII.GetBytes('$' + '$' + "`r")
  $port.Write($wb, 0, $wb.Length)
  Start-Sleep -Milliseconds 400
  $settingsBlob = Drain $port 8000
  $lines = $settingsBlob -split "`r`n|`r|`n"
  $interesting = @('\$30=', '\$31=', '\$32=', '\$13=')
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if (-not $t) { continue }
    if ($DumpAllSettings) {
      if ($t -match '^\$\d+=|^ok$|^GRBL') { Write-Host $t }
    }
    else {
      foreach ($pat in $interesting) {
        if ($t -match $pat) { Write-Host $t; break }
      }
    }
  }
  if (-not $DumpAllSettings) {
    Write-Host '(Pass -DumpAllSettings for full $$ listing)'
  }

  $maxGrblRpm = $null
  foreach ($ln in $lines) {
    $t = $ln.Trim()
    if ($t -match '^\$30=([\d\.]+)') {
      $maxGrblRpm = [double]$matches[1]
      break
    }
  }
  if ($null -ne $maxGrblRpm) {
    $wantMax = ($SpindleSpeeds | Measure-Object -Maximum).Maximum
    if ($wantMax -gt $maxGrblRpm) {
      Write-Host ''
      Write-Host "IMPORTANT: Grbl `$30=$([int]$maxGrblRpm) RPM caps all M3 S above that (FS showed capped speed). For CAM at S$wantMax set e.g. `$30=$wantMax then verify VFD/router." -ForegroundColor Yellow
      Write-Host 'Send in Candle serial console: $30=24000  (or your real max RPM), then $$ to confirm.' -ForegroundColor Yellow
    }
  }

  Write-Host ''
  Write-Host '--- M5 then modal setup ---' -ForegroundColor Yellow
  [void](Cmd $port 'M5' 2000)
  foreach ($line in @('G21', 'G90', 'G94', 'G54')) {
    $r = Cmd $port $line 12000
    if ($r -match '(?i)error:\d+') {
      Write-Host $r
      throw "GRBL error on: $line"
    }
  }

  Write-Host ''
  Write-Host "--- Axis crawl (G91, F$JogFeed) X +/- , Y +/-$(if (-not $SkipZJog) { ' , Z +/-' }) ---" -ForegroundColor Yellow
  if ($SpindleOnly) {
    Write-Host 'Skipped (-SpindleOnly).' -ForegroundColor DarkYellow
  }
  else {
    [void](Cmd $port 'G91' 8000)

    $axisMoves = @(
      ('G1 X{0:F4} F{1:F0}' -f $TravelMm, $JogFeed),
      ('G1 X{0:F4} F{1:F0}' -f (-$TravelMm), $JogFeed),
      ('G1 Y{0:F4} F{1:F0}' -f $TravelMm, $JogFeed),
      ('G1 Y{0:F4} F{1:F0}' -f (-$TravelMm), $JogFeed)
    )
    if (-not $SkipZJog) {
      $axisMoves += @(
        ('G1 Z{0:F4} F{1:F0}' -f (-$TravelMm), [math]::Min($JogFeed, 300)),
        ('G1 Z{0:F4} F{1:F0}' -f $TravelMm, [math]::Min($JogFeed, 300))
      )
    }

    $mi = 0
    foreach ($mv in $axisMoves) {
      $mi++
      Write-Host ("  [{0}/{1}] {2}" -f $mi, $axisMoves.Count, $mv)
      $r = Cmd $port $mv 120000
      if ($r -match '(?i)error:\d+|ALARM:') {
        Write-Host $r
        throw "Axis test failed on: $mv"
      }
      Wait-GrblIdle $port 120000 | Out-Null
    }

    [void](Cmd $port 'G90' 8000)
    Wait-GrblIdle $port 60000 | Out-Null
  }

  Write-Host ''
  Write-Host '--- Spindle speed steps (listen/watch VFD or router; compare FS: vs commanded S) ---' -ForegroundColor Yellow
  Write-Host 'Commanded S    Status FS (feed,spindle as reported)'
  foreach ($rpm in $SpindleSpeeds) {
    $cmd = "M3 S$rpm"
    Write-Host "`n>> $cmd"
    $r = Cmd $port $cmd 4000
    if ($r -match '(?i)error:\d+') { Write-Host $r; throw "GRBL error on $cmd" }
    Start-Sleep -Seconds 2
    $t0 = Get-Date
    while (((Get-Date) - $t0).TotalSeconds -lt $SpindleDwellSeconds) {
      $o = Get-StatusFs $port
      Write-Host ("  {0,-6} s   FS={1}" -f [math]::Round(((Get-Date) - $t0).TotalSeconds, 0), $(if ($o.FS) { $o.FS } else { '(no FS in ?)' }))
      Start-Sleep -Seconds 2
    }
  }

  Write-Host ''
  Write-Host '--- M5 ---' -ForegroundColor Yellow
  [void](Cmd $port 'M5' 3000)
  Start-Sleep -Seconds 2
  $done = Get-StatusFs $port
  Write-Host ("Idle FS after M5: {0}" -f $(if ($done.FS) { $done.FS } else { $done.Raw }))

  Write-Host ''
  Write-Host '=== Done. Interpretation hints ===' -ForegroundColor Green
  Write-Host '- If $30 is 1000 but you command S24000, GRBL scales PWM; FS second field may still reflect scaled range.'
  Write-Host '- If FS spindle value never rises with S, PWM wiring/VFD mode/M3 mapping may be wrong.'
  Write-Host '- Laser mode ($32=1) changes spindle behavior - normally OFF for routers.'
}
finally {
  if ($port -and $port.IsOpen) {
    try {
      [void](Cmd $port 'M5' 2000)
    }
    catch { }
    $port.Close()
  }
  $port.Dispose()
}
