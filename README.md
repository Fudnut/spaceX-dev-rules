# SpaceX Dev Rules

A small kit that makes AI coding agents (Claude Code, Codex, Gemini, DeepSeek) trustworthy across all of Steve's projects.

It applies the ideas from Lauren Tan's talk [All Code Is Slop (Except Mine)](https://ai.engineer/talks/O_zcc6Xl12g-all-code-is-slop-except-mine): put trust in code and checks, not in written rules.

## Core ideas

- **Quality at the source.** A good brief and short coding rules ([rules/coding.md](rules/coding.md)) give lean code at the first attempt. Only changes that can reach user data get a model review.
- **Every correction becomes a check.** When you correct an agent, add a lint rule, a test or an API change. Do not add another line to CLAUDE.md.
- **Code is memory.** Agents copy what is in the repo. Block new copies of a bad pattern with a rule, then clean up the old ones.
- **Spend effort top-down** (the "trust pyramid"): codebase design > static checks > runtime verification > prose rules > human review.
- **Verify by evidence.** A feature map says how a user reaches each feature and which command proves it works.
- **Fix the inner loop before you automate it.**

## Contents

| Path | What it is | Status |
|---|---|---|
| `rules/coding.md` | Briefs, coding rules, checks and review by consequence. Each computer's `~/.claude/CLAUDE.md` imports it. | In use (2026-11-28) |
| `usage/` | Usage-limit tracker for Codex, Claude accounts and Gemini, with fallback rules. See [usage/README.md](usage/README.md). | Done |
| `source/` | Claude's and Codex's analyses of the talk. The transcript and slides stay local (not published). | Done |
| `templates/check.ps1` | One command that runs a project's format and lint, then the given tests (focused run), or the whole suite with `-Full`; stops at the first failure. | Piloted (File_manager) |
| `templates/FEATURES.md` | Feature map: feature, user path, check command, expected result. | Piloted (File_manager) |
| `templates/instruction-block.md` | Short shared text for each project's AGENTS.md and CLAUDE.md: "a correction becomes a check". | Piloted (File_manager) |
| `review/` | Code review method for Claude and Codex: blind review, cross-check, approval, one writer, stop at 95%. See [review/METHOD.md](review/METHOD.md). | Occasional cleanup of old code, not for each commit |
| `gate/` | Commit gate for Rust projects: tool ratchet and two blind model reviews, enforced by git hooks. | Retired 2026-11-28: too slow (5 commits took over 5 hours). Do not install. |

## Agents and roles

| Agent | Role |
|---|---|
| Claude (4 Pro accounts) | Design, turning corrections into checks, review. |
| Gemini Neon (high) | Default worker for code changes. Verifier when Codex is at its limit. |
| Gemini Carbon | Code changes when Steve picks it. Verifier when Codex and Neon are at their limits. |
| Gemini Hydrogen | Mechanical scans and summaries. |
| Cheap Agent (DeepSeek Flash) | Code changes only when Steve picks it. |
| Codex (GPT-6.2-Astra, Plus) | Verifier: runs checks and the feature map, reports findings without fixing them. |

**Code changes (from 2026-11-26):** send them through `/workers:use`, not straight to Cheap Agent. The default worker is Neon (`gemini-4-neon-high`). Before the first code change in a session, Claude asks once: Neon (default), Hydrogen, Carbon, or DeepSeek through Cheap Agent. The answer is the session worker until the session ends. The rule is in `~/.claude/CLAUDE.md`, so every new session gets it.

Check usage before you call Codex or Gemini: run `usage\usage.ps1` (see [usage/README.md](usage/README.md)).

## Setup on a computer

1. Set the shared usage ledger path (once per computer, then open a new terminal):
   - Desktop PC: `[Environment]::SetEnvironmentVariable('AI_USAGE_LEDGER', 'Z:\AI-Development\SpaceX_Dev_Rules\usage\ledger.json', 'User')`
   - Laptop: `[Environment]::SetEnvironmentVariable('AI_USAGE_LEDGER', 'C:\AI-Development\SpaceX_Dev_Rules\usage\ledger.json', 'User')`
2. Get the kit: clone this repo. On the laptop, the folder already holds the ledger, so use `git init`, `git remote add origin https://github.com/Fudnut/spaceX-dev-rules.git` and `git pull origin master` instead.
3. Add these two lines to `~/.claude/CLAUDE.md`, with this computer's kit path (desktop: `F:/AI_Projects_4/SpaceX_Dev_Rules`, laptop: `C:/AI-Development/SpaceX_Dev_Rules`), not in backticks, so Claude Code imports the file:
   ```
   ## Writing code
   @<kit path>/rules/coding.md
   ```

## Next steps

- Use the templates in a second project, then mark them Done.
- Settle the fallback order for quota errors (the workers plugin falls back to Sonnet; this kit prefers Gemini first).
- Move a rule into this kit only after it has worked in a second project.

## Progress log

Newest first.

- **2026-11-28** Retired the commit gate. On File_manager, 5 UI commits took over 5 hours: each one got two blind reviews, a cross-check, fix re-checks, a final review, a stamp and the same tool runs two or three times, with 16 to 37 findings per commit. New approach in `rules/coding.md`: a brief that names the code to reuse and the real failure cases, short writer rules (smallest change, reuse, no dead code, no comments, real-use cases only, few tests), focused checks, and one review only for changes that can reach user data. Codex `gpt-6.2-astra` high reviewed the draft ("adopt with changes"); its changes are in. Applied to File_manager: removed `.spacex/` and `.githooks/`; `check.ps1` runs no tests without arguments and the whole suite plus the slow wipe tests with `-Full`; AGENTS.md is one role table plus the project safety rules (40 lines, was 50 dense ones), and CLAUDE.md imports it instead of repeating it. Both computers' `~/.claude/CLAUDE.md` import `rules/coding.md`.

- **2026-11-26** Added the draft review method for Claude and Codex (`review/`), to pilot on File_manager `fm-sfx`. Made Neon (high) the default worker for code changes through `/workers:use`; each session asks before its first code change. Installed the review tools; cargo-machete is pinned to 0.9.1 because 0.10.1 does not compile on rustc 1.97.1.

- **2026-11-25** Piloted the kit on File_manager (Rust): `check.ps1` (fmt, clippy, Linux check, tests; focused-run arguments), `FEATURES.md` with one workflow (F5 copy to the other pane, checked by `cargo test -p fm-app --test feature_copy` on the real file system), and the instruction block in AGENTS.md and CLAUDE.md. The first full run found flaky sound tests (a timing wait and a poisoned test lock); fixed. Generic copies are in `templates/`.
- **2026-11-25** Read the talk with Codex; wrote both analyses. Added the usage-limit tracker and shared ledger.
