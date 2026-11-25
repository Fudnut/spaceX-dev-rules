# SpaceX Dev Rules

A small kit that makes AI coding agents (Claude Code, Codex, Gemini, DeepSeek) trustworthy across all of Steve's projects.

It applies the ideas from Lauren Tan's talk [All Code Is Slop (Except Mine)](https://ai.engineer/talks/O_zcc6Xl12g-all-code-is-slop-except-mine): put trust in code and checks, not in written rules.

## Core ideas

- **Every correction becomes a check.** When you correct an agent, add a lint rule, a test or an API change. Do not add another line to CLAUDE.md.
- **Code is memory.** Agents copy what is in the repo. Block new copies of a bad pattern with a rule, then clean up the old ones.
- **Spend effort top-down** (the "trust pyramid"): codebase design > static checks > runtime verification > prose rules > human review.
- **Verify by evidence.** A feature map says how a user reaches each feature and which command proves it works.
- **Fix the inner loop before you automate it.**

## Contents

| Path | What it is | Status |
|---|---|---|
| `usage/` | Usage-limit tracker for Codex, Claude accounts and Gemini, with fallback rules. See [usage/README.md](usage/README.md). | Done |
| `source/` | Claude's and Codex's analyses of the talk. The transcript and slides stay local (not published). | Done |
| `templates/check.ps1` | One command that runs a project's lint, types and tests. | Planned |
| `templates/FEATURES.md` | Feature map: feature, user path, check command, expected result. | Planned |
| Instruction block | Short shared text for each project's AGENTS.md and CLAUDE.md: "a correction becomes a check". | Planned |

## Agents and roles

| Agent | Role |
|---|---|
| Claude (4 Pro accounts) | Design, turning corrections into checks, review. |
| Cheap Agent (DeepSeek Flash) | Code changes. |
| Gemini Neon / Carbon | Implementation steps; verifier when Codex is at its limit. |
| Gemini Hydrogen | Mechanical scans and summaries. |
| Codex (GPT-6.2-Astra, Plus) | Verifier: runs checks and the feature map, reports findings without fixing them. |

Check usage before you call Codex or Gemini: run `usage\usage.ps1` (see [usage/README.md](usage/README.md)).

## Setup on a computer

1. Set the shared usage ledger path (once per computer, then open a new terminal):
   - Desktop PC: `[Environment]::SetEnvironmentVariable('AI_USAGE_LEDGER', 'Z:\AI-Development\SpaceX_Dev_Rules\usage\ledger.json', 'User')`
   - Laptop: `[Environment]::SetEnvironmentVariable('AI_USAGE_LEDGER', 'C:\AI-Development\SpaceX_Dev_Rules\usage\ledger.json', 'User')`
2. Get the kit: clone this repo. On the laptop, the folder already holds the ledger, so use `git init`, `git remote add origin https://github.com/Fudnut/spaceX-dev-rules.git` and `git pull origin master` instead.

## Next steps

- Pilot `check.ps1` and `FEATURES.md` on one project.
- Settle the fallback order for quota errors (the workers plugin falls back to Sonnet; this kit prefers Gemini first).
- Move a rule into this kit only after it has worked in a second project.

## Progress log

Newest first.

- **2026-11-25** Read the talk with Codex; wrote both analyses. Added the usage-limit tracker and shared ledger.
