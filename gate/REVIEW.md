# Commit gate: review steps for one change

Retired 2026-11-28 (too slow). Do not install or follow it. Use [../rules/coding.md](../rules/coding.md).

Applies to every commit in a project that has `.spacex/`. This is the per-change version of the kit's `review/METHOD.md`.

## Rule

- Never use `--no-verify`. Only Steve may, in an emergency.
- Never run `gate.ps1 baseline`. Only Steve runs it.
- Run `git config core.hooksPath .githooks` once per clone (`check` and `stamp` refuse without it). Active hooks: `pre-commit`, `pre-merge-commit`, `commit-msg`, `post-commit`, and `pre-push`.

## Flow

1. **Write.** Make the change. For a bug fix, write a test that fails now. Then make it pass.
2. **Stage.** Run `git add` for the files of this change. Stage everything: the hooks refuse unstaged or untracked files.
3. **Check.** Run `powershell -NoProfile -File .spacex/gate.ps1 check <test args>`. It runs the tool gates and focused tests, and reads size and tier from the index. A `Large` or dependency exception only prints a note here; `pre-commit` enforces it after the stamp. Fix every failure.
4. **Review blind.** Reviewer A and reviewer B (see Roles) each get `git diff --cached` plus every touched function in full. They do not see each other's findings. They write findings in the format below.
5. **Cross-check.** Each reviewer gives a verdict on the other's findings. The writer fixes the findings that both confirm, inside this change. Then go to step 2. Only the reviewer who raised a finding checks its fix. Disputed findings go to Steve.
6. **Final review.** The orchestrator (the main Claude session, not a subagent) reads the whole staged diff once more (`git diff --cached`). It checks that the diff holds only the change and the confirmed fixes, that no fix broke something else, and that there are no unrelated edits or swallowed errors. It writes `Final: claude/<model> OK` in the review file, or lists the problems there and goes back to step 2.
7. **Stamp.** Write the review file. Keep it outside the repo, or in a gitignored folder. Run `powershell -NoProfile -File .spacex/gate.ps1 stamp <review file>`. `stamp` refuses a review file without a `Final: claude/<model> OK` line. When `Dependency-reason:` is present and the dependency count went up, `stamp` raises the count in `.spacex/baseline.json` and stages it before taking the tree. Any later change to the staged files makes the stamp invalid: stamp again.
8. **Commit** after Steve's OK. The hooks (`pre-commit`, `pre-merge-commit`, `commit-msg`, `post-commit`) run the checks again, add the trailers and store the review as a git note.

## Diff size

Counted lines: added lines in staged `.rs` files that are not blank, not comments (`//`, `///`, `//!`), and not test code. Test code is any file under `tests/`, any `*tests.rs` file, and lines after the first `#[cfg(test)]` that is followed by an inline `mod <name> {` line. A `#[cfg(test)]` on an import or function does not stop counting. `#[cfg(test)] mod tests;` does not stop counting. Deleted lines are reviewed but not counted.

Over 400 counted lines:
- Split first into a series of green, stamped commits on one branch (example: add the new function and its tests; move the callers; delete the old code).
- Only if it cannot be split: add `Large: <reason>` and `Large-approved: Steve` (an agent adds `Large-approved: Steve` only after Steve says so in chat). Review in parts of at most 400 counted lines with A and B on each part; the `Final:` review covers the whole diff.

## Tiers

`gate.ps1` sets the tier from the staged paths and lines. The stamp check enforces it.

| Tier | When | Reviewers | Extra |
|---|---|---|---|
| Light | At most 20 counted lines outside risky paths (docs-only and test-only changes count 0) | B only | none |
| Normal | Everything else | A and B, blind, cross-check | none |
| Risky | Touches a path in `config.json` `risky` | A and B, B on the strongest model | `Test-first:` required; timing before and after on hot paths |

## Roles and models

Reviewers must be independent: neither reviewer may be the writer's model family, and A and B must be different families. When a default breaks that rule, take the next model in the list.

Only a Claude session may be orchestrator (final review, stamp, commit). Codex sessions may review or prepare changes, but do not stamp or commit.

| Role | Default | Next choices |
|---|---|---|
| Orchestrator (runs the flow, final review of the staged diff, writes the stamp) | the Claude session | none (Codex sessions do not stamp or commit) |
| Writer | Neon high | Neon xhigh (risky tier, or after one failed attempt); Sonnet high; DeepSeek Flash max (easy, mechanical, when Steve picks it) |
| Reviewer A | Codex `gpt-6.2-astra` high | DeepSeek Flash max; Neon xhigh (when the writer is Claude-family, or any non-Neon writer) |
| Reviewer B | Sonnet high (light: Sonnet medium) | Opus high (risky tier); Codex `gpt-6.2-astra` high (when the writer is Claude-family, including Risky) |
| Mechanical subagent | Hydrogen high | Hydrogen xhigh (large outputs); Haiku |

When the writer is Claude-family (for example Sonnet): reviewer A = Neon xhigh, reviewer B = Codex `gpt-6.2-astra` high. In Risky, Codex high as B is accepted instead of Opus.

Before a Codex run, run the kit's `usage/usage.ps1`. If one review would take Codex over 95%, use the next reviewer A choice.

## Review file format

Header lines, then the findings table. `gate.ps1 stamp` reads these lines.

```
Writer: gemini/neon-high
Reviewer-A: codex/gpt-6.2-astra
Reviewer-B: claude/sonnet-high
Test-first: tests/copy.rs::copy_keeps_mtime fails before the fix
Timing: copy 1 GB: 4.1 s before, 4.0 s after
Dependency-reason: adds crate x because ...
# only for a Large change:
Large: <reason>
Large-approved: Steve
Final: claude/opus-5.5 OK

## Findings

| ID | file:line | Type | Now | Proposed | Why better | Behavior change | Perf risk | Test | A | B | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | src/copy.rs:42 | bug | ... | ... | ... | yes: fixes <bug> | none | copy_keeps_mtime | CONFIRMED | CONFIRMED | FIXED |
```

- The family is the text before the first `/`.
- `Test-first:` is required in the Risky tier, and `Reviewer-B:` must name Opus (for example `claude/opus-high`), or Codex when the writer is Claude-family. `Timing:` is required when a staged path matches `hotPaths`. `Dependency-reason:` is required when the dependency count goes up; `stamp` raises the staged baseline and stages `.spacex/baseline.json`.
- `Large:` and `Large-approved: Steve` are only for a Large change (over 400 counted lines that cannot be split). An agent adds `Large-approved: Steve` only after Steve says so in chat.
- `Final:` is required in every tier: `claude/<model>`, then `OK` (only the Claude orchestrator writes it).
- IDs: `A1`, `A2` for reviewer A; `B1`, `B2` for reviewer B.
- Type: bug, dead, duplicate, simpler, dependency.
- Behavior change: "no", or "yes: fixes <bug>". Perf risk: "none", or "hot path: <why>" (needs a timing).
- Status: `FIXED`, `REJECTED (reason)` or `ACCEPTED (Steve)`. No other value passes. In Normal and Risky tiers, `FIXED` needs `CONFIRMED` in both `A` and `B` columns. A malformed row fails.
- Every table row in the review file must be the header, the separator, or a finding with ID `A<n>`/`B<n>` and 12 cells. Escape a literal pipe in a cell as `\|`.

## Bar for a change

Propose a change only if it fixes a bug, or removes code, branches, duplication or a dependency, and keeps public behavior. No renames, formatting or style-only rewrites. This applies to every finding on the diff. When one finding type appears 3 or more times, also propose a clippy lint that blocks it (a correction becomes a check).

## Baseline and pre-push

- `check` and `pre-commit` read the staged `.spacex/baseline.json`; `pre-push` reads `HEAD:.spacex/baseline.json`.
- `pre-push` checks only the checked-out `HEAD` (check out a branch and push it alone). It skips ref lines that push `refs/notes/*` to `refs/notes/*`; a push of only notes refs (for example `git push origin refs/notes/review`) runs no tests. Deleting a notes ref runs the full checks.
- `pre-push` checks "not higher" (clippy per lint, machete, dependency count, jscpd) on every OS and fails on any increase. It lowers counts and writes `.spacex/baseline.json` only on the OS recorded in `baseline.json` (`os`) when at least one count goes down. A baseline without `os` lowers nothing.

## Config keys (`.spacex/config.json`)

| Key | Meaning |
|---|---|
| `risky` | Globs of paths that set the Risky tier (delete, copy, move, concurrency, format writes). |
| `hotPaths` | Globs of paths that need a `Timing:` line. |
| `maxDiffLines` | Most counted lines per commit (see Diff size). |
| `lightMaxLines` | Most counted lines outside risky paths for the Light tier. |
| `testCommand` | Program and arguments for the full test run in `pre-push`. |
| `jscpdPaths` | Folders that jscpd scans for duplicates. |

Globs are PowerShell `-like` patterns on repo-relative paths with `/`. `*` also matches across folders.

## When a hook fails

| Message | Meaning and action |
|---|---|
| `core.hooksPath is not .githooks` | Run `git config core.hooksPath .githooks` once per clone. |
| `N counted lines (max M)` | The change is too big. Split it into stamped commits; only if it cannot be split, ask Steve for a `Large:` exception and stamp again. |
| `cargo fmt --check failed` | Run `cargo fmt --all`, stage, stamp again. |
| `clippy::<lint> N > M` | The change adds warnings of that lint. Fix them. Do not raise the baseline. |
| `cargo clippy reports ... error(s)` | A default lint or a compile error. Fix it. |
| `unused dependencies (machete)` | Remove the unused dependency. |
| `dependency count` | Remove the new dependency, or add `Dependency-reason:` to the review and stamp again. |
| `stage or stash unstaged or untracked changes` | The checks must see the staged content. Stage or stash all unstaged and untracked files. |
| `no review stamp for staged tree` | You changed the staged files after the stamp, or never stamped. Review, then stamp. |
| `pre-push checks only the checked-out HEAD` | Check out the branch you want to push and push it alone. Push review notes in their own push: `git push origin refs/notes/review`. |
| `duplicate count (jscpd)` | The push adds duplicates. Remove them. |
| `tests failed` | Fix the tests before the push. |
| `... not found` | A tool is missing (cargo-machete, jscpd). Tell Steve. A missing tool is a failure. |
