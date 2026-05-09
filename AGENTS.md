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
