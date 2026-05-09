param(
  [string]$NcPath = (Join-Path $PSScriptRoot "samples/from-web/feather-circle-dry-75mm.nc"),
  [string]$Com = $(if ($env:MASUTER_COM) { $env:MASUTER_COM } else { "COM5" })
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $NcPath)) { throw "Missing: $NcPath" }

$nclines = @(Get-Content $NcPath | ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and ($_ -notmatch '^\(') -and ($_ -match '^(N\d+\s+)?(?i)(g|m)\d+') })

if ($nclines.Count -lt 3) { throw "Parsed G-code lines: $($nclines.Count). Check $NcPath and regex filter." }
Write-Host "G-code lines to stream: $($nclines.Count)"

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
  foreach ($nl in $nclines) {
    $i++
    Write-Host "`r>> $i / $($nclines.Count)" -NoNewline
    $resp = Cmd $port $nl 12000  # allow slow rapids across table
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

Write-Host "Dry-run done (segmented G1 at fixed Z clearance)."
