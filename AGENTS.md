# Agent / operator notes (Masuter + Katahdin)

## Stopping the machine and freeing COM

When a job is still streaming from **PowerShell** (`DryRun-WebCircle.ps1`, Katahdin runners), **closing Candle alone is not enough** — COM stays denied.

**Verified workflow** (from repo root):

```powershell
.\Close-Candle-Stop-And-Home.ps1 -Com COM7 -StopStreamingPowerShell
```

- Stops Candle, optionally ends matching **PowerShell** streamer PIDs (repo scripts only; skips Cursor temp `ps-script` wrappers).
- Then: GRBL feed hold, soft reset, `$X`, **M5**, **`$H`**, wait for **Idle**.

Alias: `Stop-Masuter-And-Home.ps1` (same parameters).

## Live white-oak rough in Candle

- Regenerate feeds and open **rough** in Candle: `.\Open-LiveOakRough-In-Candle.ps1`
- Outputs: `samples/katahdin.oak.rough.nc` (rough), `samples/katahdin.oak.finish.nc` (finish). Same **G54** as tests; **spindle on** in file — only with stock clamped.

## Full detail

See `docs/katahdin-dry-run-workflow.md` and `README.md`.

## Plank / operator-defined far-right limit

Marked after exploratory **−X** jogs from streaming/session stops (**do not treat as a soft-limit probe substitute** — confirm **`?`** / **`Pn:`** on your machine).

**Treat this pose as the new usable far-right boundary** (until you change **`G54`** or homing again):

| Quantity | Value |
|---------|--------|
| **`MPos` X** (when marked) | **−175 mm** |
| **`WCO` X** (same snapshot) | **−363 mm** ⇒ **`Work X` ≈ 188 mm** |

Meaning with **unchanged `G54`**: keep **terrain / drills max `Work X` below ~187–188 mm** (leave margin), **or** re-zero **`G54` XY** on the plank and re-measure.

**Regenerated jobs:** `samples/katahdin*.nc` use **`--board-mm 186`** so **finish max `Work X` ≈ 185 mm** (inside this limit). If you change clamps or **`G54`**, regenerate / remeasure.

If **`MPos` Y/Z were not meaningful** (e.g. never **`$H`** after e-stop), **home (`$H`)**, **re-touch `G54`**, **repeat marking**.

## Z retract vs upper limit (`Pn:Z`)

Terrain programs used **`G0 Z10`** rapids; with some **`G54` / `WCO`** mappings that still drives **machine Z** high enough to hit the **upper Z stop** (`Pn:Z`, **`ALARM:3`**).

Repo mitigations:

- **`New-KatahdinOakFeeds.ps1`** **`-RetractZMm`** (default **5**): rewrites **`G0 Z10`** → **`G0 Z<n>`** in generated oak rough/finish.
- **`DryRun-WebCircle.ps1`** **`-ResumeRetractZMm`**: resume preamble retract before **`G0 X… Y…`** (same idea as feeds script).
- **`Open-LiveOakRough-In-Candle.ps1`** regenerates oak with **`-RoughFeedXY 156`**, **`-FeedPlungeRough 240`**, **`-RetractZMm 5`** by default (2× rough vs legacy **78/120**).

Lower **`-RetractZMm`** further if the switch still trips; raise slightly only if rapids foul clamps.

## Resume mid-job

- **PowerShell:** **`Resume-KatahdinOakRough.ps1`** calls **`New-KatahdinOakFeeds.ps1`** then **`DryRun-WebCircle.ps1`** **`-SkipParsedLines <n>`** (index into **parsed** lines: comments stripped; same filter as DryRun). Wrong skip can crash; advance from logged **`>> i / total`** if a run stops early.
- **Candle (no line-skip in GUI):** **`Resume-OakRough-In-Candle.ps1`** emits **`samples/katahdin.oak.rough.candle-resume.nc`** (modal + **`M3`** / **`G4`** + retract + XY + remainder of rough) and launches Candle — **Send from line 1**.

**COM handoff:** **`Close-Candle-Stop-And-Home.ps1`** and **`Open-LiveOakRough-In-Candle.ps1`** also match-kill **`Resume-OakRough-In-Candle.ps1`** child flows where applicable.

## Spindle speed vs CAM (`M3 S24000`)

Grbl **`$30`** = **max spindle RPM** used for **`S`** PWM scaling. If **`$30=10000`**, status **`FS:`** will **cap** around **10000** even when you command **`S24000`**. Set **`$30`** to your real maximum (e.g. **`$30=24000`**), **`$$`** to confirm, then verify **VFD / router** follows PWM.

Quick check: **`Test-MasuterAxesAndSpindle.ps1`** **`-Com COM7`** (full test homes first). If **`Pn:`** blocks homing, use **`-SkipHome -SpindleOnly`** for **`$$`** + stepped **`M3 S`** only.

## Optional bench monitor

**`Watch-CncSensor.ps1`** + **`tools/cnc_sensor_watch.py`** (`pip install -r requirements-cnc-watch.txt`): webcam motion hint, mic RMS spikes, optional **`--com`** **`?`** status (**exclusive port** — stop Candle first).
