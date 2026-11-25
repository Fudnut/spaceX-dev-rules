# Usage Limit Tracker

## What the script shows
`usage.ps1` prints one table for Codex, Claude accounts, and Gemini models.
Each row shows 5-hour and weekly percentages, local reset times, update time, and status.

## Commands
- Show table: `powershell -NoProfile -ExecutionPolicy Bypass -File usage\usage.ps1`
- Show JSON: `powershell -NoProfile -ExecutionPolicy Bypass -File usage\usage.ps1 -Json`
- Record Claude usage: `powershell -NoProfile -ExecutionPolicy Bypass -File usage\usage.ps1 -RecordClaude -FiveHour 10 -Weekly 20 -FiveHourReset 2030-01-01T00:00:00Z -WeeklyReset 2030-01-05T00:00:00Z`
- Mark Gemini exhausted: `powershell -NoProfile -ExecutionPolicy Bypass -File usage\usage.ps1 -GeminiExhausted neon -Until 2030-01-01T00:00:00Z`
- Clear Gemini exhausted state: `powershell -NoProfile -ExecutionPolicy Bypass -File usage\usage.ps1 -GeminiOk neon`

## Shared ledger
Set `AI_USAGE_LEDGER` on each computer to the full path of one shared `ledger.json`, so all computers use the same records.
If the variable is not set, or its folder cannot be reached, the script uses `usage\ledger.json` and prints a warning.

## Data sources
- Codex: The script reads Codex session logs directly. These numbers are exact.
- Claude: Each session records its signed-in account with numbers from the Claude app usage tool.
- Gemini: No usage data exists. The ledger records quota errors only.

## Fallback rules
- Before each Codex call, run usage.ps1. If Codex shows FALLBACK, use Gemini Neon, then Carbon, as the verifier.
- Claude sessions record their account at work boundaries. At STOP, write the handoff and continue on the Claude account with the most weekly limit left.
- On a Gemini quota error, run -GeminiExhausted with the reset time if known, else 5 hours from now. Fallback order: Neon -> Carbon -> Hydrogen -> Cheap Agent (DeepSeek Flash).
