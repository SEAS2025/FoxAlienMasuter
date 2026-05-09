# Cursor agent transcripts

This folder stores **parent** Cursor agent session logs (JSONL) for this project’s development history.

| File | Session id | Notes |
|------|------------|--------|
| `cursor-agent-transcript-9938e032.jsonl` | `9938e032` | Masuter + Candle: install, serial dry-runs, complex spirograph, standalone repo setup. |
| `2026-05-09-katahdin-masuter-session.md` | — | Narrative transcript: oak air test, COM recovery (`-StopStreamingPowerShell`), live rough in Candle, `AGENTS.md`. |

Format: JSONL = one JSON object per line (Cursor export). Narrative **`.md`** summaries are used when only the chat text is archived from the agent side.

To refresh a **JSONL** from your machine, copy from under:

`%USERPROFILE%\.cursor\projects\<workspace-hash>\agent-transcripts\<parent-uuid>\<parent-uuid>.jsonl`

Example (older workspace path):

`%USERPROFILE%\.cursor\projects\c-Users-User-Desktop-MEDISOFT\agent-transcripts\9938e032-7a19-41e3-b4a6-2999f57e38e7\9938e032-7a19-41e3-b4a6-2999f57e38e7.jsonl`

If you add more JSONL sessions, use the `cursor-agent-transcript-<parent-uuid-stem>.jsonl` name and extend the table.
