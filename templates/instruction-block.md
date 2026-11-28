## Checks before "done" (SpaceX Dev Rules kit)

- Coding rules, checks and review: the kit's `rules/coding.md`. Claude gets it through `~/.claude/CLAUDE.md`; other agents get it in their brief.
- Before you say "done", run `.\check.ps1 <test args>`: format, lint and the tests of the changed code. It stops at the first failure and returns its exit code. `.\check.ps1 -Full` runs the whole suite; use it only before a release. Report the result; never claim a pass you did not see.
- If the change touches a workflow in `FEATURES.md`, also run that row's check command.
- When Steve corrects an agent, propose an enforced check, in this order: an API change that makes the mistake impossible, then a lint rule (linter setting or guard test), then a test. Add a prose rule only when no check is possible.
- Before you call Codex or Gemini, run `powershell -NoProfile -ExecutionPolicy Bypass -File F:\AI_Projects_4\SpaceX_Dev_Rules\usage\usage.ps1`. If Codex shows FALLBACK, use Gemini Neon, then Carbon.
