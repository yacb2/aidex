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
- A rejection by the user (Esc, or denying the permission prompt) **cancels the entire
  parallel tool batch** — Writes, Edits and commits in it silently do not apply. A deny
  rule or a non-zero exit does not. After any `Cancelled:` result, re-verify with `git status`.
- `total_cost_usd` is computed locally at API list rates — not a charge, and subscription
  work is not metered. Report probe runs in tokens against quota.
- Two sessions on one workspace share the same git working tree: `checkout`, `stash` and
  `branch` are global per repo and move the other session's view. Warn, restore the
  original branch, and never touch or commit changes that are not yours.
- Two `chrome-devtools` traps — a suppressed native file picker, and a profile lock held
  by the previous session's stack — are in `fix-chrome-devtools/references/session-and-picker.md`.
- `~/.claude/projects/` dirs start with `-`, so a shell glob like `*/*.jsonl` hands `grep`
  arguments it parses as options: empty result, exit 0. Use `grep -- <glob>` or the Grep tool.
