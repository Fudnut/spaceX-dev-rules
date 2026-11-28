# Commit gate: how to use it

Retired 2026-11-28 (too slow). Do not install or follow it. Use [../rules/coding.md](../rules/coding.md).

The gate checks every commit in a Rust project before it lands: tool checks (fmt, clippy, machete, dependencies, jscpd), tests, and model reviews of the diff. Design: [DESIGN.md](DESIGN.md). Step-by-step flow for agents: [REVIEW.md](REVIEW.md).

## Hook or plugin?

Neither is needed. The gate lives in the project's repo, so it works for every account and every agent:

| Part | Where | What it does |
|---|---|---|
| Git hooks (`.githooks/`, run `.spacex/gate.ps1`) | The repo | Git refuses a commit or push that fails the checks. This works for any account, any agent, and a human too. |
| `CLAUDE.md` and `AGENTS.md` lines | The repo | Claude Code reads `CLAUDE.md`, and Codex reads `AGENTS.md`, at the start of every session. The line tells them to follow `.spacex/REVIEW.md`. |

Do not use a Claude Code plugin or a user-level hook for this. Those are installed for each account, and the next account or agent would not have them.

## Use it in a project that has it (for example File_manager)

1. Open the project folder in a new session (Claude Code or Codex, any account).
2. Ask for the change as normal. The session reads `CLAUDE.md` and follows `.spacex/REVIEW.md`: it writes the change, runs `gate.ps1 check`, gets the reviews, stamps and commits. It asks for your OK before the commit and before the push.

You do not need to say "use the gate". You do not need to start a task or a hook.

Only a Claude session stamps and commits. A Codex session may write or review a change, but it does not commit through the gate.

### One-time setup for each clone

Git does not copy `core.hooksPath` when you clone, so the hooks are off in a fresh clone. Run this once in the new clone:

```
git config core.hooksPath .githooks
```

`gate.ps1 check` and `gate.ps1 stamp` refuse to run until this is set. The setting is in the clone's `.git/config`, so a new account that uses the same folder on the same computer does not need it again.

If a different Windows user opens the same folder and git reports "dubious ownership", that user runs `git config --global --add safe.directory <folder>` once.

### Tools needed on the computer

PowerShell (5.1 or 7), git, the Rust toolchain, `cargo-machete` (`cargo install cargo-machete`), and `jscpd` (`npm install -g jscpd`). A missing tool fails the gate. It does not skip the check.

## Add the gate to a new Rust project

1. Clone this kit anywhere on the computer.
2. From the kit, run:
   ```
   powershell -NoProfile -File gate/install.ps1 -Target <project folder>
   ```
   This copies the gate into `<project>/.spacex/`, adds `.githooks/`, sets `core.hooksPath`, and writes the first baseline (today's counts, so old debt does not block).
3. Edit `<project>/.spacex/config.json`: set the `risky` globs (delete, copy, move, concurrency, format writes), `hotPaths`, `testCommand` and `jscpdPaths`. See "Config keys" in [REVIEW.md](REVIEW.md).
4. Add this line to the project's `CLAUDE.md` and `AGENTS.md`:
   ```
   If the repo has `.spacex/`, every commit goes through the commit gate: follow `.spacex/REVIEW.md`. Never use `--no-verify`. Only a Claude session stamps and commits through the gate.
   ```
5. Commit the install. The gate checks this first commit too.

## Update a project to a newer kit

From the kit, run `powershell -NoProfile -File gate/install.ps1 -Target <project folder> -Update`. This replaces `gate.ps1`, `REVIEW.md`, `VERSION` and the hooks. It does not change `config.json` or `baseline.json`. Then commit the change through the gate.

## Rules

- Never use `--no-verify`. Only Steve may, in an emergency.
- Never run `gate.ps1 baseline`. Only Steve runs it.
- Push the review notes in a separate push: `git push origin refs/notes/review`.
- When a hook fails, see "When a hook fails" in [REVIEW.md](REVIEW.md).
