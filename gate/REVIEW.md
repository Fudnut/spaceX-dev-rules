# Commit gate: review steps for one change

Applies to every commit in a project that has `.spacex/`. This is the per-change version of the kit's `review/METHOD.md`.

## Rule

- Never use `--no-verify`. Only Steve may, in an emergency.
- Never run `gate.ps1 baseline`. Only Steve runs it.

## Flow

1. **Write.** Make the change. For a bug fix, write a test that fails now. Then make it pass.
2. **Check.** Run `powershell -NoProfile -File .spacex/gate.ps1 check <test args>`. It runs the tool gates and the focused tests. Fix every failure.
3. **Stage.** Run `git add` for the files of this change. Stage everything: the hooks do not accept unstaged changes.
4. **Review blind.** Reviewer A and reviewer B (see Roles) each get `git diff --cached` plus every touched function in full. They do not see each other's findings. They write findings in the format below.
5. **Cross-check.** Each reviewer gives a verdict on the other's findings. The writer fixes the findings that both confirm, inside this change. Then go to step 2. Only the reviewer who raised a finding checks its fix. Disputed findings go to Steve.
6. **Final review.** The orchestrator (the main Claude session, not a subagent) reads the whole staged diff once more (`git diff --cached`). It checks that the diff holds only the change and the confirmed fixes, that no fix broke something else, and that there are no unrelated edits or swallowed errors. It writes `Final: <model> OK` in the review file, or lists the problems there and goes back to step 2.
7. **Stamp.** Write the review file. Keep it outside the repo, or in a gitignored folder. Run `powershell -NoProfile -File .spacex/gate.ps1 stamp <review file>`. `stamp` refuses a review file without a `Final: <model> OK` line. Any later change to the staged files makes the stamp invalid: stamp again.
8. **Commit** after Steve's OK. The hooks run the checks again, add the trailers and store the review as a git note.

## Diff size

Counted lines: added lines in staged `.rs` files that are not blank, not comments (`//`, `///`, `//!`), and not test code. Test code is any file under `tests/`, any `*tests.rs` file, and every line after the first `#[cfg(test)]`. Deleted lines are reviewed but not counted.

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

| Role | Default | Next choices |
|---|---|---|
| Orchestrator (runs the flow, final review of the staged diff, writes the stamp) | the Claude session | none |
| Writer | Neon high | Neon xhigh (risky tier, or after one failed attempt); Sonnet high; DeepSeek Flash max (easy, mechanical, when Steve picks it) |
| Reviewer A | Codex `gpt-6.2-astra` high | DeepSeek Flash max; Neon xhigh (only if the writer is not Neon) |
| Reviewer B | Sonnet high (light: Sonnet medium) | Opus high (risky tier) |
| Mechanical subagent | Hydrogen high | Hydrogen xhigh (large outputs); Haiku |

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
- `Test-first:` is required in the Risky tier, and `Reviewer-B:` must name Opus (for example `claude/opus-high`). `Timing:` is required when a staged path matches `hotPaths`. `Dependency-reason:` is required when the dependency count goes up.
- `Large:` and `Large-approved: Steve` are only for a Large change (over 400 counted lines that cannot be split). An agent adds `Large-approved: Steve` only after Steve says so in chat.
- `Final:` is required in every tier: the model name, then `OK`.
- IDs: `A1`, `A2` for reviewer A; `B1`, `B2` for reviewer B.
- Type: bug, dead, duplicate, simpler, dependency.
- Behavior change: "no", or "yes: fixes <bug>". Perf risk: "none", or "hot path: <why>" (needs a timing).
- Status: `FIXED`, `REJECTED (reason)` or `ACCEPTED (Steve)`. No other value passes.

## Bar for a change

Propose a change only if it fixes a bug, or removes code, branches, duplication or a dependency, and keeps public behavior. No renames, formatting or style-only rewrites. This applies to every finding on the diff. When one finding type appears 3 or more times, also propose a clippy lint that blocks it (a correction becomes a check).

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
| `N counted lines (max M)` | The change is too big. Split it into stamped commits; only if it cannot be split, ask Steve for a `Large:` exception and stamp again. |
| `cargo fmt --check failed` | Run `cargo fmt --all`, stage, stamp again. |
| `clippy::<lint> N > M` | The change adds warnings of that lint. Fix them. Do not raise the baseline. |
| `cargo clippy reports ... error(s)` | A default lint or a compile error. Fix it. |
| `unused dependencies (machete)` | Remove the unused dependency. |
| `dependency count` | Remove the new dependency, or add `Dependency-reason:` to the review and stamp again. |
| `stage or stash unstaged changes` | The checks must see the staged content. Stage the change or stash it. |
| `no review stamp for staged tree` | You changed the staged files after the stamp, or never stamped. Review, then stamp. |
| `duplicate count (jscpd)` | The push adds duplicates. Remove them. |
| `tests failed` | Fix the tests before the push. |
| `... not found` | A tool is missing (cargo-machete, jscpd). Tell Steve. A missing tool is a failure. |
