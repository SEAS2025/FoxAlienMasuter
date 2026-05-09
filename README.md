# Fox Alien Masuter (GRBL) automation

Standalone repository for **Fox Alien Masuter-class** routers running **GRBL 1.x** over **USB serial** (often CH341/CH340), plus **dry-run / air-carve** sample G-code.

## Prerequisites

1. **Windows** PowerShell **5.x** or **PowerShell Core** (`System.IO.Ports`).
2. USB driver for CH340 from WCH if no COM port appears.
3. **Candle**: run `install-candle.ps1` (downloads Candle 11.2 portable beside this repo) or point `Run-Candle-Masuter.bat` at your install.

Operational notes, COM quirks, limit-switch behavior: see **`masuter-setup.txt`**.

## Scripts

| Script | Purpose |
|--------|---------|
| `Disconnect-Candle.ps1` | Stop Candle so another process can open the serial port |
| `Run-Candle-Masuter.bat` | Launch Candle pointing at `./candle-11.2/Candle/` |
| `install-candle.ps1` | Download and extract Candle 11.2 portable |
| `DryRun-WebCircle.ps1` | Stream a `.nc` file line-by-line to GRBL (default: Feather circle dry path) |
| `Move-To-Table-Center.ps1` | G53 XY move toward table centre from EEPROM `$130`/`$131` |
| `Move-To-Z-Top.ps1` | G53 Z move to configured homed-top machine coordinate |
| `Send-HOME.ps1`, `Probe-Z-Deck.ps1`, `Spindle-On.ps1` | Machine-specific utilities (verify wiring before relying on them) |
| `New-ComplexDryRun.ps1` | Generate a dense hypotrochoid air path (`samples/complex-spirograph-air-dry.nc`-style) |

Set **`MASUTER_COM`** (for example `COM7`) before scripts that take `-Com`.

## Samples

Under **`samples/`**: box trace, feather circle (MIT), synthetic Z-clamped wave, generated spirograph. Third-party attribution: **`samples/from-web/SOURCE_AND_LICENSE.txt`**.

## Safety

Dry-run NC files intend **fixed safe Z** above the spoilboard **and** spindle off unless you deliberately change code. Confirm machine coordinates, feeds, and limit wiring before unattended runs.

## Repository

This project is maintained as its **own Git repository** at [`SEAS2025/FoxAlienMasuter`](https://github.com/SEAS2025/FoxAlienMasuter). Earlier snapshots may also appear in other workspaces; treat **this clone** as canonical.
