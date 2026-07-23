# Case Taxonomy — the Four-Axis Model

The generic, stack-agnostic taxonomy that `bootstrap`'s interview walks and `suggest`
reads against. It is **four independent axes**, not a flat enum of cases — a real
task's answer is always a tuple across all four, never a single letter grade.

---

### Axis 1 — Tier (what must be isolated)

What the work needs isolated, from cheapest to most expensive:

- **Tier 0 — not parallel.** The work isn't running alongside other in-flight work at
  all. No worktree needed; just work in the main tree (or take a plain branch).
- **Tier 1 — code-only parallelism.** A second working directory on its own branch is
  enough — the work does not run services and does not touch the database/migrations.
  Verification can happen centrally in the main worktree if the stack only needs to
  run in one place.
- **Tier 2 — full environment isolation.** The work runs migrations, needs the stack
  live to iterate, or otherwise mutates shared state (DB, caches, running services) in
  a way that would collide with parallel work.

**Contract:** Tier 2 = full isolation including isolated E2E capability by default: the
`worktree_up` command must leave a runnable per-worktree `test-e2e.sh` (template DB
clone + namespaced E2E ports) with no additional ask. The independent-E2E trigger is
**included by default** for Tier 2 — not "decide per task."

Record the **concrete signal** the project uses to tell these apart (e.g. "touches
`migrations/`" or "runs `docker compose up`") — never a vague description like "big
changes."

### Axis 2 — Scope (which participants)

Which of the project's detected repos/services actually participate in worktree work:

- **One** — only a single participant is touched (e.g. backend-only bug fix in a
  split-git topology).
- **Some, not all** — a subset of participants (e.g. backend + frontend, but not the
  mobile repo).
- **All** — every participant is touched (e.g. a monorepo change spanning the whole
  tree, or a genuinely cross-cutting multi-repo change).

Only **touched** participants get worktreed — never "all or nothing" by default. Some
participants may never need a worktree at all (a docs-only sibling repo, for
instance). When work spans more than one participant, record any cross-repo
branch-naming convention that keeps them coordinated (e.g. the same branch name used
in each touched repo, so related worktrees are easy to find and merge together).

### Axis 3 — Infra strategy (only meaningful when Axis 1 resolves to Tier 2)

If Tier 2 applies, which strategy isolates the environment:

- **Clone full infra** — a separate DB instance/container, a separate compose
  project + network. Strongest isolation, heaviest cost (a full second stack).
- **Clone partial infra** — same DB server, a new DB via template-clone, same
  network, new ports only. Cheaper than full clone; the common middle ground.
- **Share with logical partitioning** — a separate schema/tenant in the same DB.
  Cheapest, but the weakest guarantee (still one DB server, one set of connections
  competing for the same resources).
- **Not yet available** — no isolation mechanism exists yet for this project. Record
  exactly what's missing (e.g. "no template-clone script; compose file hardcodes
  `container_name`"). Do **not** build the isolation mechanism as part of recording
  this axis — that is a separate, project-scoped follow-up, not something `bootstrap`
  or `suggest` do.

### Axis 4 — Lifecycle & cleanup

- **Ephemeral** — spin up, run, auto-teardown (e.g. a CI/e2e-style recipe). Right for
  short, self-contained runs.
- **Persistent** — iterate for hours or days, explicit teardown on exit. Right for a
  dev worktree someone is actively working in.
- **Concrete cleanup steps** for a Tier-2 worktree closing out: drop the isolated DB,
  stop/remove the isolated compose project/containers/network, **never** touch shared
  named volumes, free the allocated port offset, and decide whether the worktree
  directory itself is kept (resuming later) or removed.
- **Deterministic port/offset allocation rule** for N concurrent worktrees — not just
  "offset by index." Record how collisions are avoided **across sessions** (e.g. a
  registry file tracking which offsets are currently claimed, or a convention tied to
  a stable per-worktree identifier rather than an ephemeral launch order).

---

## These are axes, not a single choice

A real task's answer is a **tuple** across all four axes, never a single letter grade
— for example: "Tier 2, scope = backend + frontend only, infra strategy = clone
partial, lifecycle = persistent." Never collapse this into "case A/B/C"; each axis is
a genuinely separate decision, and the interview (and `suggest`) must resolve each one
on its own.

## Cross-cutting concern: unversioned infra wrappers

Not a fifth axis, but worth a note: orchestration/wrapper files (a root
`docker-compose.yml`, a `dev.sh`) that are **not versioned by any participant repo**
are themselves sometimes the thing being changed — a task might be "add a service to
the compose file" rather than "change application code." This is a rare but real case
the interview should ask about (who owns the wrapper file, and does *it* need a
worktree of its own), without the taxonomy needing to model it as a full axis.
