# Autonomy Conventions (front-loaded autonomy)

Shared operating canon for **how autonomously a skill runs before it pauses to
ask the user**. Owned here; referenced by `aidex-loop`, `aidex-plan`,
`aidex-plan-exec`, and `aidex-audit`. This is a *behavioral* canon, not a
`.context/` artifact format — it governs runtime conduct, so each consuming skill
keeps a short inline summary (a referenced file is read on-demand and may not be
loaded at the deciding moment) and points here for the full rule.

> Backed by the loop autonomy research — Claude Code's native `allow`/`ask`/`deny`
> model. See ADR `decision/2026-06-19-loop-autonomy-surface-native-permissions.md`,
> `decision/2026-06-19-autonomy-surface-plan-exec-audit-and-commit-policy.md`, and
> `research/loop-autonomy-permission-models/`.

---

## The core principle: front-loaded autonomy

**Once a process starts, it runs autonomously start-to-finish. All questions are
asked in the initial phase — the run itself is non-interactive.**

A "process" is a plan execution, an audit run, or a loop. Its **initial phase**
is the place where every clarification and every gate is resolved:

- Plan → the `aidex-plan` design + the `aidex-plan-exec` Orient step.
- Audit → the `/aidex-audit new` kickoff (scope + borders).
- Loop → the `aidex-loop` design interview (Step 1.5).

After that point the run does not stop to ask permission or opinion. If a fork
appears mid-run that you did not foresee, you resolve it (see tiers below) and
**document it for later review** — you do not interrupt.

## The two failure modes this eliminates

A process that runs unattended fails by **stopping when it should not**:

- **Mode A — the non-breaking doubt.** An unforeseen, non-destructive decision
  under your authorship where you halt to ask. → Resolve it + **document**; do not
  stop.
- **Mode B — the re-confirmation.** A step the skill already mandates and the user
  already authorized by invoking the workflow ("should I commit? is the message
  OK? should I hand off?"). → **Do it; do not re-confirm.**

## The native model (why `allow` is not the lever)

Precedence is fixed: `hooks → deny → ask → permission-mode → allow → canUseTool`.
`deny` and `ask` are evaluated **before** the mode, so they hold even under
`bypassPermissions`; `allow` is evaluated **after**, so an allowlist alone cannot
bound a permissive default. Shape a permissive-by-default run with **`deny`** and
**`ask`**, never an enumerated allowlist.

## The decision rule during the run

Classify before you pause:

1. **Deny — never run, even mid-run.** Destructive / irreversible-with-data-loss:
   dropping or deleting data, **DB deletion** (global rule: never delete the DB
   without explicit confirmation), a **destructive migration** (data loss), or
   anything conflicting with a registered ADR or existing code. → Do **not**
   execute; **document the skip and surface it** at the end.
2. **Pre-authorized at the initial phase — then autonomous.** Outward / irreversible
   *publication*: `git push`, publish, **deploy**, **release**. These run unattended
   **only if the user pre-authorized them in the initial phase**. If not
   pre-authorized and a need arises mid-run: do **not** publish and do **not** block
   — finish all safe work, leave the publish undone, and surface it at the end as
   the one open question.
3. **A step this skill/spec already mandates** (review, commit, handoff, message
   authoring) → **do it; do not re-confirm.** (Mode B.)
4. **Autonomous — proceed, and log any bifurcation.** Everything safe + additive,
   including dependency changes (install / update / downgrade), **additive
   migrations**, and an unforeseen non-breaking decision under your authorship. A
   mid-run fork that is **not destructive** → pick the reasonable path, **execute,
   and document it** so the user can review afterward. Verify the assumption
   (investigate, don't guess); you may read the DB and take a backup without asking.
   Do **not** halt on a doubt that breaks nothing.

A genuine **hard blocker** (missing credentials, a test whose intended behavior is
truly unknowable) is not "asking permission" — you literally cannot proceed. That
still stops. Everything resolvable does not.

## What is *not* gated (commit, deps, migrations)

- **`git commit`** — local + reversible. Commit freely; never ask "should I commit?"
  or "is the message OK?".
- **Dependency changes** (install / update / downgrade) — autonomous.
- **Migrations** — autonomous when additive. A *destructive* migration (data loss)
  falls under tier 1 (deny / confirm).

The gate is only **outward publication** (push / publish / deploy / release), and
even that is resolved at the initial phase, never mid-run.

## Per-skill application

- **aidex-plan** — the design is the front-loading home: capture the **autonomy
  surface** (any deploy/publish to pre-authorize; planned migrations/deps that exec
  may run autonomously; anything to keep in `deny`) so execution needs no questions.
- **aidex-plan-exec** — resolve all clarifications at **Orient** (phase 0), then run
  every phase autonomously. Planned migrations/deps execute without asking; commit
  per phase, review, handoff are mandated (do them). Mid-run non-destructive
  bifurcation → do + document (in the plan doc / final summary). Only publish stays
  gated, surfaced at the end if not pre-authorized.
- **aidex-audit** — scope and borders are set at `new` (phase 0). The run is an
  uninterrupted sweep: catalog each finding with best-judgment severity and **log
  the assumption**. Escalation to backlog/loop is a separate explicit sub-action.
  For security audits, active exploitation / destructive verification is `deny`.
- **aidex-loop** — the design interview (Step 1.5) pre-declares the surface; the run
  then proceeds to its stop condition without interrupting.
