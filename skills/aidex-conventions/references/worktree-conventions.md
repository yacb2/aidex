# Worktree & Isolation Conventions (parallelization surface)

Shared operating canon for **when a process should run in its own git worktree, and
how much of the environment to isolate**. Owned here; referenced by `aidex-plan`,
`aidex-plan-exec`, and `aidex-loop`. Like the autonomy canon this is a *behavioral*
canon (it governs runtime conduct, not a `.context/` artifact format), so each consuming
skill keeps a short inline summary and points here for the full rule.

> Backed by research `research/worktree-parallelization-strategy/` (topology verified on
> the user's monorepos; native Claude Code worktree tooling; the code-vs-environment
> isolation literature).

---

## The core distinction

**A git worktree isolates *code*, not *environment*.** It gives you N working
directories on N branches sharing one `.git`. It does nothing about the **database,
host ports, caches, or running services** — those still collide. The expensive problem
is the environment, and it is what decides the tier below.

The friction this solves: a branch alone forces serialization (one working tree, one
checked-out branch), so you stop work A to keep it from contaminating work B — even when
the files never overlap. Worktrees let both proceed; environment isolation lets both
*run* without trampling shared state.

## The two tiers

Pick the tier from the work, not from habit. **Choosing the tier is the whole decision.**

### Tier 1 — code-only worktree (cheap)

- **What:** a second working directory on its own branch. Nothing else isolated.
- **Mechanism:** native `EnterWorktree` (or `git worktree add`); `isolation: "worktree"`
  on a subagent/Workflow stage for parallel batched edits.
- **Use when:** pure code work — refactor, new module, docs, a self-contained feature —
  that does **not** run services and does **not** touch the DB/migrations; or work you're
  content to **verify centrally in the main worktree** (start the stack only there).
- **Cost:** disk (a full tree copy) + review/merge burden. Negligible setup.

### Tier 2 — full environment isolation (expensive)

- **What:** a worktree **plus** an isolated DB, isolated Docker compose project, isolated
  ports, isolated `.env`.
- **Mechanism:** worktree + a project-provided `worktree-up` recipe (see below).
- **Use when:** the work **runs migrations**, needs the **stack live** to iterate, or
  otherwise risks **DB-state collision** with parallel work. This is the only case that
  justifies the expensive path.
- **Cost:** a second DB (cheap if template-cloned), a second compose project, port
  arithmetic, teardown discipline.

### The decision heuristic

```
Is this work parallel to other in-flight work?
  no  → no worktree. Just a branch (or just do it).
  yes → Does it run services or mutate the database in parallel?
          no  → Tier 1 (code-only worktree).
          yes → Tier 2 (full environment isolation).
```

Keep parallelism to **3–5 worktrees**; beyond that, disk/IO (file watchers + test
runners + builds per tree) and the review burden offset the gains.

## The opt-in gate (who decides vs who authorizes)

Native `EnterWorktree` fires **only** when the user says "worktree" or **CLAUDE.md /
memory instructs it**. Respect that gate: a skill **recommends** a tier; the **user or
the project's CLAUDE.md authorizes** the actual worktree. Never auto-enter a worktree the
user did not approve — surface the recommendation, then act on the answer.

## Repo topology changes the unit of isolation

- **Monorepo** (one repo holding backend + frontend + mobile, one compose file): a
  worktree is the **whole tree at one branch**. The unit is **per-task / per-branch, full
  stack** — *not* per-service (no "backend-only worktree" without `git sparse-checkout`,
  which rarely pays off here). Parallelism comes from two branches/tasks at once, each its
  own worktree with its own isolated stack.
- **Multi-repo** (separate backend/frontend repos): per-service worktrees *are*
  meaningful — each repo worktrees independently, and you isolate only the services that
  worktree actually runs.

Detect topology (`git rev-parse --show-toplevel` per service dir; one root = monorepo)
before recommending a unit.

## The environment-isolation recipe (Tier 2)

Four resources isolate per worktree. The canon is **stack-agnostic**: the project supplies
the concrete recipe via a **detected `worktree-up` script** (the way `aidex-plan-exec`
detects the project's review/commit commands). If no such script exists, **Tier 2 is not
available** — fall back to Tier 1 and note that a `worktree-up` recipe would unlock it.

| Resource | Strategy |
|---|---|
| **Database** | Per-worktree DB. Cheapest: a new DB **in the same Postgres container** via `CREATE DATABASE … TEMPLATE` (~200ms clone) under a unique name (`<db>_wt_<slug>`). Heaviest: a separate DB container. |
| **Ports** | Offset by worktree index: `base + N*10` (extends a `dev → +10` test convention). |
| **Docker** | `COMPOSE_PROJECT_NAME=<repo>-<slug>` so containers/networks/named-volumes don't collide. |
| **Env** | A per-worktree `.env` injecting the unique DB name + offset ports. |

**Gotchas to flag (don't let them silently break isolation):**

- A **hardcoded `container_name`** in `docker-compose.yml` overrides
  `COMPOSE_PROJECT_NAME` prefixing — two worktrees collide. Drop it (or parametrize) and
  env-drive host ports (`${DB_PORT:-5900}:5432`) before Tier 2 can work.
- **Never share Docker volumes** between worktrees to "save disk" — it corrupts state.
- An **ephemeral** test recipe (clone → run → tear down, e.g. a `test-e2e.sh`) is the
  right *seed* but the wrong *lifecycle*: a dev worktree is **persistent** (iterate for
  hours, tear down on exit). Generalize it into `worktree-up` / `worktree-down`.

## Lifecycle

Enter at the process's **initial phase** (plan Orient / loop design), iterate, then on
completion `ExitWorktree` (`keep` to resume later, `remove` for a clean exit — it refuses
to drop uncommitted work unless `discard_changes`) and run `worktree-down` for Tier 2 to
drop the DB + compose project. This is consistent with front-loaded autonomy: the
isolation decision is made up front, not mid-run.

> **Plan/spec artifact stays in the main tree.** A fresh worktree contains only
> **committed** files, so a `.context/` plan or loop-spec that is gitignored or merely
> uncommitted will **not** be present inside the worktree. Keep the driving artifact as
> source-of-truth in the **main working tree** — mark phases done and record `proof_links`
> there (at its main-tree path), not in the throwaway worktree where the edits would
> vanish on `remove` or diverge from main on `keep`. The worktree is for the **code work**;
> the plan tracks it from outside. (Alternatively, commit the plan before entering — but
> that fails for a gitignored `.context/`, so the main-tree rule is the safe default.)

## Per-skill application

- **aidex-plan** — capture the **Isolation surface** in the plan (parallel? which tier?
  which `worktree-up` recipe) so execution needs no questions. *Suggest* the tier from the
  plan's content (migrations present? services run?); record it as a recommendation the
  user authorizes.
- **aidex-plan-exec** — at **Orient (phase 0)** read the Isolation surface; for Tier 1
  `EnterWorktree`, for Tier 2 run the project's `worktree-up`. Tear down at completion.
- **aidex-loop** — the design interview pre-declares the Isolation tier next to the
  autonomy surface. Unattended loops that run migrations or mutate the DB are the
  **strongest** Tier-2 case (they trample shared state while you work elsewhere).
- **aidex-audit** — usually Tier 0/1 (read-mostly). Exception: a security audit doing
  destructive verification needs Tier 2. Low priority.
