# Coding rules

One text for every project and every agent. Claude reads it through `~/.claude/CLAUDE.md` and puts "Rules for the writer" in every brief to a worker or reviewer.

Objective: lean, correct code at the first attempt. Simple code needs few tests and little review.

## Brief (the orchestrator, before any code)

Search the code first. Then give the writer:

- Goal: what the user sees, or what must be true, after the change.
- Reuse: the existing functions, types or patterns to use, by name.
- Files, and one existing caller to read first.
- Failure (only for code that changes user data): what must stay true if the operation fails in real use or is cancelled. Example: a move to another drive keeps the source until the copy is complete.
- Check: the command that proves success. For data code, also the command that proves the failure behavior. For a change to shared code, also the tests of its callers.
- Size: the expected number of added lines, as a signal only. If the result is much larger, ask why before anyone reviews it.
- The section "Rules for the writer" below.

If a worker's results often need more than about 5 fixes, change the worker or the brief, not the review.

## Rules for the writer

- Make the smallest change that meets the goal. No options, flags, abstractions or "while here" edits that the goal does not need.
- Search before you write. Reuse the existing function, type or pattern. Never write a second version of something that exists.
- One function does one thing. Aim for less than 50 lines and no more than 3 levels of nesting.
- No dead code: no unused parameters or functions, nothing public without a caller outside its module, no commented-out code, no new allow-dead-code attributes.
- Handle only cases that happen in real use: a user action, or an error the system gives in normal use (access denied, file in use, disk full, path not found, cancel). No code or tests for theoretical limits (a path 4,096 folders deep, a counter overflow, a 2^64-byte file). No checks for states the code cannot reach.
- Errors: pass them on (Rust: `?`). No `unwrap` or `expect` outside tests and proven invariants. No catch-all that hides a failure.
- No new dependency unless the report says why.
- No comments in code, doc comments and test code included. Names and small functions explain the code. One exception: the `// SAFETY:` line on each Rust `unsafe` block. Do not remove old comments in a sweep; delete an old comment only when the change makes it wrong.
- Tests: few, each with a purpose. A bug fix starts with a test that fails now. A feature gets 1 or 2 tests that prove its goal, through its public entry point. Data code also gets one test for each real failure that the brief names. No test for each helper. UI layout and look: no unit tests; check it in the running app.
- Run the check from the brief once. Run only the tests of the changed code, not the full suite.
- Before you report, read your own diff once and remove what the goal does not need.
- Report: files changed, lines added and removed, and the check output.

## Checks

- In the edit loop: format, lint and the focused tests (`.\check.ps1 <test args>` where the project has it).
- A test runs only when the code it covers changes, and in the full suite before a release (`.\check.ps1 -Full`). A test that passed once does not run again at each commit or push.
- Lint rules go in the project's normal lint config (Rust: `[workspace.lints]` in `Cargo.toml`), so every normal run enforces them. Add a lint only when the current code passes it. No baselines or ratchet scripts.
- Duplicate scans (jscpd), unused-dependency scans (cargo-machete) and pedantic lints: once per milestone, as a cleanup task.
- No commit hooks that run tests or reviews.

## Review by consequence (the orchestrator decides)

Ask: can this change reach a call that deletes, moves, overwrites or writes user data? A one-line UI change that sends Delete to the wrong pane counts. File names and line counts do not decide it.

- Cannot reach user data: no model review. The writer reads its own diff. The orchestrator reads `git diff --stat` and looks at anything it did not expect.
- Can reach user data: one reviewer of another model family (Codex high if available, else Sonnet high), on the diff. It traces the path from the user action to the data call, unchanged code included. It reports only bugs, data loss, crashes, hangs and clear duplication that a user can hit in real use. Theoretical edge cases are not findings. The same reviewer checks the fix of each data-loss finding before it closes.
- No second reviewer, no cross-check, no review files or stamps. Measure timing only when a hot path changes.

Commit one feature at a time, in small steps, with Steve's OK.
