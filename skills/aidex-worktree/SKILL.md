---
name: aidex-worktree
description: Use when the user wants to set up a git worktree for parallel work and needs to decide whether to isolate the environment (database, ports, containers) or share it, or when a project has no worktree procedure yet and one needs to be bootstrapped by investigating the repo's topology and interviewing the user — "set up a worktree for X", "should this run isolated or share the dev DB", "how do we do worktrees on this project", first-time worktree setup. Also fires when aidex-plan/aidex-plan-exec/aidex-loop reach their Isolation step and no `.context/worktrees/00-index.md` exists yet. Not for: actually creating the worktree directory (native EnterWorktree/ExitWorktree); planning multi-step work (aidex-plan); designing a loop (aidex-loop).
argument-hint: "[bootstrap | suggest | status]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-worktree"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Worktree — Bootstrap & Suggest Per-Project Worktree Procedure

Own the **bootstrap interview** and the resulting `.context/worktrees/00-index.md`
artifact for a project — never the worktree runner itself. Native `EnterWorktree` /
`ExitWorktree` still perform the actual `git worktree add`/removal; this skill decides
and records *whether* and *how* to isolate (Tier 1 code-only vs Tier 2 full environment)
so that decision does not get re-litigated on every task.

See [references/01-topology-detection.md](references/01-topology-detection.md),
[references/02-worktree-overview-conventions.md](references/02-worktree-overview-conventions.md),
and [references/03-case-taxonomy.md](references/03-case-taxonomy.md) for the full canon
(topology-detection method, artifact conventions, and the four-axis case taxonomy the
interview walks).

---

## Sub-actions

Dispatch by first argument:

| Command | Purpose |
|---|---|
| `/aidex-worktree` (no args) | Check whether `.context/worktrees/00-index.md` exists; if yes print a one-line status + point to `suggest`; if no, offer to run `bootstrap` |
| `/aidex-worktree bootstrap` | Investigate topology + interview + scaffold the doc |
| `/aidex-worktree suggest` | Read the existing doc and recommend Tier 1/2 (which participants, which infra strategy, which cleanup) for the task at hand |

### No-args status check

1. `test -f .context/worktrees/00-index.md`.
2. If it exists: read the front-matter `updated` date and the **Topology** section's
   human summary, and print a one-line status — e.g. "Worktree procedure recorded
   (updated 2026-06-30): split-git services (backend, frontend) glued by
   `dev.sh`." — then point the user to `/aidex-worktree suggest`.
3. If it does not exist: tell the user no worktree procedure is recorded yet, and offer
   to run `/aidex-worktree bootstrap`.

---

## `bootstrap` — investigate, interview, scaffold

1. **Detect existing doc.** If `.context/worktrees/00-index.md` already exists, refuse
   to overwrite (this mirrors `new-worktree-overview.sh`'s own refusal) — tell the user
   to edit it directly or delete it first if they want to re-bootstrap from scratch.
2. **Investigate topology.** Run
   [scripts/detect-topology.sh](scripts/detect-topology.sh):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/detect-topology.sh"
   ```
   Present its findings to the user in plain language — e.g. "root has no `.git`;
   `backend/` and `frontend/` are separate git repos; `frontend_mobile/` too; found
   `docker-compose.yml` and `dev.sh` at root" — or whatever the real facts are for
   *this* project. Never assume monorepo or any other prior default; the script only
   reports facts, the summary is yours to write from what it actually found.
3. **Interview.** Walk the four axes below **one question at a time** (use
   `AskUserQuestion` with a recommended default, per the front-loaded-autonomy survey
   pattern). Do not flatten them into a single "case A/B/C" question — each axis is a
   genuinely separate decision. Full detail on each axis lives in
   [references/03-case-taxonomy.md](references/03-case-taxonomy.md); the essentials:

   - **Axis 1 — Tier (what must be isolated).** For this project, what distinguishes:
     Tier 0 (not parallel to anything — no worktree needed), Tier 1 (code-only
     parallelism — no services/DB touched), and Tier 2 (full environment isolation —
     runs migrations / needs the stack live / mutates shared state)? Record the
     concrete signal the project uses to tell them apart (e.g. "touches `migrations/`"
     or "runs `docker compose up`") — not a vague description.

   - **Axis 2 — Scope (which participants).** Which directories/repos participate in
     worktrees at all? Some may never need one (e.g. a docs-only sibling repo). When
     work spans more than one participant, is there a branch-naming convention that
     keeps them coordinated (e.g. the same branch name in each touched repo)? Record
     it — worktrees are selected **per participant touched**, never "all or nothing."

   - **Axis 3 — Infra strategy (only if Tier 2 is reachable at all).** Is there already
     an isolation mechanism to generalize (a test/e2e script, a compose profile, a DB
     template-clone)? Which strategy does/would it use: clone full infra, clone partial
     infra (same DB server, new DB name), or share with logical partitioning? If none
     exists, record Tier 2 as **not yet available** and note what's missing — do NOT
     build the isolation mechanism here; this skill records the recipe, it does not
     author `worktree-up.sh` scripts for real projects (BL-024's still-open
     project-scoped follow-up).

   - **Axis 4 — Lifecycle & cleanup.** Ephemeral (spin up -> run -> auto-teardown) or
     persistent (iterate for hours/days -> explicit teardown on exit)? What exactly
     must be cleaned up when a Tier-2 worktree closes: isolated DB dropped, isolated
     compose project/containers/network stopped (**never** shared named volumes),
     allocated port offset freed, worktree directory kept or removed. If N worktrees
     can run at once, what is the concrete, deterministic port/offset allocation rule
     (not just "offset by index" — how are collisions between concurrent sessions
     avoided)?

4. **Scaffold.** Run
   [scripts/new-worktree-overview.sh](scripts/new-worktree-overview.sh):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/new-worktree-overview.sh"
   ```
   then fill every section of the generated `.context/worktrees/00-index.md` from the
   interview answers. Leave nothing as a placeholder.

## suggest

Recommend a tier for the **current task**, grounded entirely in this project's own
recorded doc — never re-derive a generic recipe.

1. **Require the doc.** `test -f .context/worktrees/00-index.md`. If it does not exist,
   say so plainly and point to `/aidex-worktree bootstrap` — never invent a topology or
   guess a tier for a project that hasn't recorded one.
2. **Read the doc's four axis sections.** Load **Participants & scope**, **Tier
   decision**, **Tier 2 infra strategy**, and **Lifecycle & cleanup** — the four axes
   from [references/03-case-taxonomy.md](references/03-case-taxonomy.md). Do not read
   only the front-matter; the recommendation is built from the body.
3. **Resolve each axis against the current work.** Either ask the user directly, or, if
   the calling plan/loop content already states the facts, use those without
   re-asking:
   - **Participants (Axis 2):** which of the project's recorded participants does this
     work touch — one, some, or all? Only touched participants need a worktree.
   - **Tier (Axis 1):** does the work trip the project's own recorded Tier 2 signal
     (e.g. "touches `migrations/`", "runs `docker compose up`")? If not, and it's
     parallel to other in-flight work, it's Tier 1; if it isn't parallel to anything,
     it's Tier 0 — no worktree needed.
   - **Infra strategy (Axis 3):** only if Tier 2 applies — which strategy does the doc
     already record (clone full, clone partial, share with logical partitioning, or
     not yet available)?
   - **Lifecycle (Axis 4):** does this work need ephemeral or persistent isolation, and
     what does the doc's recorded cleanup procedure say to do on exit?
4. **Return the recommendation.** State: the tier; which participants (not necessarily
   all) need a worktree; if Tier 2, the infra strategy and the cleanup steps — quoting
   the project's own recorded procedure text verbatim, never a generic recipe. If the
   doc records Tier 2 as "not yet available" for this case, say so and fall back to
   Tier 1 (or Tier 0) instead of inventing an isolation mechanism.
5. **Stop — never auto-invoke.** This is a recommendation the user or the project's
   `CLAUDE.md` authorizes. Never call native `EnterWorktree` from here; state the
   suggestion and stop. The caller (user, or `aidex-plan`/`aidex-plan-exec`/
   `aidex-loop` at their Isolation step) decides whether to act on it.

---

## Boundaries

| The user wants to… | Route to |
|---|---|
| Actually create/enter a worktree right now | native `EnterWorktree` / `ExitWorktree` |
| Plan multi-step work (no worktree decision) | `aidex-plan` |
| Design an agentic loop | `aidex-loop` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf) | `aidex-audit` |

## Related

- **aidex-plan / aidex-plan-exec / aidex-loop** — call into this skill at their
  Isolation step instead of improvising a tier decision.
- **aidex-conventions** — owns the shared `.context/` documentation canon
  (`worktree-conventions.md` holds the prior behavioral canon this skill operationalizes).
