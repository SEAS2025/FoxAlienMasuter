# Katahdin Dry-Run Workflow

Use this workflow before streaming the Mt. Katahdin toolpaths so the machine does not get stuck on hard stops.

## Close Candle, stop activity, return home (always this order)

When you need to **stop the job**, **free COM**, and put the machine back at **limit home**, run one command from the repo root:

```powershell
.\Close-Candle-Stop-And-Home.ps1 -Com COM7 -StopStreamingPowerShell
```

Use **`-StopStreamingPowerShell`** when COM stays denied (a `DryRun-WebCircle` / Katahdin runner PowerShell still holds the port).

Or set `MASUTER_COM` and omit `-Com`. The script:

1. **Closes Candle** so nothing holds the CH340 serial port (same as `Disconnect-Candle.ps1`).
2. **Stops activity**: feed hold, GRBL soft reset, `$X`, `M5` (spindle off).
3. **Homes** with `$H` and waits for `Idle` without active `Pn:` limit pins.

If the port is still busy, something else holds COM (often a **PowerShell** window running `DryRun-WebCircle` or a Katahdin runner). The script **retries opening COM** after closing Candle; if it still fails, pass **`-StopStreamingPowerShell`** to end only those repo streamer processes (Cursor temp scripts are excluded), or close that window manually.

`Stop-Masuter-And-Home.ps1` is a thin alias for the same workflow.

Dry-run and oak automation scripts still **close Candle at the start** of a run so a fresh PowerShell streamer can open COM; use **Close-Candle-Stop-And-Home.ps1** when you are **done** or need to **recover** without hunting which process owns the port.

## One-command dry run

From this repository:

```powershell
.\Start-KatahdinDryRun.ps1 -Which Finish
```

That script:

1. Closes Candle if it is holding the CH340 serial port.
2. Detects the current USB serial COM port, for example `COM7`.
3. Regenerates `samples/katahdin.finish.air-dry.nc` if missing.
4. Sends `$X` to clear alarm state.
5. Sends `$H` and waits for GRBL to report `Idle`.
6. Refuses to stream if status includes active pins such as `Pn:X`, `Pn:Z`, or `Pn:XZ`.
7. Streams the air-dry file with spindle off.
8. Polls after sending until buffered GRBL motion returns to `Idle`.

Use `-Which Rough` for the roughing air-dry file.

## Manual checklist

If running by hand in Candle or with scripts:

1. Disconnect or close Candle before any PowerShell streamer opens the COM port.
2. Confirm the CNC is on the CH340 port shown by Windows, commonly `COM7` after reconnect.
3. Send `$X`.
4. Send `$H`.
5. Poll `?` and confirm the response looks like:

   ```text
   <Idle|MPos:-399.000,-379.000,-1.000|...>
   ```

6. Do not stream if the response includes `Pn:`. Examples that must be fixed first:

   ```text
   Pn:X
   Pn:Z
   Pn:XZ
   ```

7. Stream `samples/katahdin.finish.air-dry.nc`.
8. After the streamer says "Streaming pass finished", keep polling until GRBL returns to `Idle`; GRBL may still be executing buffered moves.

## Known lessons from the successful run

- Candle can keep the COM port locked. Close it before script control.
- A **PowerShell G-code streamer** (`DryRun-WebCircle`, Katahdin runners) often keeps COM locked **even after Candle is closed** — use **`Close-Candle-Stop-And-Home.ps1 -StopStreamingPowerShell`** (verified fix).
- A stale PowerShell process can also keep COM locked after homing; stop only the stale process that owns the port, not an active streamer.
- The air-dry Z is capped by `New-KatahdinAirDryNc.ps1` so `G0 Z` does not request motion above the homed Z top.
- The Katahdin files are scaled to about `356 x 330 mm` so they fit the observed Masuter travel with the current `G54` offset.
- A sender can finish before the controller is done moving. Final success is GRBL status `Idle`, not just the sender exiting.

## Live oak rough in Candle

From repo root (regenerates oak `.nc` files, then starts Candle on the **rough** program):

```powershell
.\Open-LiveOakRough-In-Candle.ps1
```

Finish program (open manually in Candle after rough): `samples/katahdin.oak.finish.nc`.

## Files

- `Start-KatahdinDryRun.ps1` - saved safe workflow.
- `samples/katahdin.finish.air-dry.nc` - spindle-off finish dry run.
- `samples/katahdin.rough.air-dry.nc` - spindle-off rough dry run.
- `samples/katahdin.finish.nc` - real finish pass.
- `samples/katahdin.rough.nc` - real rough pass.
- `samples/katahdin.oak.rough.nc` / `katahdin.oak.finish.nc` - white oak feeds (spindle on); open rough via `Open-LiveOakRough-In-Candle.ps1`.
