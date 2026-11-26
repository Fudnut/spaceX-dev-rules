# Code review method (Claude + Codex)

Status: in use. Piloted on File_manager, 2026-11-25 to 26: crate `fm-sfx` (merged to `main`), then `fm-model` chunks model-01 to model-06 on `review/fm-model`.

Goal: find logic errors, dead code, duplication and code that can be simpler. Make the code smaller and easier to maintain. Keep behavior the same, unless a change fixes a bug.

## Roles

| Who | Model | Does |
|---|---|---|
| Claude | Opus 5.5, effort high | Makes chunks, reviews, cross-checks, reviews diffs, writes `STATE.md`. |
| Codex | `gpt-6.2-astra`, effort high | Reviews, cross-checks, reviews diffs. Never edits files. |
| Neon (Claude's sub-agent) | agent `workers:antigravity`, model `gemini-4-neon-high` | Writes the tests and makes the approved changes. If it fails, a Sonnet sub-agent takes the step (`workers:use` rule 4). |
| Codex's sub-agent | `gpt-6.2-sol`, effort high | Optional, Codex decides. |
| Steve | | Approves findings and commits. Says when to resume. |

Each side runs one sub-agent at a time. The Codex runs that Claude starts are not Claude's sub-agent. Codex's config defaults to `gpt-6.2-sol`, effort medium, so every run sets the model and effort.

## Files

All in the target repo, in `docs/review/`. Each agent writes only its own files.

- `STATE.md`: Claude's checkpoint (template below). Only Claude writes it.
- `<crate>-tools.txt`: tool output for one crate.
- `<chunk>.claude.md`: Claude's findings, then Claude's verdicts on Codex's findings.
- `<chunk>.codex-review.md`, `<chunk>.codex-check.md`, `<chunk>.codex-diff.md`: the last message of each Codex run (`-o`). Each ends with a `## Checkpoint` section. Codex's newest output file is its checkpoint.

## Chunks

- A chunk is a module, or a group of functions in a big file, of at most about 1,500 lines. ID: `<crate>-NN`, for example `sfx-01`.
- Crate order, dependencies first: fm-model, fm-test-support, fm-sfx, fm-windows, fm-app.
- The first pass skips test code: `tests/`, `#[cfg(test)]` modules and `ui/tests.rs`.
- Rank the chunks in a crate by the tool output, worst first.
- Stop a crate when two chunks in a row give no confirmed findings. Mark the rest "not reviewed" in `STATE.md`.

## Tools (once per crate, before the chunks)

Tools are free and exact. The models judge only what tools cannot: logic errors and "can this be simpler".

- `cargo clippy -p <crate> --all-targets -- -W clippy::pedantic -W clippy::cognitive_complexity -W clippy::too_many_lines` (to rank chunks, not a list of fixes)
- `cargo machete` (unused dependencies; once for the workspace)
- `jscpd crates/<crate>/src --format rust --min-lines 10 --reporters console` (duplicates; once more over all of `crates/` for duplicates across crates)
- `cargo llvm-cov -p <crate> --summary-only` (code with no test needs a test before a change)

## Steps for each chunk

1. **Budget check (Claude).** Get Codex's numbers from `usage\usage.ps1` and Claude's from the app usage tool. Start the chunk only if used % + the cost of one chunk is 95% or less, for both agents, for the 5-hour and the weekly limit. Until the pilot measures the cost of a chunk, use 10%. Ignore the FALLBACK label in `usage.ps1`; read the numbers.
2. **Blind review, in parallel.** Claude starts the Codex "review" run in the background, then writes `<chunk>.claude.md`. Neither reads the other's findings until both are done.
3. **Cross-check.** The Codex "check" run gives verdicts on Claude's findings. Claude adds verdicts on Codex's findings to `<chunk>.claude.md`. Verdicts: CONFIRMED, REJECTED (reason, `file:line`) or DISPUTED (both arguments). Only findings that both agents confirm go to Steve, plus disputed findings, marked as such.
4. **Approval.** Steve approves by ID ("approve sfx-01-C2, sfx-01-X1"). Claude records it in `STATE.md`.
5. **Tests first.** A bug fix starts with a test that fails now. A change to untested code starts with a test that locks in the current behavior. Both tests pass after the change.
6. **Edit.** Claude gives Neon one task for the chunk: the approved findings, the tests, the files, and "change nothing else". Work on branch `review/<crate>`. Check `git status` first and leave unrelated files as they are.
7. **Verify.** Claude runs `.\check.ps1 <focused test args>` and reviews `git diff`. The Codex "diff" run reviews the diff. For a change on a hot path (copy, directory listing, redraw), compare a timing before and after. Run the full `.\check.ps1` at the end of each crate. If a check fails, Neon gets one fix attempt; after a second failure, stop and report to Steve.
8. **Commit** after Steve's OK, one commit per chunk.
9. **Update `STATE.md`.**

## Finding format

| ID | file:line | Type | Now | Proposed | Why better | Behavior change | Perf risk | Test | Claude | Codex |
|---|---|---|---|---|---|---|---|---|---|---|

- ID: `<chunk>-C<n>` from Claude, `<chunk>-X<n>` from Codex.
- Type: bug, dead, duplicate, simpler, dependency.
- Behavior change: "no", or "yes: fixes <bug>".
- Perf risk: "none", or "hot path: <why>" (needs a timing).
- Test: the test that proves the change, existing or new.

## Bar for a change

Propose a change only if it fixes a bug, or removes code, branches, duplication or a dependency, and keeps public behavior. No renames, formatting or style-only rewrites. When one finding type appears 3 or more times, also propose a clippy lint that blocks it (a correction becomes a check).

## Stop and resume

- **Stop** when Codex or Claude reaches 95% (5-hour or weekly), when the next chunk does not fit (step 1), or when Steve says stop.
- **Checkpoints.** Claude writes `STATE.md`. Every Codex run ends with a checkpoint, so Codex's checkpoint is always current, also when its limit stops it. If a Codex run ends without its output file, repeat that step.
- **Resume** only on Steve's OK. Claude reads `STATE.md`, does step 1, then starts the next Codex run with Codex's newest output file. Each Codex run is new and starts from the files; no Codex process waits between runs.
- **Sessions.** Start a fresh Claude session for each crate, or after 3 to 5 chunks: "Continue the File_manager review. Read `F:\AI_Projects_4\SpaceX_Dev_Rules\review\METHOD.md` and `docs/review/STATE.md`."

## Starting a Codex run

Claude fills in `codex-brief.md` (step, chunk, files, newest Codex output) in its scratchpad, then runs:

```powershell
Get-Content <filled brief> -Raw | codex exec -m gpt-6.2-astra -c model_reasoning_effort=high -s read-only -C F:\AI_Projects_3\File_manager -o docs\review\<chunk>.codex-<step>.md -
```

Run Codex and all builds on Windows. Use Codex in WSL (Ubuntu-24.04) only if the read-only sandbox fails on Windows. Before you do, make `usage.ps1` also read the WSL Codex logs (`\\wsl.localhost\Ubuntu-24.04\home\steve\.codex\sessions`); it reads only the Windows logs now, so the budget check would show old numbers.

## STATE.md template

```markdown
# Review state (Claude's checkpoint)

Updated: <date time>. Branch: review/<crate>.
Usage: Codex 5h <n>% / week <n>% (resets <time>). Claude 5h <n>% / week <n>% (resets <time>).
Measured cost of one chunk: Codex <n>%, Claude <n>%.

## Now
Chunk <id>, step <n>. Next action: <one line>.
Codex's newest output: docs/review/<file>.

## Chunks
| ID | Files and lines | Status | Approved | Committed |
|---|---|---|---|---|

## Open questions for Steve
```
