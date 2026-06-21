# Autonomy — front-loaded, then run start-to-finish

Operating rule for any process that runs unattended (`aidex-plan-exec`,
`aidex-audit`, `aidex-loop`). Full canon:
`~/.claude/skills/aidex-conventions/references/autonomy-conventions.md`.

**Core principle:** once a process starts, run it autonomously **start to finish**.
All questions are asked in the **initial phase** (plan design / audit kickoff /
loop design interview). The run itself does not stop to ask permission or opinion.

During the run, classify before pausing:

1. **Deny — never, even mid-run:** destructive / data-loss ops, DB deletion (never delete the DB without explicit confirmation), destructive migrations, or conflicts with an ADR or existing code → don't do it; **document the skip and surface it.**
2. **Publication — pre-authorized at the initial phase:** `git push`, publish, deploy, release. Autonomous only if pre-authorized up front; if it comes up unplanned, don't publish and don't block — finish the safe work and surface it at the end.
3. **A mandated step of the running skill** — code-review, commit, handoff, commit-message authoring → **do it, don't re-confirm.**
4. **Otherwise safe + additive** — incl. dependency changes, additive migrations, and unforeseen non-breaking decisions → **proceed; if it's a bifurcation, execute and document it** for later review. Don't halt on a doubt that breaks nothing.

A genuine **hard blocker** (missing credentials, truly unknowable intended behavior) still stops — that is being blocked, not asking permission.

**Not gated:** `git commit` (local + reversible), dependency changes, additive migrations. Only *publishing* (push / deploy / release) is gated, and only at the initial phase.

**Ambiguous would-stop boundary?** Before stopping to ask, consult the **durability-arbiter** (`~/.aidex/skills/aidex-conventions/agents/durability-arbiter.md`, via the Agent tool) — it returns `CONTINUE` / `ASK` / `STOP` from this canon plus a proof-of-safety gate, batches any `ASK` to the end, and fails open (if it errors, apply the rule above and proceed; never block on it).
