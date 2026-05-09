param(
  [string]$OutFile = (Join-Path $PSScriptRoot 'samples/complex-spirograph-air-dry.nc'),

  # Safe machine-coord envelope (NEGATIVE machine coords, this Masuter homes top-right corner).
  # MPos Z=-1 is the homed top; MPos Z=-46 was ~5 mm above the deck.
  # Z=-15 keeps the bit ~36 mm above the deck the entire run.
  [double]$CenterX = -200,
  [double]$CenterY = -190,
  [double]$ZAir    = -15,
  [double]$ZPark   = -1,
  [double]$Feed    = 4200,

  # Spirograph parameters: hypocycloid-with-pen-offset (R, r, d).
  # R=120 r=37 d=80 -> long, dense, non-trivial braid that fits easily inside the travel box.
  [double]$BigR   = 120,
  [double]$LittleR = 37,
  [double]$PenD   = 80,
  [int]   $Steps  = 1500,
  [double]$Sweeps = 12   # multiples of 2*pi over t (more sweeps -> more interleaved petals)
)

$ErrorActionPreference = 'Stop'

# Hard XY guard (machine coords); pattern is clipped to these.
$xMin = -360; $xMax = -40
$yMin = -340; $yMax = -40

# Z guard: NEVER below -50 (would collide with the deck at the 50 mm reference).
if ($ZAir -lt -45 -or $ZAir -gt -2)  { throw "ZAir $ZAir out of safe machine band [-45..-2]." }
if ($ZPark -lt -45 -or $ZPark -gt -1) { throw "ZPark $ZPark out of safe machine band [-45..-1]." }

$lines = New-Object System.Collections.Generic.List[string]
$null = $lines.Add('; complex air-dry spirograph (machine coords, G53 per motion)')
$null = $lines.Add(('; SPINDLE STAYS OFF. Z fixed at MPos {0:F2} the entire job (~{1:F0} mm above deck).' -f $ZAir, (50 - ([math]::Abs($ZAir) - 1))))
$null = $lines.Add(('; Travel guard: X[{0},{1}] Y[{2},{3}], Z>={4}.' -f $xMin,$xMax,$yMin,$yMax,(-45)))
$null = $lines.Add('G21 G90 G17 G94')
$null = $lines.Add('M5')
$null = $lines.Add('G53 G0 Z-1')
$null = $lines.Add(('G53 G0 X{0:F3} Y{1:F3} F4500' -f $CenterX, $CenterY))
$null = $lines.Add(('G53 G1 Z{0:F3} F2000' -f $ZAir))

# Quick perimeter rectangle (sanity sweep around the work area before the dense pattern).
$rectHX = 130; $rectHY = 130
$rxL = [math]::Max($xMin, $CenterX - $rectHX); $rxR = [math]::Min($xMax, $CenterX + $rectHX)
$ryB = [math]::Max($yMin, $CenterY - $rectHY); $ryT = [math]::Min($yMax, $CenterY + $rectHY)
foreach ($pt in @(@($rxL,$ryB),@($rxR,$ryB),@($rxR,$ryT),@($rxL,$ryT),@($rxL,$ryB))) {
  $null = $lines.Add(('G53 G1 X{0:F3} Y{1:F3} F{2:F0}' -f $pt[0], $pt[1], $Feed))
}

# Spirograph (hypotrochoid):
#   x(t) = (R - r) * cos(t) + d * cos((R - r)/r * t)
#   y(t) = (R - r) * sin(t) - d * sin((R - r)/r * t)
$Rmr = $BigR - $LittleR
$ratio = $Rmr / $LittleR
$tMax = [math]::PI * 2.0 * $Sweeps
$dt   = $tMax / $Steps

# Move to first point of the spiro before switching from rect-end to spiro-start.
function PointAt([double]$t) {
  $cx = $script:CenterX + ($script:Rmr * [math]::Cos($t)) + ($script:PenD * [math]::Cos($script:ratio * $t))
  $cy = $script:CenterY + ($script:Rmr * [math]::Sin($t)) - ($script:PenD * [math]::Sin($script:ratio * $t))
  if ($cx -lt $script:xMin) { $cx = $script:xMin }
  if ($cx -gt $script:xMax) { $cx = $script:xMax }
  if ($cy -lt $script:yMin) { $cy = $script:yMin }
  if ($cy -gt $script:yMax) { $cy = $script:yMax }
  return @($cx, $cy)
}

$first = PointAt 0.0
$null = $lines.Add(('G53 G0 X{0:F3} Y{1:F3}' -f $first[0], $first[1]))

for ($i = 1; $i -le $Steps; $i++) {
  $p = PointAt ($i * $dt)
  $null = $lines.Add(('G53 G1 X{0:F3} Y{1:F3} F{2:F0}' -f $p[0], $p[1], $Feed))
}

$null = $lines.Add(('G53 G0 Z{0:F3}' -f $ZPark))
# Park a few mm shy of the home corner so we don't tickle the Y/X limit switches.
$null = $lines.Add('G53 G0 X-395 Y-375')
$null = $lines.Add('M5')
$null = $lines.Add('; end')

[System.IO.File]::WriteAllLines($OutFile, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0} ({1} lines)." -f $OutFile, $lines.Count)
