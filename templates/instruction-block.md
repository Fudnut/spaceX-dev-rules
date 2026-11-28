## Checks before "done" (SpaceX Dev Rules kit)

- Before you say "done", run `.\check.ps1` (format, lint, types, tests; it stops at the first failure and returns its exit code). For a focused run, pass the test arguments: `.\check.ps1 <test args>`. With no arguments it runs the whole suite. Report the result; never claim a pass you did not see.
- If the change touches a workflow in `FEATURES.md`, also run that row's check command.
- When Steve corrects an agent, propose an enforced check, in this order: an API change that makes the mistake impossible, then a lint rule (linter setting or guard test), then a test. Add a prose rule only when no check is possible.
- Before you call Codex or Gemini, run `powershell -NoProfile -ExecutionPolicy Bypass -File F:\AI_Projects_4\SpaceX_Dev_Rules\usage\usage.ps1`. If Codex shows FALLBACK, use Gemini Neon, then Carbon.
- If the repo has `.spacex/`, every commit goes through the commit gate: follow `.spacex/REVIEW.md`. Never use `--no-verify`.
