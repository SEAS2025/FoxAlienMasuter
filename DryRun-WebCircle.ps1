param(
  [string]$NcPath = (Join-Path $PSScriptRoot "samples/from-web/feather-circle-dry-75mm.nc"),
  [string]$Com,
  # Long default: G4 spindle dwell lines can exceed typical rapids timeout.
  [int]$LineWaitMs = 90000,
  # Skip first N parsed lines (after NC filter). Next line sent is index N (1-based counter would be N+1).
  # When > 0, default injects modals + spindle (first M3/G4 from file head) + G0 Z… + G0 XY from replayed moves over skipped lines.
  [ValidateRange(0, 9999999)]
  [int]$SkipParsedLines = 0,
  # Work-coordinate retract before rapid XY in resume preamble (mm). Keep below your upper Z limit margin — large values can trip Z max.
  [ValidateRange(0.1, 50)]
  [double]$ResumeRetractZMm = 5,
  # Unsafe: stream only from skipped index with no preamble (only if machine already matches modals + position).
  [switch]$NoResumePreamble
)

$ErrorActionPreference = "Stop"

function Update-XYZZFromMoveLine {
  param(
    [string]$Line,
    [ref]$Rx,
    [ref]$Ry,
    [ref]$Rz
  )
  if ($Line -notmatch '(?i)^(?:G00|G0|G01|G1)\b') { return }
  if ($Line -match '(?i)\bX([\-\d\.]+)') { $Rx.Value = $matches[1].Trim() }
  if ($Line -match '(?i)\bY([\-\d\.]+)') { $Ry.Value = $matches[1].Trim() }
  if ($Line -match '(?i)\bZ([\-\d\.]+)') { $Rz.Value = $matches[1].Trim() }
}

function ResolveMasuterCom {
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*USB-SERIAL CH340*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  foreach ($name in @(Get-CimInstance Win32_PnPEntity | Where-Object Name -Like '*CH34*COM*' | Sort-Object Name | Select-Object -ExpandProperty Name)) {
    if ($name -match '\(COM(\d+)\)') { return "COM$($matches[1])" }
  }
  throw "No CH340 COM found. Close Candle then pass -Com (e.g. COM7)."
}

if (-not $Com) {
  $Com = if ($env:MASUTER_COM) { $env:MASUTER_COM } else { ResolveMasuterCom }
}
if (-not (Test-Path $NcPath)) { throw "Missing: $NcPath" }

$nclines = @(Get-Content $NcPath | ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and ($_ -notmatch '^\(') -and ($_ -match '^(N\d+\s+)?(?i)(g|m)\d+') })

if ($nclines.Count -lt 3) { throw "Parsed G-code lines: $($nclines.Count). Check $NcPath and regex filter." }

if ($SkipParsedLines -ge $nclines.Count) {
  throw "SkipParsedLines ($SkipParsedLines) must be less than parsed line count ($($nclines.Count))."
}

Write-Host "G-code lines to stream: $($nclines.Count)$(if ($SkipParsedLines -gt 0) { "  (resume skip first $SkipParsedLines)" })"

$resumeSlice = @($nclines | Select-Object -Skip $SkipParsedLines)
$preambleLines = @()

if ($SkipParsedLines -gt 0 -and -not $NoResumePreamble) {
  Write-Host @'

=== RESUME MODE ===
You homed / reset since the partial run: we replay skipped moves only to compute XY/Z,
then inject spindle + safe Z + rapid XY before continuing. Wrong SkipParsedLines risks a crash.
Verify G54 matches your plank; tune -SkipParsedLines if unsure.

'@ -ForegroundColor Yellow

  $sx = $null
  $sy = $null
  $sz = $null
  for ($k = 0; $k -lt $SkipParsedLines; $k++) {
    Update-XYZZFromMoveLine -Line $nclines[$k] -Rx ([ref]$sx) -Ry ([ref]$sy) -Rz ([ref]$sz)
  }
  if ($null -eq $sx -or $null -eq $sy) {
    throw "Resume: could not infer last X/Y before skip index $SkipParsedLines - adjust SkipParsedLines or use -NoResumePreamble (expert)."
  }

  $head = $nclines | Select-Object -First 40
  $m3Line = $head | Where-Object { $_ -match '^(?i)M3\s+S\d+' } | Select-Object -First 1
  $g4Line = $head | Where-Object { $_ -match '^(?i)G4\s+P' } | Select-Object -First 1
  if (-not $m3Line) { throw 'Resume: no M3 line in first 40 parsed commands - add spindle line or run full job.' }

  $zr = $ResumeRetractZMm.ToString('0.###', [cultureinfo]::InvariantCulture)
  $preambleLines = @(
    'G21',
    'G17',
    'G90',
    'G94',
    'G54',
    $m3Line,
    $(if ($g4Line) { $g4Line }),
    ('G0 Z{0}' -f $zr),
    ('G0 X{0} Y{1}' -f $sx, $sy)
  ) | Where-Object { $_ }

  Write-Host ("Resume preamble retract G0 Z{0} mm (work); ends near XY ({1},{2}) last skipped Z={3}; continuing file at parsed index {4}." -f $zr, $sx, $sy, $(if ($null -eq $sz) { '(unknown)' } else { $sz }), $SkipParsedLines)
}

elseif ($SkipParsedLines -gt 0 -and $NoResumePreamble) {
  Write-Host 'WARN: -NoResumePreamble - starting mid-file without injected setup/positioning.' -ForegroundColor Red
}

$sendLines = @($preambleLines + $resumeSlice)
if ($sendLines.Count -lt 1) { throw 'Nothing to stream after resume slice.' }

$port = New-Object System.IO.Ports.SerialPort $Com, 115200, None, 8, One
$port.DtrEnable = $false
$port.RtsEnable = $false

try {
  $port.Open()
} catch {
  Write-Host ($_ | Out-String)
  Write-Host "Close Candle/disconnect COM on $Com, then rerun DryRun-WebCircle.ps1."
  exit 1
}

Start-Sleep -Milliseconds 2000

function Drain([System.IO.Ports.SerialPort]$p, $ms) {
  $acc = ""
  $dead = (Get-Date).AddMilliseconds($ms)
  while ((Get-Date) -lt $dead) {
    if ($p.BytesToRead -gt 0) { $acc += $p.ReadExisting() }
    Start-Sleep -Milliseconds 35
    if ($acc -match '(?msi)ALARM:\d+') { break }
    if ($acc -match '(?msi)error:\d+') { break }
    if ($acc -match '(?m)(^|\r|\n)ok(\r|\n|$)') { break }
  }
  Start-Sleep -Milliseconds 160
  while ($p.BytesToRead -gt 0) {
    $acc += $p.ReadExisting()
    Start-Sleep -Milliseconds 28
    if ($acc -match '(?m)(^|\r|\n)ok(\r|\n|$)') { break }
  }
  return $acc
}

function Cmd([System.IO.Ports.SerialPort]$p, [string]$s, [int]$waitMs = 5000) {
  $line = ([string]$s).TrimEnd()
  if (-not $line) { return }
  $p.DiscardInBuffer()
  $wb = [Text.Encoding]::ASCII.GetBytes($line + "`r")
  $p.Write($wb, 0, $wb.Length)
  Start-Sleep -Milliseconds 80
  $r = Drain $p $waitMs
  return $r
}

$dr = Cmd $port "?" 900
Write-Host "`n=== First status (`?`) trim ===`n$([regex]::Replace($dr.Trim(), '\s+', ' '))"
$unlock = Cmd $port '$X' 2200

if ($unlock.Trim()) {
  Write-Host "`n=== `$X response trim ===`n$([regex]::Replace($unlock.Trim(), '\s+', ' '))"
}

$dr2 = Cmd $port "?" 900
Write-Host "`n=== Status before stream ===`n$([regex]::Replace($dr2.Trim(), '\s+', ' '))"

$stAll = ($dr + "`n" + $dr2)
if ($stAll -match '<Alarm') {
  Write-Host "`nWARN: Alarm in status -- send `$X to unlock limits, fix wiring/back-off, then consider `$H to re-seat."
}

$r = ""

try {
  $i = 0
  foreach ($nl in $sendLines) {
    $i++
    Write-Host "`r>> $i / $($sendLines.Count)" -NoNewline
    $resp = Cmd $port $nl $LineWaitMs  # allow slow moves / arcs
    if ($resp -match '(?msi)alarm:') {
      Write-Host "`nSTOP ALARM sending: $nl"
      Write-Host $resp
      exit 3
    }
    if ($resp -match '(?msi)error:') {
      Write-Host "`nSTOP ERROR sending: $nl"
      Write-Host $resp
      exit 2
    }
  }
} finally {
  $end = Cmd $port "?" 1200
  Write-Host "`n=== End status (trim) ===`n$([regex]::Replace($end, '\s+', ' ').Trim())`n"
  $port.Close()
  $port.Dispose()
}

Write-Host "Streaming pass finished."
