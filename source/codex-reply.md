## 1. Six ideas worth keeping

- **Make the safe path easy to copy.** If every caller needs the same cleanup sequence, put it behind one API. That saves Steve from reviewing the sequence every time an agent writes a caller.
- **Make boundaries visible and enforceable.** `electron-main/` and `electron-renderer/` tell an agent where code belongs. An import check catches the mistake when the names alone fail.
- **Treat a copied workaround as a design signal.** The slide goes from one timer that fixed a flicker to 183 timers. The moment to investigate was when the workaround entered a shared module.
- **Turn repeatable corrections into executable checks.** A diagnostic that names the offending import and points to the supported API can help even a cheap worker repair its own patch.
- **Give agents a way to exercise the product.** A feature name, a user action and an observable result give Steve and the agent a shared definition of “works.”
- **Judge quality through the user’s experience.** Startup time, typing lag and whether a setting survives restart tell Steve more about a desktop release than PR volume.

Release-triggered fleets and automatic merging solve a coordination problem Steve rarely has. The full testing matrix is a menu. Maintaining every layer would consume time he could spend checking the few workflows his users actually depend on. [Lauren Tan’s talk](https://ai.engineer/talks/O_zcc6Xl12g-all-code-is-slop-except-mine)

## 2. One reusable project

I’d make **one small template repository** with three files:

| File | Purpose |
|---|---|
| `README.md` | Adoption instructions, the correction loop, and a short paragraph to add to existing agent instructions. |
| `templates/check.ps1` | A Windows entry point for a project’s existing lint, type and test commands. It stops on failure and returns the failing exit code. |
| `templates/FEATURES.md` | A worked example mapping a user-visible feature to its verification command and expected result. |

A new project copies the templates and fills in its first real workflow. An existing project keeps its working check command and feature documentation wherever they already live. In either case, `AGENTS.md` names the check command and feature-map path, and `CLAUDE.md` directs Claude to that same section. Each project owns its checks. Promote a pattern back to the template once it proves useful in a second project. I’d start without an installer or agent-specific skills.

## 3. From correction to deterministic check

Record the correction in the current task or issue as **observed behavior → expected behavior**, with one failing example. The implementing agent decides whether a small API change removes the mistake, an existing lint rule catches it, or a regression test best expresses the requirement. A one-off preference can stay in the task.

For example, if Cancel overwrites a file, give the file known contents, cancel the operation, then compare its bytes. Run the test against the faulty version, observe the intended failure, apply the fix and rerun it. Add it to the ordinary project check. Claude and Codex run the focused check while editing and the project check before handoff. Existing CI can invoke that same command. The lasting record is the named test and its failure message.

## 4. Runtime verification across languages

Standardize the **feature-map entry**. Let each project pick its driver.

| Feature | User path | Command | Observable result |
|---|---|---|---|
| Remember theme | Open Settings, choose Dark, close and reopen | `.\check.ps1 theme-persists` | The reopened app shows Dark selected using the same temporary profile. |

For Python tools, the driver can invoke the public CLI against a temporary directory and inspect the output file. For Electron, it can launch the app and operate named controls through its existing UI test harness. A native Windows app can use Windows UI Automation. Each driver should exit nonzero on a failed assertion and report what it observed. Capture a screenshot when appearance matters. Start with one workflow Steve would otherwise verify by hand.

## 5. Claude, Codex and cheap workers

Use a cheap worker for a bounded patch with a clear acceptance example. Codex can verify it from Steve’s request, inspect the diff and exercise a failure path the writer missed. Reserve Claude’s Pro allowance for ambiguous intent, architectural tradeoffs or consequential changes. If Claude writes the patch, Codex can verify it. Routine changes with a convincing regression check can finish in one session.

## 6. Where I disagree

I’d keep comments that explain an external constraint or a surprising decision. I’d also keep the reported 70% verification-token figure out of the budget. A ten-second test that catches tomorrow’s regression is a better investment than repeated model reviews. Formal methods earn their upkeep when Steve can name a consequential invariant, such as “retrying an interrupted import cannot duplicate records.” Even then, Steve still decides whether that invariant captures what the user needs.