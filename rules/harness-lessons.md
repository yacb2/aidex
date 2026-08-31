# Harness lessons — one line each

Corrections about how the *harness* behaves — Bash, the tools, hooks, shell quoting,
skill loading — that are true in every project. Not project facts, not preferences.

**Budget: 400 words.** This file is always-on: every line is paid in every session of
every project, forever. A lesson that needs a paragraph belongs in a skill's
`references/`, with one line here pointing at it. Exceeding the budget means a lesson
was mis-routed, not that the budget is wrong.

Where a lesson is already enforced by a rule, a check or a script, it does not belong
here — the mechanism is the memory.

<!-- Lessons below, one line each, newest last. -->

- `/code-review` agents have full tool access and **do write to the working tree**, then
  report their own edit as your defect — commit before launching one, and pass an explicit
  `<base>..<tip>` sha range, never `..HEAD` (from a worktree it inverts).
- One failing call **cancels the entire parallel tool batch** — Writes, Edits and commits
  in it silently do not apply. After any `Cancelled:` result, re-verify with `git status`.
- The harness replaces any `local@domain` literal in **your tool inputs** (Bash and file
  content alike) with a redaction string; stdout is untouched. Derive addresses from data
  at runtime instead of typing them.
- `total_cost_usd` is computed locally at API list rates — not a charge, and subscription
  work is not metered. Report probe runs in tokens against quota.
- Never put `model:` in command front-matter — it inherits the parent's 1M variant and
  throttles. Pass `model:` to the Agent tool instead.
- A repo that ships an installer is installed **by running it**. Symlinking its working
  tree into `~/.claude/skills` makes branch state live and has no doctor watching it.
- Two sessions on one workspace share the same git working tree: `checkout`, `stash` and
  `branch` are global per repo and move the other session's view. Warn, restore the
  original branch, and never touch or commit changes that are not yours.
- Two `chrome-devtools` traps — a suppressed native file picker, and a profile lock held
  by the previous session's stack — are in `fix-chrome-devtools/references/session-and-picker.md`.
