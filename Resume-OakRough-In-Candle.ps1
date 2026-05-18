# Build a standalone resume .nc (DryRun-style preamble + tail) and open it in Candle.
# Candle streams whole programs only - send from line 1 after homing/unlock.
#
# Example:
#   .\Resume-OakRough-In-Candle.ps1
#   .\Resume-OakRough-In-Candle.ps1 -SkipParsedLines 1600 -RegenerateFeeds:$false

param(
  [bool]$StopStreamingPowerShell = $true,
  [bool]$RegenerateFeeds = $true,
  [int]$RoughFeedXY = 156,
  [int]$FeedPlungeRough = 240,
  [ValidateRange(0.1, 50)]
  [double]$RetractZMm = 5,
  [ValidateRange(0, 99999999)]
  # Parsed-line index from DryRun-WebCircle filter (same as -SkipParsedLines there).
  # Bumped after PS resume ended ~75/5291 with skip 1453 (≈1453 + 66).
  [int]$SkipParsedLines = 1519,
  [string]$SourceNcRelative = 'samples\katahdin.oak.rough.nc',
  [string]$OutRelative = 'samples\katahdin.oak.rough.candle-resume.nc',
  [ValidateRange(0.1, 50)]
  [double]$ResumeRetractZMm = 5
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

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

if ($StopStreamingPowerShell) {
  Write-Host 'Stopping PowerShell G-code streamers (DryRun / Katahdin)...' -ForegroundColor Yellow
  $streamRx = '(?i)DryRun-WebCircle\.ps1|Resume-KatahdinOakRough\.ps1|Resume-OakRough-In-Candle\.ps1|Start-KatahdinDryRun\.ps1|Run-KatahdinOakAirTestSequential\.ps1|Run-KatahdinOakSequential\.ps1|Run-KatahdinRoughLayer1\.ps1|Run-KatahdinCornerHoles\.ps1|Move-To-KatahdinG54Origin\.ps1|Move-To-KatahdinFirstCut\.ps1|Jog-Z-Relative\.ps1|Jog-X-Relative\.ps1'
  foreach ($procName in @('powershell.exe', 'pwsh.exe')) {
    Get-CimInstance Win32_Process -Filter "Name='$procName'" | ForEach-Object {
      $cl = $_.CommandLine
      if (-not $cl) { return }
      if ($cl -match '(?i)AppData\\Local\\Temp\\ps-script-') { return }
      if ($cl -notmatch $streamRx) { return }
      if ($_.ProcessId -eq $PID) { return }
      Write-Host "  Stop-Process -Id $($_.ProcessId)"
      Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
    }
  }
  Start-Sleep -Seconds 2
}

if ($RegenerateFeeds) {
  & (Join-Path $root 'New-KatahdinOakFeeds.ps1') -RoughFeedXY $RoughFeedXY -FeedPlungeRough $FeedPlungeRough -RetractZMm $RetractZMm
}

$src = Join-Path $root $SourceNcRelative
if (-not (Test-Path $src)) { throw "Missing: $src" }
$srcFull = (Resolve-Path $src).Path

$nclines = @(Get-Content $srcFull | ForEach-Object { $_.Trim() } |
  Where-Object { $_ -and ($_ -notmatch '^\(') -and ($_ -match '^(N\d+\s+)?(?i)(g|m)\d+') })

if ($nclines.Count -lt 3) { throw "Parsed G-code lines: $($nclines.Count). Check $srcFull" }
if ($SkipParsedLines -ge $nclines.Count) {
  throw "SkipParsedLines ($SkipParsedLines) must be less than parsed line count ($($nclines.Count))."
}

$sx = $null
$sy = $null
$sz = $null
for ($k = 0; $k -lt $SkipParsedLines; $k++) {
  Update-XYZZFromMoveLine -Line $nclines[$k] -Rx ([ref]$sx) -Ry ([ref]$sy) -Rz ([ref]$sz)
}
if ($null -eq $sx -or $null -eq $sy) {
  throw "Resume: could not infer last X/Y before skip index $SkipParsedLines - adjust -SkipParsedLines."
}

$head = $nclines | Select-Object -First 40
$m3Line = $head | Where-Object { $_ -match '^(?i)M3\s+S\d+' } | Select-Object -First 1
$g4Line = $head | Where-Object { $_ -match '^(?i)G4\s+P' } | Select-Object -First 1
if (-not $m3Line) { throw 'Resume: no M3 line in first 40 parsed commands.' }

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

$resumeSlice = @($nclines | Select-Object -Skip $SkipParsedLines)
$all = @($preambleLines + $resumeSlice)

$outPath = Join-Path $root $OutRelative
$hdr = @(
  '; Candle resume chunk - SPINDLE ON - verify G54 / clamps / Z retract.',
  "; Source: $SourceNcRelative",
  "; Parsed skip index (DryRun filter): $SkipParsedLines  |  preamble lines: $($preambleLines.Count)  |  tail lines: $($resumeSlice.Count)",
  "; Approx XY/Z before tail: X$sx Y$sy Z$(if ($null -eq $sz) { '?' } else { $sz })  |  retract: G0 Z$zr",
  ''
)
$body = $hdr + $all
[System.IO.File]::WriteAllLines($outPath, $body, [System.Text.UTF8Encoding]::new($false))

Write-Host ("Wrote {0} ({1} lines)." -f (Resolve-Path $outPath).Path, $body.Count) -ForegroundColor Green
Write-Host ("Preamble retract G0 Z{0} mm; rapid to X{1} Y{2}; then continue rough." -f $zr, $sx, $sy)

$candleExe = Join-Path $root 'candle-11.2\Candle\candle.exe'
if (-not (Test-Path $candleExe)) {
  throw ('Candle not found at {0} - run .\install-candle.ps1' -f $candleExe)
}
$candleDir = Split-Path $candleExe
$outFull = (Resolve-Path $outPath).Path
Write-Host "Opening Candle with:`n  $outFull" -ForegroundColor Cyan
Start-Process -FilePath $candleExe -ArgumentList @($outFull) -WorkingDirectory $candleDir

Write-Host ''
Write-Host 'Connect COM (115200), $X / $H if needed, confirm G54, then Send from line 1.'
Write-Host 'Wrong -SkipParsedLines can crash - tune from Candle preview vs stock.'
