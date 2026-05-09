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
| `Close-Candle-Stop-And-Home.ps1` | **Shut down workflow:** close Candle, stop motion (hold/reset/`$X`/M5), home (`$H`). Retries COM if port was busy. |
| `Disconnect-Candle.ps1` | Stop Candle so another process can open the serial port |
| `Run-Candle-Masuter.bat` | Launch Candle pointing at `./candle-11.2/Candle/` |
| `install-candle.ps1` | Download and extract Candle 11.2 portable |
| `DryRun-WebCircle.ps1` | Stream `.nc`/`.mm.nc` lines to GRBL (**file may include M3** spindle on) |
| `Start-KatahdinDryRun.ps1` | Saved safe workflow: close Candle, `$X`, `$H`, require `Idle` with no `Pn:` pins, stream Katahdin air-dry, poll until `Idle` |
| `Move-To-Table-Center.ps1` | G53 XY toward table midpoint from EEPROM `$130`/`$131` |
| `Move-To-Z-Top.ps1` | G53 Z lift toward homed top |
| `Run-Smiley-Carve.ps1` | Helps table-centre + optional CUT-confirm carve stream for smiley pine file |
| `New-SmileyFacePineNc.ps1` | Regenerate shallow smiley contour (`samples/smiley-face-soft-pine-G54.mm.nc`) |
| `Send-HOME.ps1`, `Probe-Z-Deck.ps1`, `Spindle-On.ps1` | Machine-specific helpers (verify wiring/limit behaviour) |
| `New-ComplexDryRun.ps1` | Hypotrochoid air carve generator (`samples/complex-spirograph-air-dry.nc`) |

Set **`MASUTER_COM`** (for example `COM7`) before scripts that take `-Com`.

## Samples

Under **`samples/`**: box trace, feather circle (MIT), synthetic Z-clamped wave, generated spirograph, shallow **smiley carve** pine job (`smiley-face-soft-pine-G54.mm.nc`, G54 top-of-stock), and Mt. Katahdin rough/finish plus air-dry files. Third-party attribution: **`samples/from-web/SOURCE_AND_LICENSE.txt`**.

## Katahdin Dry Run

Use the saved workflow before streaming the Mt. Katahdin files:

```powershell
.\Start-KatahdinDryRun.ps1 -Which Finish
```

The script closes Candle, detects the CH340 COM port, clears alarm, homes, refuses active limit pins (`Pn:X`, `Pn:Z`, `Pn:XZ`), streams `samples/katahdin.finish.air-dry.nc`, and waits for GRBL to return to `Idle`. Details: **`docs/katahdin-dry-run-workflow.md`**.

After regenerating terrain with `New-TerrainNc.py`, build a **hillshaded “how it will look carved”** preview: `python New-TerrainPreviewImage.py` → **`samples/katahdin.carve-preview.png`** (source: `samples/katahdin.heightmap.png`).

For a **3D orthographic** render (Matplotlib): `python New-TerrainOrtho3D.py` → **`samples/katahdin.ortho3d.png`** (`--max-depth-mm` should match `--max-cut-mm`).

**Trail + relief preview** (Appalachian Trail only, no lettering): `python New-KatahdinMapOverlay.py` → **`samples/katahdin.map-overlay.png`**.

**Shallow trail groove for paint** (run after terrain): `python New-KatahdinTrailEngrave.py` → **`samples/katahdin-trail-light.nc`** (default **-0.35 mm** deep; use a small vee or fine ball).

**White oak carve feeds** (same geometry, slower XY / plunge, `M3 S10800`): run **`New-KatahdinOakFeeds.ps1`** → **`samples/katahdin.oak.rough.nc`** + **`samples/katahdin.oak.finish.nc`**. Optional full sequential stream (spindle on — **real cut**): **`Run-KatahdinOakSequential.ps1 -Com COM7`** (requires typing **`CUT-WHITE-OAK`**).

## Safety

Default **dry-run** samples deliberately keep spindle off and safe Z heights. **`smiley-face-soft-pine-G54.mm.nc` and Run-Smiley-Carve** turn **spindle ON (M3)** after you explicitly type `CUT` -- watch fingers, clamps, and fire-extinguisher common sense around chips.

## Repository

This project is maintained as its **own Git repository** at [`SEAS2025/FoxAlienMasuter`](https://github.com/SEAS2025/FoxAlienMasuter). Earlier snapshots may also appear in other workspaces; treat **this clone** as canonical.

Development chat logs (Cursor agent JSONL exports) live under **`docs/transcripts/`**.
