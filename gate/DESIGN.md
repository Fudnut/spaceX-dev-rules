# Commit gate: design (approved by Steve, 2026-11-27)

Goal: every commit in a Rust project is checked and reviewed before it lands, so no codebase ever needs a full after-the-fact review again. Checks: logic, bloat, function simplicity, duplication, dead code, unused dependencies, speed. First project: File_manager (bug fixes from release testing).

Decisions (Steve, 2026-11-27): Rust only for now. Hard block. Codex is reviewer A; if Codex is not available, another model takes its place. Pilot: File_manager.

## Principles

1. Review the diff, not the codebase. Cost grows with the change, not with the 292k lines.
2. Tools first. A tool check is free and exact. Models judge only what tools cannot: logic and "can this be simpler".
3. Ratchet. Old debt does not block a commit. A count may go down, never up.
4. Git enforces it. A pre-commit hook refuses any commit without passing checks and a review stamp for the exact staged content.
5. Runs anywhere. No fixed paths, accounts or machine names in committed files. Machine settings come from environment variables or a gitignored local file.
6. Guards fail closed (Steve, 2026-11-27). A guard tool (gate, hook, CI script) blocks the commit when any command it runs fails or gives output it cannot read. Before a guard tool goes into a project, or after a change to it, it gets one review from a model family that did not write it and one test for each way it can fail. The kit itself is not Rust, so its own gate does not do this: do it by hand.

## Files

In this kit, `gate/`:

| File | Purpose |
|---|---|
| `install.ps1` | Copies the gate into a project as `.spacex/`, sets `git config core.hooksPath .githooks`, writes the first baseline. `-Update` replaces kit files, keeps config and baseline. |
| `gate.ps1` | One script, subcommands: `check`, `stamp`, `pre-commit`, `commit-msg`, `post-commit`, `pre-push`, `baseline`. |
| `hooks/*` | 2-line shims (one per hook name) that run `gate.ps1 <hook>`. |
| `REVIEW.md` | The per-change review steps for agents (the diff version of `review/METHOD.md`). |
| `config.example.json` | Project settings: risky paths, diff limit, test command, test scope, hot-path benches. |
| `test-affected.ps1` | Kit test for `testScope` `affected` (crate mapping and fallbacks). Stays in the kit; `install.ps1` does not copy it. |

In the project: `.spacex/` (kit copy + `VERSION`), `.spacex/config.json`, `.spacex/baseline.json` (committed), `.githooks/`, and a short block in AGENTS.md and CLAUDE.md that points to `.spacex/REVIEW.md`. Instructions live in the repo, so Claude and Codex find them on any account.

Scripts run on Windows PowerShell 5.1 and PowerShell 7 (Linux, macOS). They find the repo with `git rev-parse --show-toplevel`. Estimated size: 300 to 400 lines in total.

## Flow for one change

1. **Write.** The writer makes the change. A bug fix starts with a test that fails now (the correction becomes a check).
2. **Check.** `gate.ps1 check` runs the tool gates and the focused tests.
3. **Stage, then review blind.** Reviewers A and B each get the staged diff plus every function it touches, in full. They do not see each other's findings. They use the finding format and "Bar for a change" from `review/METHOD.md`.
4. **Cross-check.** Each reviewer gives verdicts on the other's findings. Findings confirmed by both are fixed by the writer if they are inside the change; then back to step 2, and only the reviewer who raised a finding checks its fix. Disputed findings go to Steve.
5. **Final review, then stamp.** The orchestrator (the main Claude session, not a subagent) reads the whole staged diff once more: does it hold only the change and the confirmed fixes, did a fix break something else, are there unrelated edits or swallowed errors. It records its verdict in the review file as `Final: <model> OK` or lists problems (then back to step 2). `gate.ps1 stamp <review file>` refuses a review file without a `Final:` OK line. It also checks that the review file names the reviewers the tier needs and that every finding is FIXED, REJECTED (reason) or ACCEPTED by Steve. It saves the stamp as `.git/spacex/stamps/<tree id>.json`, where the tree id is `git write-tree` of the staged content. Any later edit changes the tree id, so the stamp no longer matches.
6. **Commit (Steve's OK).** Hooks:
   - `pre-commit`: fmt, clippy ratchet, cargo-machete, diff size limit, stamp matches the staged tree. Target: under a minute with a warm build cache.
   - `commit-msg`: adds trailers, for example `Reviewed-by: codex/gpt-6.2-astra, claude/sonnet`, `Findings: 3 fixed, 1 rejected`, `Net-lines: -12`.
   - `post-commit`: stores the full review as a git note (`refs/notes/review`).
7. **Push.** `pre-push`: full test suite, jscpd ratchet, then the new lower counts become the baseline.

Agents never use `--no-verify`. Steve may, in an emergency.

## Tool gates (Rust)

| Gate | Hook | Rule |
|---|---|---|
| `cargo fmt --check` | pre-commit | must pass |
| clippy, JSON output, with `pedantic`, `cognitive_complexity`, `too_many_lines` as warnings | pre-commit | default lints are errors; the other counts per lint may not go up |
| `cargo machete` | pre-commit | unused dependency count may not go up |
| dependency count (`Cargo.lock` packages) | pre-commit | may not go up without a reason in the review |
| diff size | pre-commit | at most 400 counted lines (see "Diff size") |
| full `cargo test` (the project's `check.ps1`) | pre-push | must pass |
| `jscpd crates --min-lines 10` | pre-push | duplicate count may not go up |

Later, when a project needs them: a criterion benchmark budget for hot paths, a release binary size budget, coverage of changed lines with cargo-llvm-cov.

## Diff size

Counted lines: added lines in staged `.rs` files that are not blank, not comments (`//`, `///`, `//!`) and not test code. Test code is any file under a `tests/` folder, any `*tests.rs` file, and every line after the first `#[cfg(test)]` in a file. Deleted lines are reviewed but not counted, so removing code is never blocked.

Over 400:
- Split first. One feature across several files becomes a series of commits on one branch, each green and each stamped. Example: add the new function and its tests; move the callers; delete the old code.
- If the change cannot be split (for example an API change that breaks the build unless all callers change at once), the review file may carry `Large: <reason>`. The stamp accepts it only if the review file also has `Large-approved: Steve` (Steve said so in chat), the review was done in parts of at most 400 counted lines with reviewers A and B on each part, and the `Final:` review covers the whole diff. Without these lines the commit is refused.

## Tiers

`gate.ps1` sets the tier from the staged paths and line count. The stamp check enforces it.

| Tier | When | Reviewers | Extra |
|---|---|---|---|
| Light | Only docs or tests, or at most 20 lines outside risky paths | B only | none |
| Normal | Everything else | A and B, blind, cross-check | none |
| Risky | Touches a path in `config.json` `risky` (file delete, copy, move, concurrency, format writes) | A and B, B on the strongest model | tests first required; timing before and after on hot paths |

## Roles and models

Reviewers must be independent: neither reviewer may be the writer's model family, and A and B must be different families. When a default breaks that rule, take the next model in the list.

| Role | Default | Next choices |
|---|---|---|
| Orchestrator (runs the flow, final review of the staged diff, writes the stamp) | the Claude session | none |
| Writer | Neon high | Neon xhigh (risky tier, or after one failed attempt); Sonnet high; DeepSeek Flash max (easy, mechanical, when Steve picks it) |
| Reviewer A | Codex `gpt-6.2-astra` high | DeepSeek Flash max; Neon xhigh (only if the writer is not Neon) |
| Reviewer B | Sonnet high (light: Sonnet medium) | Opus high (risky tier) |
| Mechanical subagent (summarize tool output, baseline triage) | Hydrogen high | Hydrogen xhigh (large outputs); Haiku |

Before a Codex run, check its numbers with `usage/usage.ps1`. If one review would take Codex over 95%, use the next reviewer A choice.

## Old code

The baseline at install time records today's counts, so File_manager can use the gate now. The chunk review in `review/METHOD.md` goes on separately on the old code. Its findings are commits too, so they pass the gate.

## Limits

- Tools prove the measurable parts: format, lint counts, complexity, duplication, dependencies. Logic is not proven. Tests and two independent reviews lower the risk.
- The stamp stops an accidental skip, not a deliberate fake review file.
- Clippy on the whole workspace is slow on a cold cache. If pre-commit takes over a minute with a warm cache, limit clippy to the changed crates.

## Pilot decisions (Steve, 2026-11-27)

- File_manager's risky paths: the 31 globs from the build session's scan (file operations, delete, copy, format writes, queue and workers, `elevated_host`, `fm-test-support`). They go in that project's `.spacex/config.json`.
- File_manager's AGENTS.md names Neon as the default code worker; Steve can name another worker per session.
