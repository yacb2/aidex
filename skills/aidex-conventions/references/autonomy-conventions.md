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

## The durability-arbiter (active enforcement)

The rules above are static; at a real mid-run boundary the executing agent still
tends to default to "better ask". The **durability-arbiter** is the active
enforcement of this canon: a focused subagent the executor consults *instead of*
stopping to ask the user. It plays the user's standing posture — *"don't stop yet,
you can do this, continue"* — but **with criterion**: it applies the allow/ask/deny
classification plus a proof-of-safety gate, and returns `CONTINUE` / `ASK` / `STOP`.

**Consult it only at an *ambiguous* would-stop boundary** — not every step. Clear
cases are resolved inline by the rule above (a `commit` is never a question; a
`push` is always the ask-set). Consult when the executor is about to pause on a
judgment call it cannot cleanly classify.

**The consultation passes:** the standing autonomy surface (allow/ask/deny fixed at
the initial phase), the situation (what was just done; what it wants to do, or why
it would stop), the **proof** the next step is safe (verification output; additive /
reversible nature), and the stop condition / remaining work.

**It returns:**
- `CONTINUE` — proceed with the action; **log the bifurcation** for later review.
- `ASK` — genuinely the user's call (unauthorized publication, deny-class ambiguity).
  **Accumulate the question, finish all other safe work first, surface ONE batched
  question at the end.** Never pause the run waiting on it.
- `STOP` — the stop condition is met, or the action is deny-class / unsafe (skip + document).

**The verification coupling** (what keeps "stop less" from becoming "clean up more"):
a `CONTINUE` on a state-mutating action requires **proof it is safe** — verification
output, an additive/reversible nature, a passing gate. No proof for a mutating step →
the arbiter orders *verify first*, not *ask*. The gate is "do you have proof this is
safe?", not merely "is it in the allow-set?".

**Three guardrails so the arbiter never becomes the stall it prevents:**
1. **Ambiguous boundaries only** — overhead is real; do not consult on clearly-classified steps.
2. **Fail open to the canon, never block** — if the arbiter errors or returns nothing,
   apply the inline rule above and proceed. It is a forcing function, not a single point of failure.
3. **ASK is batched and deferred** — surfaced once, at the end, after all safe work is
   done. The run never silently waits (the Stop-hook deadlock failure mode).

The arbiter prompt lives at
[`../agents/durability-arbiter.md`](../agents/durability-arbiter.md); consuming skills
spawn it via the Agent tool with that prompt. It is consulted by the **main-loop
executor** — where the stop-to-ask decision actually happens — not by short-lived leaf
subagents.

## What is *not* gated (commit, deps, migrations)

- **`git commit`** — local + reversible. Commit freely; never ask "should I commit?"
  or "is the message OK?".
- **Dependency changes** (install / update / downgrade) — autonomous.
- **Migrations** — autonomous when additive. A *destructive* migration (data loss)
  falls under tier 1 (deny / confirm).

The gate is only **outward publication** (push / publish / deploy / release), and
even that is resolved at the initial phase, never mid-run.

## Chained work-lists (front-loading across many items)

Everything above governs a **single** process. A session that **chains many tracked
items** — a backlog sweep, closing several plans, reconciling audit areas — has a
second failure mode the single-process rule misses: it stops *between* items to ask
**"¿y ahora qué?"** (which item next?), because the cross-item **order** was never
fixed. Measured across real usage, this "what next?" menu is the dominant un-governed
stop, and it lands in ad-hoc multi-item sessions that never had an initial phase.

The fix is a **work-list** ([`worklist-conventions.md`](worklist-conventions.md)): the
initial phase fixes the ordered queue of items + the gate policy once, as a durable
`.context/worklists/` artifact; execution walks it (`worklist-advance.sh`) without
re-asking. This extends front-loading from "within one process" to "across a chained
work-list", and the queue survives handoff.

### The three classes of mid-run question

Classify any mid-run question before pausing. The goal is to remove the **avoidable**
ones — **not** to reach zero (trapping a real fork is worse than one extra question):

- **(a) Ordering of known items** — "which of these next?"; the alternatives already
  existed at the initial phase. → Resolved **once** into the work-list `## Queue`;
  **never** re-asked mid-run.
- **(b) Emergent discovered work** — more of the same surfaced mid-run ("found 3 more
  stale rows"). → **Append** to `## Deferred / emergent` and continue; **not** asked.
  (Mode-A bifurcation, applied to a work item.)
- **(c) Emergent decision** — a genuine fork the work itself revealed, whose options did
  not exist at planning ("the investigation found 3 paths: do all / quick-win only /
  log only"). → The **one** legitimate mid-run interrupt. Bias to allow it.

### Front-loading via the AskUserQuestion survey (transversal)

The initial phase captures parameters + the work-list + (for workflows) per-agent
models through the official **`AskUserQuestion`** tool as a structured survey — run
**first and to completion**, after which execution is **headless and menu-free**.
`AskUserQuestion` is the un-governed leak surface at *execution* time (a tool pause the
durability-arbiter never sees) and the right instrument at *planning* time. Use it for
**parametric / confirm-or-correct** decisions (each option carrying a recommended
default); **discuss** deep architectural forks rather than menuing them. Limits: ≤4
questions per call, interactive-only — which is exactly why the survey belongs to the
interactive initial phase and never to a headless run.

## Per-skill application

- **aidex-plan** — the design is the front-loading home: capture the **autonomy
  surface** (any deploy/publish to pre-authorize; planned migrations/deps that exec
  may run autonomously; anything to keep in `deny`) so execution needs no questions.
- **aidex-plan-exec** — resolve all clarifications at **Orient** (phase 0), then run
  every phase autonomously. Planned migrations/deps execute without asking; commit
  per phase, review, handoff are mandated (do them). Mid-run non-destructive
  bifurcation → do + document (in the plan doc / final summary). Only publish stays
  gated, surfaced at the end if not pre-authorized. **Consult the durability-arbiter**
  on an ambiguous mid-phase fork or before any would-stop at the between-phase
  checkpoint, passing the phase's proof (verification output, commit SHA).
- **aidex-audit** — scope and borders are set at `new` (phase 0). The run is an
  uninterrupted sweep: catalog each finding with best-judgment severity and **log
  the assumption**. Escalation to backlog/loop is a separate explicit sub-action;
  when an escalate/sweep step would pause to ask "escalate or triage yourself?",
  **consult the durability-arbiter** instead. For security audits, active
  exploitation / destructive verification is `deny`.
- **aidex-loop** — the design interview (Step 1.5) pre-declares the surface; the run
  then proceeds to its stop condition without interrupting. If the loop is about to
  pause on a consent point not in the declared ask-set, **consult the
  durability-arbiter** rather than deadlocking on it.
- **aidex-backlog** — an autonomous "work / sweep the backlog" pass resolves
  safe+additive items to completion; before halting with "the rest needs your
  decision", **consult the durability-arbiter** per item, halting only on the ones
  it returns `ASK`/`STOP` for.
