# Claude's independent view (written before reading Codex's reply)

## Ideas that matter for a solo developer
1. **Inverse trust pyramid.** Spend effort top-down: codebase/API design > static checks (lint, types, tests) > runtime/formal verification > prose (CLAUDE.md, skills) > human review. Steve's current setup is mostly prose (large CLAUDE.md). Move weight up the pyramid.
2. **Every correction becomes a deterministic check**, not a new rule line. The "staircase" chart (7 -> 167 lint rules in 4 months) is the metric.
3. **Code is memory.** Agents copy what is in the repo. A workaround left in place becomes "the pattern". Order: lint rule to stop new copies, then clean old copies.
4. **Nuance leads to slop.** APIs that need judgement (useEffect, timers, threads, raw SQL, file deletes) are banned in product code and allowed only inside one small wrapper.
5. **Directory structure is context**, and boundaries are enforced (import rules), so the name tells the agent the rule and the check catches misses.
6. **Comments and unsolicited Markdown are liabilities.** Agents use them to justify shortcuts. Guidance belongs in the lint error message, which appears exactly when the rule is broken.
7. **Runtime verification:** feature map (what exists, how a user reaches it, what proves it works) + a reusable CLI driver. Review becomes looking at evidence (screenshots, output), not reading diffs.
8. **Fix the inner loop before automating.** Automating a slop loop makes more slop and burns tokens.

Does not transfer well: 11k PRs/month, auto-merge, release-fuzzing fleets (no CI fleet, Pro limits). TLA+/Lean: only for rare state-heavy logic (sync, file operations). "Ban 99% of comments" is too strict as a blanket rule; ban agent justification/history comments, keep "why" comments a human wrote.

## Proposed shape (minimal)
A small kit repo, applied per project by one adopt script:
- `check` entry point per project (`tools/check.ps1`): runs format, lint, types, tests and custom rules; exit code is the truth. Agents run it before saying "done".
- Custom rules via **ast-grep** (one cross-language tool, rule files with a `message:` that tells the agent the root-cause fix). Plus the language-native boundary tool where needed (import-linter for Python, eslint no-restricted-imports / dependency-cruiser for JS).
- `/correct` skill (Claude) + same text in AGENTS.md (Codex): when Steve corrects an agent, the agent proposes the cheapest enforcement in pyramid order (API change > rule > test > prose), adds it, and logs one line in `docs/CORRECTIONS.md` (date, mistake, check id). Prose-only entries must say why no check is possible.
- `/verify` skill + `docs/FEATURES.md` feature map + a driver CLI per project type: Playwright/CDP for web and Electron, UI Automation (PC-Control) for Windows desktop, golden output for CLIs. Evidence saved to `evidence/`.
- Global CLAUDE.md shrinks: rules that became checks are deleted from prose.

## Claude / Codex split
Writer and verifier are different agents. One writes the change and runs `check`; the other drives the feature map, collects evidence and reports findings without fixing them. Repeated findings go through `/correct`.

## Risks
- Rule sprawl and false positives: each rule needs a test case and a clear message; delete rules that never fire.
- Over-rotation: one small correction must not become a hard global rule (the talk warns about this). Rules are scoped to a project unless seen in 2+ projects.
- Setup cost per project: the adopt script must be small; start with `check` + `/correct` only, add verification when a project has a UI.
