param(
  [ValidateSet('Rough', 'Finish')]
  [string]$Which = 'Finish',
  # Added to every Z in the file so the tool stays above the board (stock top = G54 Z0).
  # Default 25 mm leaves >=3 mm air clearance for the current Katahdin files
  # generated with --max-cut-mm 22.
  [double]$ZLiftMm = 25,
  # Masuter: homed MPos Z is ~-1; with typical G54 WCO Z ~-23, work Z must stay ~<=22.5 or Z+
  # requests ram the top limit. Clamp lifted coords so rapids never exceed this work-Z ceiling.
  [double]$MaxWorkZ = 21.5,
  [string]$OutPath = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$samples = Join-Path $root 'samples'
$base = Join-Path $samples ("katahdin.{0}.nc" -f $Which.ToLower())
if (-not (Test-Path $base)) { throw "Missing: $base" }
if (-not $OutPath) {
  $OutPath = Join-Path $samples ("katahdin.{0}.air-dry.nc" -f $Which.ToLower())
}

$rxZ = [regex]::new('Z(-?\d+(?:\.\d+)?)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$out = New-Object System.Collections.Generic.List[string]
$out.Add("; AIR DRY - spindle off, Z lifted +${ZLiftMm} mm (cap work Z ${MaxWorkZ}) from: $(Split-Path $base -Leaf)")
$out.Add('; Close Candle; connect USB; jog/zero as for a real run; this traces XY only in air.')

foreach ($line in [System.IO.File]::ReadAllLines($base)) {
  $t = $line.Trim()
  if (-not $t -or $t.StartsWith(';')) {
    if ($t.StartsWith(';')) { $null = $out.Add($line) }
    continue
  }
  if ($t -match '^(?i)M3\s') {
    $null = $out.Add('M5 ; was M3 - dry run')
    continue
  }
  if ($t -match '^(?i)G4\s+P') {
    $null = $out.Add('; G4 dwell skipped (no spindle warmup)')
    continue
  }
  $newLine = $rxZ.Replace($line, {
      param($m)
      $z = [double]::Parse($m.Groups[1].Value, [System.Globalization.CultureInfo]::InvariantCulture)
      $z2 = $z + $ZLiftMm
      if ($z2 -gt $MaxWorkZ) { $z2 = $MaxWorkZ }
      return ('Z{0}' -f $z2.ToString('0.####', [cultureinfo]::InvariantCulture))
    })
  $null = $out.Add($newLine)
}

[System.IO.File]::WriteAllLines($OutPath, $out.ToArray(), [System.Text.UTF8Encoding]::new($false))
Write-Host ("Wrote {0} ({1} lines)." -f $OutPath, $out.Count)
return $OutPath
