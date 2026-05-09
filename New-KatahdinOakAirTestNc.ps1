param(
  [ValidateSet('Rough', 'Finish')]
  [string]$Which = 'Finish',
  # Lift every Z so deepest pass clears empty deck (max cut ~22 mm in exaggerated file).
  [double]$ZLiftMm = 28,
  [double]$MaxWorkZ = 21.5,
  # Spindle warmup dwell: shorter than full carve for air testing.
  [int]$SpinupSeconds = 5,
  [string]$OutPath = ''
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$samples = Join-Path $root 'samples'
$base = Join-Path $samples ("katahdin.oak.{0}.nc" -f $Which.ToLower())
if (-not (Test-Path $base)) {
  throw "Missing: $base  Run .\New-KatahdinOakFeeds.ps1 first."
}
if (-not $OutPath) {
  $OutPath = Join-Path $samples ("katahdin.oak.{0}.airtest.nc" -f $Which.ToLower())
}

$rxZ = [regex]::new('Z(-?\d+(?:\.\d+)?)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

$out = New-Object System.Collections.Generic.List[string]
$out.Add("; AIR TEST - spindle ON, Z lifted +${ZLiftMm} mm (cap ${MaxWorkZ}) - no stock on deck")
$out.Add('; Same XY + feeds as oak files; only Z raised. Use hearing protection.')

foreach ($line in [System.IO.File]::ReadAllLines($base)) {
  $t = $line.Trim()
  if (-not $t -or $t.StartsWith(';')) {
    if ($t.StartsWith(';')) { $null = $out.Add($line) }
    continue
  }
  if ($t -match '^(?i)G4\s+P') {
    $null = $out.Add(("G4 P{0}" -f $SpinupSeconds))
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
Write-Host ('Wrote {0} ({1} lines).' -f $OutPath, $out.Count)
return $OutPath
