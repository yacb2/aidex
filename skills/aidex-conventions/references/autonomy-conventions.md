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

1. **Deny — never run, even mid-run, and never pre-authorizable.** Destructive /
   irreversible-with-data-loss operations on **real** data: dropping, resetting or
   truncating an application database in any environment (local, dev, staging, prod),
   a **destructive migration** (data loss), or anything conflicting with a registered
   ADR or existing code. → Do **not** execute; **document the skip and surface it**
   at the end — and, where a chain ledger exists, as an `OPEN OWED` delta too
   (see *A deferral must outlive its run* below).

   Unlike class 2, this class has **no pre-authorization path** — deliberately. A
   run cannot be granted permission up front to destroy real data, because at
   planning time the need is unknown, and a checkbox granted in advance decays into
   a rubber stamp. If a run genuinely cannot proceed without one, that is a **hard
   blocker**: stop and surface it. Stopping is cheap here precisely because the case
   is rare, and the need almost always signals a shortcut around a migration
   conflict or schema drift — which is the thing to investigate, not to execute.

   **Not in this class: disposable databases whose lifecycle *is* destruction.** E2E
   template clones, per-worktree throwaway databases, anything `test-e2e.sh` creates
   and resets — these are routine class-4 work needing no authorization at all.
   Reading them as class 1 forbids the E2E rule's own mandated command; that
   contradiction is what this carve-out closes.
2. **Pre-authorized at the initial phase — then autonomous.** Outward / irreversible
   *publication*: `git push`, publish, **deploy**, **release**. These run unattended
   **only if the user pre-authorized them in the initial phase**. If not
   pre-authorized and a need arises mid-run: do **not** publish and do **not** block
   — finish all safe work, leave the publish undone, and surface it at the end as
   the one open question, and as an `OPEN OWED` delta where a chain ledger exists
   (see *A deferral must outlive its run* below).
3. **A step this skill/spec already mandates** (review, commit, handoff, message
   authoring) → **do it; do not re-confirm.** (Mode B.)

   **Precedence over `session-handoff`.** That skill instructs the agent to propose a
   handoff and confirm before running it. The guard is correct for a *conversational*
   session, where handing off is the user's call. **Inside an active unattended run it
   is superseded by this clause**: the handoff is a mandated step and runs without
   asking. Both files load into the same session, so the conflict is live rather than
   theoretical, and the observed symptom is a run pausing to ask permission to hand off
   — precisely the stop the process exists to prevent (field-observed 2026-08-01).
   Outside a run, `session-handoff`'s propose-first behaviour is unchanged.
   Note the ownership limit: `session-handoff` is not in `~/.aidex/.manifest`, so this
   repo can state precedence but cannot edit that skill. It does have an owner, though,
   and it is not this codebase: the skill ships from `claude-session-handoff`, which
   actively maintains this exact boundary (`15b42a3`, 2026-08-06, separates asking for a
   handoff *prompt* from asking for the *move*). So if precedence alone proves
   insufficient in the field, file it there rather than stacking a third precedence
   clause here — two files already state it and a third would not be read either.
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

### A deferral must outlive its run

Classes 1 and 2 both end in "surface it at the end", and the end of a run is not where
anyone is standing when the run spans sessions: a handoff re-drafts the brief from
scratch, so the final summary is exactly what does not survive. Three phase decisions
deferred this way were absent one link later with no record they had ever been owed
(`research/2026-08-22-chain-context-decay.md` in `claude-session-handoff`, Result 2;
user-owed obligations survived a hop 17% of the time, the worst class measured).

So where a chain ledger exists, a deferral is an **`OPEN OWED` delta as well** — not
instead of the final summary, in addition to it. An item there leaves only when a
`CLOSE` delta closes it, so it survives until it is answered rather than until the next
re-draft. This is the canon for the one-line form in `rules/autonomy.md`; the two must
agree, and a clause living on only one of the two surfaces is the failure this file has
already litigated once.

### Integrating a branch is not a commit (class 2)

`git merge` into the trunk — and `rebase --onto` it, a `cherry-pick` onto it, a
fast-forward of `main` — is **class 2**, not class 4. It is grouped with publication
rather than with commit for one reason: it **ends the review window**. A commit is
local and reversible and leaves the work still reviewable as a unit; a merge into the
trunk dissolves that unit. A run that finishes its work leaves the branch **ready to
merge** and says so in its final summary.

**The direction is part of the rule, not an inference.** Merging the trunk *into* a
feature branch to stay current is routine class-4 work and stays ungated — a session
does it several times a day, and a clause that caught it would be worse than the
silence it replaces. Only branch → trunk is gated.

**Class 2, deliberately, not class 1.** "Close it and merge when green" is a perfectly
good standing instruction at planning time, so the pre-authorization path must exist.
Making it class 1 would break legitimate unattended flows and get the rule quietly
ignored, which is the failure mode that produces rules nobody reads.

**Why this is written down.** On 2026-08-15 a plan-exec run merged its worktree branch
into `main` in both participant repos, with no merge request anywhere in the chain —
the last user instruction was a `/handoff` to continue Phase 6 in the worktree. It was
**not a violation of this canon; it was a hole in it.** Class 4 read as "safe +
additive", `git commit` was listed as ungated, and nothing distinguished a local merge
from one. `aidex-plan-exec`'s close-out contains zero occurrences of merge/branch/main —
close-out meant tearing the worktree down, not integrating it. The only anti-merge
sentence in the entire suite lived in a comment inside `worktree.sh`'s teardown path,
invisible from a plan-exec session. Two other merges the same fortnight were explicitly
requested (2026-08-13 *"luego podemos mezclar"*; 2026-08-19 *"after owner review"*),
which is what makes the third legible as a gap rather than a habit.

**Tearing down a worktree is close-out; integrating its branch is not.** The two are
routinely confused because they happen at the same moment.

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
   done. The run never silently waits (the Stop-hook deadlock failure mode). "The end"
   is the end of the RUN, not of the session: where the run spans a handoff, the batched
   ASK is also an `OPEN OWED` delta (see *A deferral must outlive its run*).

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

#### When there is no interactive channel

A run launched under `claude -p`, from a cron/scheduled routine, or from any other
non-interactive surface reaches the survey with nowhere to ask. Stating that
`AskUserQuestion` is interactive-only does not say what to do instead, and an undefined
step is the one thing an unattended run cannot recover from. The fallback, for every
skill whose initial phase is a survey:

**Do not attempt the survey. Take each question's recommended default, and record in the
artifact the run writes — plan, spec, work-list, audit brief — that the parameters were
defaulted because no interactive channel was available.** Then execute as normal.

Two consequences follow, both deliberate:

- **Never treat the absent channel as a blocker.** A defaulted parameter is a documented
  assumption, not a hard blocker; hard blockers stay defined as they are above.
- **A decision that cannot be defaulted is not survey material.** If a question has no
  defensible default, it is an architectural fork — the canon already says to *discuss*
  those rather than menu them, which means it belongs to an interactive session and the
  run should not have been launched headless. Say so in the artifact and stop.

This is a documented behaviour, not a runtime check: nothing detects the surface, and no
skill should try. The other four facts of this kind are indexed in § Execution environment
below.

## Execution environment — what a given run actually provides

Not every Claude that this suite starts gets the same tools, the same rules, or the same
interactive channel. Those facts are true, load-bearing, and **scattered across five
documents**, each filed under an unrelated heading. When one of them stops being true,
nothing points at the other four — so they are indexed here:

| Fact | Recorded in |
|---|---|
| Headless `claude -p` does not ship `artifact-design` (field-verified 2026-07-23) | `rules/artifacts-local-first.md` |
| `AskUserQuestion` is interactive-only; the fallback is above | this document, § above |
| `~/.claude/rules/` is the only surface that loads; a copy under `~/.aidex/` loads nothing | `install.sh` header + repo `CLAUDE.md` |
| A spawned eval child inherits CWD, pays MCP cold-start, and loads every ambient skill | `skill-trigger-eval-methodology.md` |
| Per-agent `model` / `effort` are assigned explicitly, not inherited by accident | `aidex-plan-exec` + `aidex-workflow` SKILL.md |

**Naming.** Call this the *execution environment*, never the *harness*: in this suite
"harness" already means the PTY / `claude -p` eval runner, throughout
`skill-conventions.md`, `skill-trigger-eval-methodology.md` and a script path. Reusing the
word here would make every "verify the harness" line ambiguous.

## Per-skill application

- **aidex-plan** — the design is the front-loading home: capture the **autonomy
  surface** (any deploy/publish to pre-authorize; planned migrations/deps that exec
  may run autonomously; anything to keep in `deny`) so execution needs no questions.
- **aidex-plan-exec** — resolve all clarifications at **Orient** (phase 0), then run
  every phase autonomously. Planned migrations/deps execute without asking; commit
  per phase, review, handoff are mandated (do them). Mid-run non-destructive
  bifurcation → do + document (in the plan doc / final summary, and as an `OPEN OWED`
  delta where a chain ledger exists). Only publish stays gated, surfaced at the end if
  not pre-authorized. **Consult the durability-arbiter**
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
