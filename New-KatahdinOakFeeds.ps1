param(
  [string]$RoughIn = 'samples/katahdin.rough.nc',
  [string]$FinishIn = 'samples/katahdin.finish.nc',
  [string]$RoughOut = 'samples/katahdin.oak.rough.nc',
  [string]$FinishOut = 'samples/katahdin.oak.finish.nc',
  # White oak / stiff Masuter (XY translation; ~1/8 of original 620 / 720 mm/min)
  [int]$RoughFeedXY = 78,
  [int]$FinishFeedXY = 90,
  [int]$FeedPlungeRough = 120,
  [int]$FeedPlungeFinish = 135,
  # Trim-router class often tops ~24k; verify your VFD/PWM maps M3 S correctly.
  [int]$SpinRpm = 24000,
  # Rapids `G0 Z10` in terrain NC → this Z (mm, work). Lower if Z max limit trips on retract.
  [ValidateRange(0.1, 50)]
  [double]$RetractZMm = 5
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Replace-FeedsAndRpm {
  param(
    [string]$PathIn,
    [string]$PathOut,
    [int]$FeedXY,
    [int]$Plunge,
    [int]$Rpm,
    [double]$RetractZMm = 5
  )
  $pIn = Join-Path $root $PathIn
  $pOut = Join-Path $root $PathOut
  if (-not (Test-Path $pIn)) { throw "Missing: $pIn" }
  $text = [System.IO.File]::ReadAllText($pIn)
  $text = [regex]::Replace($text, ' F900(\s)', {
      param($m)
      return (' F{0}{1}' -f $FeedXY, $m.Groups[1].Value)
    })
  $text = [regex]::Replace($text, ' F200(\s)', {
      param($m)
      return (' F{0}{1}' -f $Plunge, $m.Groups[1].Value)
    })
  # Trailing F900 or F200 at EOF (no trailing space)
  if ($text -match ' F900\s*$') { $text = $text -replace ' F900\s*$', (' F{0}' -f $FeedXY) }
  if ($text -match ' F200\s*$') { $text = $text -replace ' F200\s*$', (' F{0}' -f $Plunge) }

  $text = [regex]::Replace($text, 'M3 S\d+', ('M3 S{0}' -f $Rpm))
  if ($RetractZMm -ne 10) {
    $zTxt = $RetractZMm.ToString('0.###', [cultureinfo]::InvariantCulture)
    $text = [regex]::Replace($text, '(?im)^G0 Z10\s*$', ('G0 Z{0}' -f $zTxt))
  }
  [System.IO.File]::WriteAllText($pOut, $text, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Wrote $pOut  (XY F$FeedXY  plunge F$Plunge  M3 S$Rpm  retract G0 Z$($RetractZMm.ToString('0.###',[cultureinfo]::InvariantCulture)))"
}

Replace-FeedsAndRpm $RoughIn $RoughOut $RoughFeedXY $FeedPlungeRough $SpinRpm $RetractZMm
Replace-FeedsAndRpm $FinishIn $FinishOut $FinishFeedXY $FeedPlungeFinish $SpinRpm $RetractZMm

Write-Host 'Done. Tune -RoughFeedXY / -FinishFeedXY if you hear chatter or burning.'
