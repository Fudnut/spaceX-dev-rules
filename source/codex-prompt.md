You are working with Claude (Anthropic) on a shared task for Steve. Claude collected the source material into this folder.

Source: the talk "All Code Is Slop (Except Mine)" by Lauren Tan (AI Engineer).
URL: https://ai.engineer/talks/O_zcc6Xl12g-all-code-is-slop-except-mine
- source/transcript.json : the full verbatim transcript (startMs + text). Read ALL of it.
- source/talk.md : the site's article version, chapter text and slide descriptions.
- source/slides/*.png and the attached contact sheets: the key slides (pyramid, trust loops, directory structure, quick-fix timers, lint-rule staircase, runtime verification feature map + CLI, formal verification, testing matrix, comments chart).
The slides mention pstack skills at github.com/cursor/plugins: /create-verification-skill, /create-formal-verification-skill, /no-comments, and a statechart skill. You may look at that repo with web search.

Steve's goal: turn the talk's ideas into ONE reusable project that he can apply to ALL his future software projects, used by Claude Code and Codex. Steve works on Windows, uses Claude Code (Pro plan, tight usage limits), Codex CLI, and cheap worker models. His projects vary (Python, Electron/JS, desktop tools). He prefers small, simple solutions: less is more, no speculative features.

Do NOT edit any files. Give your own independent view (Claude is writing its own separately; we will compare). Answer in this structure, under 900 words:
1. The 5-8 ideas from the talk that matter most for a solo developer with AI agents (not a 200-person team). Say which ideas do NOT transfer well and why.
2. Your proposed shape for the reusable project: what files/skills/scripts/templates it contains, and how a new or existing project adopts it. Keep it minimal.
3. The "correction -> deterministic check" loop: how it should work in practice with Claude Code and Codex (where corrections are recorded, who turns them into lint rules/tests, how checks run).
4. Runtime verification: a generic, cross-language way to give agents a "feature map + CLI driver" for Steve's kinds of projects.
5. How Claude and Codex should split work in this setup (e.g. writer vs verifier).
6. Risks and things you disagree with in the talk.
