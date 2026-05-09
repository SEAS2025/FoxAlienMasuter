# Cursor agent transcripts

This folder stores **parent** Cursor agent session logs (JSONL) for this project’s development history.

| File | Session id | Notes |
|------|------------|--------|
| `cursor-agent-transcript-9938e032.jsonl` | `9938e032` | Masuter + Candle: install, serial dry-runs, complex spirograph, standalone repo setup. |
| `cursor-export-2026-05-09-fox-alien-project-repository.md` | — | Full Cursor **Markdown export** (2026-05-09 19:38 EDT): repo lookup, Katahdin dry run, terrain, oak, recovery — copied from Downloads. |
| `2026-05-09-katahdin-masuter-session.md` | — | Narrative transcript: oak air test, COM recovery (`-StopStreamingPowerShell`), live rough in Candle, `AGENTS.md`. |

Format: JSONL = one JSON object per line (Cursor export). **Markdown exports** (full chat text from Cursor) and short narrative **`.md`** summaries are both valid archives.

Source for `cursor-export-2026-05-09-fox-alien-project-repository.md`: user export at  
`c:\Users\User\Downloads\cursor_fox_alien_project_repository.md` (copy committed here for reproducibility).

To refresh a **JSONL** from your machine, copy from under:

`%USERPROFILE%\.cursor\projects\<workspace-hash>\agent-transcripts\<parent-uuid>\<parent-uuid>.jsonl`

Example (older workspace path):

`%USERPROFILE%\.cursor\projects\c-Users-User-Desktop-MEDISOFT\agent-transcripts\9938e032-7a19-41e3-b4a6-2999f57e38e7\9938e032-7a19-41e3-b4a6-2999f57e38e7.jsonl`

If you add more JSONL sessions, use the `cursor-agent-transcript-<parent-uuid-stem>.jsonl` name and extend the table.
