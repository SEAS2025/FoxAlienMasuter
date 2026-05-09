param(
  [string]$OutFile = $(Join-Path $PSScriptRoot 'samples/smiley-face-soft-pine-G54.mm.nc'),
  [double]$DepthMm = -2.0,
  [double]$FaceRadiusMm = 34.0,
  [double]$EyeCenterY = 13.5,
  [double]$EyePathRadius = 5.0,
  [double]$MouthCx = 0.0,
  [double]$MouthCy = -12.0,
  [double]$MouthRx = 21.0,
  [double]$MouthRy = 11.0,
  [int]$MouthSeg = 42,
  [int]$FeedXY = 380,
  [int]$PlungeZFeed = 110,
  [int]$SpinRpm = 7200
)

$ErrorActionPreference = 'Stop'
$script:culture = [System.Globalization.CultureInfo]::InvariantCulture

function FNum([double]$v) {
  [string]::Format($script:culture, '{0:G7}', $v)
}

$L = New-Object System.Collections.Generic.List[string]
[void]$L.Add('; smiley_face_soft_pine G54 XY board center Z TOP of pine spindle ON')
[void]$L.Add(('; Soft pine nominally 25 mm. G54 Z0 = TOP surface. Deepest cut Z = ' + (FNum $DepthMm) + ' mm'))
[void]$L.Add('; CLAMP BOARD. KEEP CLEAR. E_STOP ready.')
[void]$L.Add('; AFTER homing jog over BOARD geometric center THEN zero G54 XY in Candle.')
[void]$L.Add('; Zero G54 Z on TOP of pine thin-paper-drag or jog down until scratch then Z0.')
[void]$L.Add('; Tool suggestion: approx 3 mm two-flute down-cut for fuzz control on pine')
$L.Add('')
$L.Add('G21')
$L.Add('G17')
$L.Add('G90')
$L.Add('G94')
$L.Add('G54')
$L.Add('')
$L.Add('M5')
$L.Add('G4 P2')
$L.Add(('M3 S{0}' -f $SpinRpm))
$L.Add('G4 P4')
$L.Add('')
$L.Add('G0 Z10')

$fr = [double]$FaceRadiusMm
$L.Add(('G0 X{0} Y{1}' -f (FNum $fr), (FNum ([double]0))))

$L.Add('G1 Z1.0 F800')
$L.Add(('G1 Z{0} F{1}' -f ((FNum $DepthMm)), $PlungeZFeed))
$L.Add(('G3 X{0} Y{1} I{2} J0 F{3}' -f (FNum $fr), (FNum ([double]0)), (FNum (-$fr)), $FeedXY))

$L.Add('')
$L.Add('G0 Z10')

$eyes = @(
  @{ Cx=-12.5; Cy=$EyeCenterY; R=$EyePathRadius },
  @{ Cx=12.5;  Cy=$EyeCenterY; R=$EyePathRadius }
)

foreach ($e in $eyes) {
  [double]$xs = $e.Cx + $e.R
  $L.Add(('G0 X{0} Y{1}' -f (FNum $xs), (FNum $e.Cy)))
  $L.Add('G1 Z1 F800')
  $L.Add(('G1 Z{0} F{1}' -f (FNum $DepthMm), $PlungeZFeed))
  $L.Add(('G3 X{0} Y{1} I{2} J0 F{3}' -f (FNum $xs), (FNum $e.Cy), (FNum (-$e.R)), $FeedXY))
  $L.Add('')
  $L.Add('G0 Z10')
}

$tpi = [math]::PI

$first = $true

for ($si = 0; $si -le $MouthSeg; $si++) {
  [double]$t = $tpi + ($si / [double]$MouthSeg) * $tpi
  [double]$mx = [math]::Round(($MouthCx + $MouthRx * [math]::Cos($t)), 4)
  [double]$my = [math]::Round(($MouthCy + $MouthRy * [math]::Sin($t)), 4)

  if ($first) {
    $first = $false
    $L.Add(('G0 X{0} Y{1}' -f (FNum $mx), (FNum $my)))
    $L.Add('G1 Z1 F800')
    $L.Add(('G1 Z{0} F{1}' -f (FNum $DepthMm), $PlungeZFeed))
  }
  else {
    $L.Add(('G1 X{0} Y{1} F{2}' -f (FNum $mx), (FNum $my), $FeedXY))
  }
}

$L.Add('')
$L.Add('G0 Z10')
$L.Add('G0 X0 Y0')
$L.Add('M5')
$L.Add('G4 P3')
$L.Add('')
$L.Add('; end smiley carve')

[System.IO.File]::WriteAllLines($OutFile, $L.ToArray(), [System.Text.UTF8Encoding]::new($false))

Write-Host "Wrote $OutFile lines=$($L.Count)"
