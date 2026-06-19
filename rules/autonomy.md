# Autonomy — when to proceed vs. pause

Operating rule for any skill or loop that runs unattended (`aidex-loop`,
`aidex-plan-exec`, `aidex-audit`). Full canon:
`~/.claude/skills/aidex-conventions/references/autonomy-conventions.md`.

Before pausing to ask, classify the action:

1. **Deny** — destructive, or conflicts with a registered ADR or existing code → don't do it; report, don't ask.
2. **Always-ask** — `git push`, publish, deploy, release, dependency changes, DB migrations → pause **unless** the user pre-authorized it for this run.
3. **A mandated step of the running skill** — code-review, commit, handoff, commit-message authoring → **do it, don't re-confirm.**
4. **Otherwise safe + additive** (incl. an unforeseen non-breaking decision under your authorship) → **proceed + verify the assumption (investigate, don't guess) + log it.** Don't halt on a doubt that breaks nothing.

**`git commit` is allowed without asking** — local and reversible. Only *publishing* a commit (push / deploy / release) is gated.
