param(
  [string]$RoughIn = 'samples/katahdin.rough.nc',
  [string]$FinishIn = 'samples/katahdin.finish.nc',
  [string]$RoughOut = 'samples/katahdin.oak.rough.nc',
  [string]$FinishOut = 'samples/katahdin.oak.finish.nc',
  # White oak / stiff Masuter: slower than default 900 mm/min roughing
  [int]$RoughFeedXY = 620,
  # Finish passes are lighter
  [int]$FinishFeedXY = 720,
  [int]$FeedPlungeRough = 120,
  [int]$FeedPlungeFinish = 135,
  [int]$SpinRpm = 10800
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Replace-FeedsAndRpm {
  param(
    [string]$PathIn,
    [string]$PathOut,
    [int]$FeedXY,
    [int]$Plunge,
    [int]$Rpm
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
  [System.IO.File]::WriteAllText($pOut, $text, [System.Text.UTF8Encoding]::new($false))
  Write-Host "Wrote $pOut  (XY F$FeedXY  plunge F$Plunge  M3 S$Rpm)"
}

Replace-FeedsAndRpm $RoughIn $RoughOut $RoughFeedXY $FeedPlungeRough $SpinRpm
Replace-FeedsAndRpm $FinishIn $FinishOut $FinishFeedXY $FeedPlungeFinish $SpinRpm

Write-Host 'Done. Tune -RoughFeedXY / -FinishFeedXY if you hear chatter or burning.'
