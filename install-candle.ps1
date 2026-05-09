# Downloads and extracts Candle (Denvi/Candle) portable build next to this script.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$version = "11.2"
$zipName = "candle-$version-portable.zip"
$url = "https://github.com/Denvi/Candle/releases/download/v$version/$zipName"
$zipPath = Join-Path $root $zipName
$outDir = Join-Path $root "candle-$version"

if (Test-Path (Join-Path $outDir "Candle\candle.exe")) {
    Write-Host "Candle already present at: $(Join-Path $outDir 'Candle\candle.exe')"
    exit 0
}

Write-Host "Downloading $url ..."
Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing

Write-Host "Extracting to $outDir ..."
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
Expand-Archive -Path $zipPath -DestinationPath $outDir -Force

if (-not (Test-Path (Join-Path $outDir "Candle\candle.exe"))) {
    throw "Extract failed: candle.exe not found under $outDir\Candle"
}

Write-Host "Done. Run Run-Candle-Masuter.bat or: $($outDir)\Candle\candle.exe"
