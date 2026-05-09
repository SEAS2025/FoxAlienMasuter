param(
  [string]$OutFile = $(Join-Path $PSScriptRoot 'samples/smiley-face-soft-pine-G54.mm.nc'),
  [double]$DepthMm = -7.0,
  [double]$StepDownMm = 2.0,
  [double]$FaceRadiusMm = 34.0,
  [double]$EyeCenterY = 13.5,
  [double]$EyePathRadius = 5.0,
  [double]$MouthCx = 0.0,
  [double]$MouthCy = -12.0,
  [double]$MouthRx = 21.0,
  [double]$MouthRy = 11.0,
  [int]$MouthSeg = 42,
  [int]$FeedXY = 145,
  [int]$PlungeZFeed = 45,
  [int]$ApproachXYFeed = 220,
  [double]$SafeZMm = 18.0,
  [double]$SkinZMm = 1.0,
  [int]$SpinRpm = 10000,
  # Dwell after M3 before first G0/G1 (allow VFD/Router spin-up).
  [int]$SpinupDwellSeconds = 18
)

$ErrorActionPreference = 'Stop'
if ($DepthMm -ge -0.0001) { throw 'DepthMm must be negative (below stock top Z0).' }
if ($StepDownMm -le 0.1) { throw 'StepDownMm must be positive (mm per slice).' }

$script:culture = [System.Globalization.CultureInfo]::InvariantCulture

function FNum([double]$v) {
  [string]::Format($script:culture, '{0:G7}', $v)
}

function Get-ZLevels([double]$TargetDepthNeg, [double]$StepDownPositive) {
  $ta = [math]::Abs($TargetDepthNeg)
  $acc = 0.0
  $list = New-Object System.Collections.Generic.List[double]
  while ($acc + 1e-9 -lt $ta) {
    $acc = [math]::Min($acc + $StepDownPositive, $ta)
    $list.Add(-$acc)
  }
  if ($list.Count -lt 1) {
    throw 'No depth slices; check DepthMm / StepDownMm.'
  }
  return [double[]]$list.ToArray()
}

$levels = @(Get-ZLevels $DepthMm $StepDownMm)
$fr = [double]$FaceRadiusMm
$Ssafe = '{0:G7}' -f $SafeZMm
$psk = '{0:G7}' -f $SkinZMm

$L = New-Object System.Collections.Generic.List[string]
[void]$L.Add('; smiley_face_soft_pine MULTI_PASS shallow smiley carve')
[void]$L.Add(('; G54 XY board centre spindle ON; Deepest FINAL Z slice = ' + (FNum $levels[-1]) + ' mm'))
[void]$L.Add('; Step-down passes (~StepDownMm) then retract SafeZ clears chips')
[void]$L.Add('; Stream order intended: **M3 + dwell BEFORE any XYZ move**')
[void]$L.Add('')
$L.Add(('M3 S{0}' -f $SpinRpm))
$L.Add(('G4 P{0}' -f $SpinupDwellSeconds))
$L.Add('G21')
$L.Add('G17')
$L.Add('G90')
$L.Add('G94')
$L.Add('G54')
$L.Add('')
$L.Add(('G0 Z' + $Ssafe))

foreach ($zd in $levels) {
  $zStr = FNum $zd
  $L.Add('')
  $L.Add('; --- face tier Z ' + $zStr + ' ---')
  $L.Add(('G0 Z{0}' -f $Ssafe))
  $L.Add(('G0 X{0} Y{1}' -f (FNum $fr), (FNum ([double]0))))
  $L.Add(('G1 Z{0} F{1}' -f $psk, $ApproachXYFeed))
  $L.Add(('G1 Z{0} F{1}' -f $zStr, $PlungeZFeed))
  $L.Add(('G3 X{0} Y{1} I{2} J0 F{3}' -f (FNum $fr), (FNum ([double]0)), (FNum (-$fr)), $FeedXY))
  $L.Add(('G0 Z{0}' -f $Ssafe))
}

$L.Add('')
$L.Add('; --- eyes multi-pass ---')
$eyes = @(
  @{ Cx=-12.5; Cy=$EyeCenterY; R=$EyePathRadius },
  @{ Cx=12.5;  Cy=$EyeCenterY; R=$EyePathRadius }
)

foreach ($e in $eyes) {
  [double]$xs = $e.Cx + $e.R

  foreach ($zd in $levels) {
    $zStr = FNum $zd
    $L.Add('')
    $L.Add('; eye CX=' + ($e.Cx) + ' CY=' + ($e.Cy) + ' depth ' + $zStr)
    $L.Add(('G0 Z{0}' -f $Ssafe))
    $L.Add(('G0 X{0} Y{1}' -f (FNum $xs), (FNum $e.Cy)))
    $L.Add(('G1 Z{0} F{1}' -f $psk, $ApproachXYFeed))
    $L.Add(('G1 Z{0} F{1}' -f $zStr, $PlungeZFeed))
    $L.Add(('G3 X{0} Y{1} I{2} J0 F{3}' -f (FNum $xs), (FNum $e.Cy), (FNum (-$e.R)), $FeedXY))
    $L.Add(('G0 Z{0}' -f $Ssafe))
  }
}

$tpi = [math]::PI
$mxPts = New-Object double[] ($MouthSeg + 1)
$myPts = New-Object double[] ($MouthSeg + 1)

for ($si = 0; $si -le $MouthSeg; $si++) {
  [double]$t = $tpi + ($si / [double]$MouthSeg) * $tpi
  $mxPts[$si] = [math]::Round(($MouthCx + $MouthRx * [math]::Cos($t)), 4)
  $myPts[$si] = [math]::Round(($MouthCy + $MouthRy * [math]::Sin($t)), 4)
}

$L.Add('')
$L.Add('; --- mouth multi-pass contour ---')

foreach ($zd in $levels) {
  $zStr = FNum $zd
  $L.Add('')
  $L.Add('; mouth tier depth ' + $zStr)

  for ($pj = 0; $pj -le $MouthSeg; $pj++) {
    [double]$jx = $mxPts[$pj]
    [double]$jy = $myPts[$pj]

    if ($pj -eq 0) {
      $L.Add(('G0 Z{0}' -f $Ssafe))
      $L.Add(('G0 X{0} Y{1}' -f (FNum $jx), (FNum $jy)))
      $L.Add(('G1 Z{0} F{1}' -f $psk, $ApproachXYFeed))
      $L.Add(('G1 Z{0} F{1}' -f $zStr, $PlungeZFeed))
    }
    else {
      $L.Add(('G1 X{0} Y{1} F{2}' -f (FNum $jx), (FNum $jy), $FeedXY))
    }
  }

  $L.Add(('G0 Z{0}' -f $Ssafe))
}

$L.Add('')
$L.Add(('G0 Z{0}' -f $Ssafe))
$L.Add('G0 X0 Y0')
$L.Add('M5')
$L.Add('G4 P3')
$L.Add('')
$L.Add('; end smiley carve')

[System.IO.File]::WriteAllLines($OutFile, $L.ToArray(), [System.Text.UTF8Encoding]::new($false))

$deepest = FNum $levels[-1]

Write-Host "Wrote $OutFile lines=$($L.Count) levels=$($levels.Length) deepest=$deepest mm"
