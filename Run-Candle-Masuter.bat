@echo off
setlocal
rem Fox Alien Masuter: GRBL over USB — use CH340 driver, 115200 baud in Candle (Service ^> Settings).
set "HERE=%~dp0"
set "CND=%HERE%candle-11.2\Candle"
if not exist "%CND%\candle.exe" (
  echo Candle not found. Run install-candle.ps1 first.
  pause
  exit /b 1
)
cd /d "%CND%"
start "" "candle.exe"
