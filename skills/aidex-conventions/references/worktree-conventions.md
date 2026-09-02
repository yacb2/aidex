# Worktree & Isolation Conventions (parallelization surface)

Shared operating canon for **when a process should run in its own git worktree, and
how much of the environment to isolate**. Owned here; referenced by `aidex-plan`,
`aidex-plan-exec`, and `aidex-loop`. Like the autonomy canon this is a *behavioral*
canon (it governs runtime conduct, not a `.context/` artifact format), so each consuming
skill keeps a short inline summary and points here for the full rule.

> Backed by research `research/worktree-parallelization-strategy/` (topology verified on
> the user's monorepos; native Claude Code worktree tooling; the code-vs-environment
> isolation literature).

> Detection and the per-project bootstrap interview are owned by the `aidex-worktree`
> skill, not by this canon or by the consuming skills directly — this file documents
> the shared reasoning (what a worktree isolates, the opt-in gate); `aidex-worktree` is where the
> per-project `.context/worktrees/00-index.md` gets read or created.

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

## One path, not tiers

A worktree is born with its full isolated stack, always: its own database, compose
project, ports and `.env`, with isolated E2E capability included. The mechanism is
`aidex-worktree`'s `worktree.sh new <slug> --branch <branch>`; the project supplies only
parameters (`.context/worktrees/config.env`, a `WT_PROFILE`). Creating the stack costs
seconds and tearing it down costs less, so there is no tier to weigh per task.

- **`--no-infra`** is the explicit code-only opt-out — a second working directory on its
  own branch and nothing else — for work that runs no services and touches no
  database or migration, or that you are content to verify centrally in the main tree.
- A repository with **no services at all** has nothing to isolate beyond the checkout:
  native `EnterWorktree` (or `git worktree add`) is the whole mechanism there.
- **Contract:** the isolated stack includes a runnable per-worktree `test-e2e.sh`
  (template DB clone + namespaced E2E ports) with no additional ask — never "decide per
  task."

### The decision heuristic

```
Is this work parallel to other in-flight work?
  no  → no worktree. Just a branch (or just do it).
  yes → worktree.sh new <slug> --branch <branch>
        (--no-infra only when it runs no services and touches no DB)
```

## The opt-in gate (who decides vs who authorizes)

Native `EnterWorktree` fires **only** when the user says "worktree" or **CLAUDE.md /
memory instructs it**. Respect that gate: a skill **recommends** a tier; the **user or
the project's CLAUDE.md authorizes** the actual worktree. Never auto-enter a worktree the
user did not approve — surface the recommendation, then act on the answer.

## Repo topology changes the unit of isolation

> **There is no default topology.** Do not assume monorepo: a sampled set of six such
> projects were all split-git services glued by an unversioned orchestration wrapper.
> Every project's topology is detected fresh — see
> `aidex-worktree/references/01-topology-detection.md`.

The list below is illustrative of the categories that exist, not a claim about which
one is typical:

- **Monorepo** (one repo holding backend + frontend + mobile, one compose file): a
  worktree is the **whole tree at one branch**. The unit is **per-task / per-branch, full
  stack** — *not* per-service (no "backend-only worktree" without `git sparse-checkout`,
  which rarely pays off here). Parallelism comes from two branches/tasks at once, each its
  own worktree with its own isolated stack.
- **Multi-repo** (separate backend/frontend repos): per-service worktrees *are*
  meaningful — each repo worktrees independently, and you isolate only the services that
  worktree actually runs.

Detect topology (`git rev-parse --show-toplevel` per service dir; one root = monorepo)
before recommending a unit — never assume from habit.

## The environment-isolation recipe (what `worktree.sh new` sets up)

Four resources isolate per worktree. The canon is **stack-agnostic**: the project supplies
the concrete recipe, recorded machine-readably in the `worktree_up`/`worktree_down`
front-matter fields of `.context/worktrees/00-index.md` (written by `aidex-worktree
bootstrap`) and surfaced by `detect-project-commands.sh` as
`worktree_up_command`/`worktree_down_command` — the same way `aidex-plan-exec` detects the
project's review/commit commands. If neither the front-matter nor a root/`scripts/`
`worktree-up*.sh` exists, **the isolated stack is not available** — use `--no-infra` and
note that a `worktree-up` recipe would unlock it.

| Resource | Strategy |
|---|---|
| **Database** | Per-worktree DB. Cheapest: a new DB **in the same Postgres container** via `CREATE DATABASE … TEMPLATE` (~200ms clone) under a unique name (`<db>_wt_<slug>`). Heaviest: a separate DB container. |
| **Ports** | Candidate offsets by worktree index (`base + N*10`, extending the `dev → +10` test convention) — but **probe before assigning** (`lsof -ti :<port>`, or `docker compose -p <slug> ps` for compose-level occupancy) and skip to the next offset on collision. Static arithmetic alone is not safe: concurrent sessions can compute the same offset, and an unclean exit can leave a port held by an orphaned container. `worktree-down` must verifiably free what it allocated. |
| **Docker** | `COMPOSE_PROJECT_NAME=<project>-wt-<slug>` — see the naming/teardown contract below. |
| **Env** | A per-worktree `.env` injecting the unique DB name + offset ports. |

**Gotchas to flag (don't let them silently break isolation):**

- A **hardcoded `container_name`** in `docker-compose.yml` overrides
  `COMPOSE_PROJECT_NAME` prefixing — two worktrees collide. Drop it (or parametrize) and
  env-drive host ports (`${DB_PORT:-5900}:5432`) before the isolated stack can come up.
- **Never share Docker volumes** between worktrees to "save disk" — it corrupts state.
- An **ephemeral** test recipe (clone → run → tear down, e.g. a `test-e2e.sh`) is the
  right *seed* but the wrong *lifecycle*: a dev worktree is **persistent** (iterate for
  hours, tear down on exit). Generalize it into `worktree-up` / `worktree-down`.

## Naming/teardown contract (Docker hygiene)

Every project with an isolated stack adopts the same compose-project naming and the same teardown
command — no project-specific variant:

```
COMPOSE_PROJECT_NAME=<project>-wt-<slug>          # -wt- is the sweep marker
worktree_down: docker compose -p <project>-wt-<slug> down -v --rmi local --remove-orphans
```

`<project>` is the main repo's basename. `--rmi local` removes exactly the
compose-built default-tagged images (`<project>-backend` etc.) while custom-tagged dev
images survive structurally. The `-wt-` infix is load-bearing, not cosmetic: without it
the compose project is just the bare slug ("rb", "ad-overlap") — unattributable to a
worktree, so a sweep can't tell a worktree's containers apart from the main tree's or
from an unrelated project's. `-wt-` is what makes teardown and the orphan sweep
mechanical. The Lifecycle & cleanup cleanup checklist (below, and in
`aidex-worktree`'s Axis 4) includes: "images built for the worktree removed (`--rmi
local`); anonymous volumes reclaimed."

### `compose down` is necessary, not sufficient

Two resource classes survive a zero-exit `compose down`, both measured on a real
workspace 2026-07-25 (15GB reclaimable, 24% of image storage; one network orphaned two
days):

- **Untagged build layers.** `--rmi local` reclaims only images the compose file
  currently references *by their default tag*. Every rebuild orphans the previous image
  as `<none>`, and no compose verb revisits it — 5 dangling 3GB layers accumulated from
  5 E2E runs of a single worktree. They remain attributable: compose stamps
  `com.docker.compose.project` on the image, so the reclaim is scopeable to one
  worktree. Enumerate then remove, never a bare prune:
  ```bash
  DANGLING="$(docker images -f dangling=true -f "label=com.docker.compose.project=$PROJECT" -q)"
  [[ -n "$DANGLING" ]] && docker rmi $DANGLING
  ```
- **The project network**, whenever a container from another stack was attached to it at
  down time. Compose leaves it and exits 0.

Therefore a teardown **verifies** rather than assumes: it ends by re-running
`orphan-sweep.sh --slug <slug>` and reporting the residue. An exit code is not evidence.

### Teardown is coupled to removal

`worktree-multi.sh remove` runs the recorded `worktree_down` **before** deleting the
worktree directory, and refuses when resources exist but no `worktree_down` is recorded.
The order is load-bearing: once the directory is gone the resources are unattributable —
a sweep can still see them but can no longer distinguish a dead worktree from a live one,
so they become permanent. Teardown documented as a separate step the user is trusted to
remember is the step that gets skipped.

## Docker safety doctrine — dangling is not disposable

A dev DB volume whose containers were removed by `compose down` (without `-v`)
**dangles while still holding real data** — "dangling" describes reachability from a
running container, not whether the data matters. Skipped teardowns accumulate untracked
`-wt-` volumes and images, and some of them hold data nobody has verified is disposable.

- **Banned outright:** `docker volume prune -a` / `--all` — it removes every unused
  volume system-wide with no per-item review, including named volumes that happen not
  to be attached to a running container right now.
- **Permitted:** anonymous-volume prune (`docker volume prune -f`, Docker ≥23
  semantics — anonymous volumes only, never named ones) and an explicit
  `docker volume rm <name>` for a **specific named volume taken from a sweep report the
  user has confirmed**. Never `rm` a volume the sweep didn't name, and never `rm` from
  memory of "probably orphaned" — always from the current report.
- The orphan sweep (`aidex-worktree/scripts/orphan-sweep.sh`, wired into
  `/aidex-worktree status`) is **report-only by construction**: it prints the exact
  reclaim command per orphan and never executes anything. Deletion is always a
  separate, explicit, human-confirmed step.

## Lifecycle

Enter at the process's **initial phase** (plan Orient / loop design), iterate, then on
completion `ExitWorktree` (`keep` to resume later, `remove` for a clean exit — it refuses
to drop uncommitted work unless `discard_changes`) and run the project's `worktree_down`
command (the naming/teardown contract above) to drop the DB, the compose
project, its containers/network, and its `--rmi local` images. This is consistent with
front-loaded autonomy: the isolation decision is made up front, not mid-run. A skipped
teardown is not a silent no-op: it is exactly what the Docker safety doctrine above and
the orphan sweep exist to surface.

> **Plan/spec artifact stays in the main tree.** A fresh worktree contains only
> **committed** files, so a `.context/` plan or loop-spec that is gitignored or merely
> uncommitted will **not** be present inside the worktree. Keep the driving artifact as
> source-of-truth in the **main working tree** — mark phases done and record `proof_links`
> there (at its main-tree path), not in the throwaway worktree where the edits would
> vanish on `remove` or diverge from main on `keep`. The worktree is for the **code work**;
> the plan tracks it from outside. (Alternatively, commit the plan before entering — but
> that fails for a gitignored `.context/`, so the main-tree rule is the safe default.)

## Per-skill application

Each consuming skill records the worktree command at its own initial phase (running
`aidex-worktree bootstrap` first if the project has no `.context/worktrees/00-index.md`
yet), instead of reasoning about isolation inline:

- **aidex-plan** — at plan Orient, record `worktree.sh new <slug> --branch <branch>`
  (`--no-infra` only when the plan runs no services and touches no DB) as the plan's
  **Isolation surface** so execution needs no questions.
- **aidex-plan-exec** — at **Orient (phase 0)** run the recorded command; with no
  worktree setup in the project, `EnterWorktree` and note it. Tear down at completion.
- **aidex-loop** — the design interview pre-declares the isolation next to the autonomy
  surface. Unattended loops that run migrations or mutate the DB are the **strongest**
  case for the full stack, never `--no-infra` (they trample shared state while you work
  elsewhere).
- **aidex-audit** — usually no worktree (read-mostly). Exception: a security audit doing
  destructive verification needs the isolated stack. Low priority.
