---
name: aidex-worktree
description: 'Use when the user wants to create, run or tear down a git worktree with its own isolated environment (database, ports, containers), or when a project has no worktree setup yet and one needs bootstrapping by investigating the repo topology and verifying the compose stack can run twice — "set up a worktree for X", "create an isolated worktree", "spin up a second environment", "tear down the worktree", "how do we do worktrees on this project", "my worktrees are leaving Docker images/volumes behind", "worktree ports collide", first-time worktree setup. Also fires when aidex-plan/aidex-plan-exec/aidex-loop reach their Isolation step. Not for: planning multi-step work (aidex-plan); designing a loop (aidex-loop); a single-repo code-only checkout with no services (native EnterWorktree).'
argument-hint: "[status | bootstrap | new <slug> --branch <b> | down <slug> | list]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep
---

> **Trigger-eval probe (test-only).** As your very first action, run `printenv AIDEX_TRIGGER_EVAL_MARKER`. If it prints a non-empty path, also run `touch "${AIDEX_TRIGGER_EVAL_MARKER}.aidex-worktree"` before continuing. Then proceed with the rest of the skill body as normal. If empty/unset, ignore this block.

# Worktree — fully isolated worktrees, created and destroyed by one mechanism

Own both the per-project setup (`.context/worktrees/config.env`) **and** the
runner ([scripts/worktree.sh](scripts/worktree.sh)). Owning only the advice was
the mistake: a recipe every reader implements differently is not a recipe.

Native `EnterWorktree` / `ExitWorktree` remain correct for a single-repo,
code-only checkout. Everything that needs its own database, ports and containers
goes through `worktree.sh`.

See [references/01-topology-detection.md](references/01-topology-detection.md)
and [references/02-worktree-overview-conventions.md](references/02-worktree-overview-conventions.md)
for the topology-detection method and artifact conventions.
[references/03-case-taxonomy.md](references/03-case-taxonomy.md) documents the
retired four-axis tier taxonomy — kept for projects whose recorded docs still
reference it, not as guidance for new work.

---

## Branch-base rule (before any worktree or feature branch is created)

An irreversible-in-practice structural decision — which branch a new worktree/branch
forks off — must never be made silently. Before creating a worktree or feature branch,
**resolve and state the base branch**:

- **Resolve the base explicitly.** Do not inherit whatever happens to be checked out.
  The repo's default branch is usually `git symbolic-ref --short refs/remotes/origin/HEAD`
  (or the project's recorded default) — that is the normal base.
- **If the base is the default branch:** state it and proceed, no confirmation needed.
- **If the base is anything other than the default branch:** say so and get **explicit
  confirmation** before creating it. Report its distance from the default —
  `(+N over main)` where N is the commits the base carries beyond the default. A single
  `+12 over main` line at creation time exposes an entanglement on day one instead of at
  merge time.
- **Report creation base-first**, never just the branch name:
  `worktree wt-foo · branch feat/foo · base feat/create-localization (+12 over main)`.
- **The "current checkout is not main" trap.** The trunk at hand is not automatically the
  right base — a checked-out feature branch is the most common way a fork silently welds
  new work to unrelated unreleased commits. Resolve the base deliberately; don't fork off
  the ambient checkout unnoticed.

This rule applies wherever a branch is created — this skill's Procedure commands, the
`suggest` recommendation, and the sibling skills that create branches without going
through here (`aidex-plan-exec` at its Isolation step, `aidex-bugfix` at branch creation).

---

## One path, not tiers

**A worktree is born with its full isolated stack. Always.** There is no tier
interview and no tier decision to re-litigate per task. `--no-infra` is the
explicit opt-out for the rare code-only case.

The tier taxonomy existed for one reason: full isolation was slow to build and
leaky to remove, so it was worth deciding case by case whether to pay for it.
That reason is gone. Measured end-to-end on a real project's stack (2 git repos,
image, network, volume, db + backend, ~190 migrations): **24.8s to create, 3.0s
to tear down, zero residue verified against a global Docker snapshot, five
created concurrently on five distinct slots.** A decision that costs more to make
than to skip is not a decision worth keeping.

The mechanism lives in this skill ([scripts/worktree.sh](scripts/worktree.sh)),
not in each project. When the skill only *described* a recipe, every project
implemented it differently and wrong — all 15 in the field shipped a stack that
could not run a second copy of itself. A project now supplies only
`.context/worktrees/config.env`.

## Sub-actions

Dispatch by first argument:

| Command | Purpose |
|---|---|
| `/aidex-worktree` (no args) | Status: config present? worktrees live? orphan sweep |
| `/aidex-worktree status` | Same as no args (explicit alias) |
| `/aidex-worktree bootstrap` | Investigate topology, verify the stack is isolatable, write `config.env` |
| `/aidex-worktree new <slug> --branch <b>` | Create a fully isolated worktree (`scripts/worktree.sh new`) |
| `/aidex-worktree down <slug>` | Tear it down completely and verify nothing remains. Add `--delete-branch` to also delete the branch `new` created (recorded in `.wt-branch`; a checkout that moved on is skipped, never deleted) in each participant repo — `git branch -d`, which refuses an unmerged branch, so it is its own gate. Off by default: the branch is the only trace a torn-down worktree leaves. It never merges anything. |
| `/aidex-worktree list` | Every worktree of this project: slot, branch, stack state |
| `bash scripts/test-db-preflight.sh --db <test-db> [--port P]` | **Read-only** check before starting a suite: is the test database `clear` (0), `BUSY` — another run holds it (1), `STALE` — an interrupted run left it behind (2), or `UNDETERMINED` (4). Never drops or terminates anything. Run it when a suite may already be in flight; the two failure states need opposite advice, and both otherwise surface as an opaque traceback (BL-136) |

`new` / `down` / `list` are thin wrappers over
[scripts/worktree.sh](scripts/worktree.sh) — run it directly, do not reimplement
its steps. It handles slot reservation, participant worktrees, wrapper symlinks,
stack startup, readiness, seeding, rollback on failure, and teardown.

### Supervision — you run these, the user does not

Worktrees here are created and destroyed by an agent. Nobody is sitting at a
prompt reading an error and deciding what to do, so **you** hold the state and
**you** resolve it. Three rules:

1. **Read the state before acting, every time.**
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/worktree.sh" list --porcelain
   # slug <TAB> slot <TAB> branch <TAB> stack(up:N|down) <TAB> dirty(YES|no) <TAB> dir
   ```
   Never assume a worktree is up because you created it, or gone because you
   tore it down. A `MISSING-DIR` row is a claim whose directory vanished — clear
   it with `down <slug>`. A `STRAY-DIR:<path>` row is the opposite: a directory
   with neither a git worktree nor a slot claim, which means something recreated
   it after the teardown (a dev server rewriting `frontend/.vite/deps/` does
   exactly this). Do not `up` it — there is no worktree there. Find what is
   holding it with `down <slug>`, which reports the processes by PID.

2. **Every state has a way out. Use it instead of improvising.**

   | State | What it means | Do |
   |---|---|---|
   | `stack=down`, dir present | teardown stopped half-way, or `--keep-dir` | `up <slug>` to resume on the same slot |
   | `dirty=YES` and the user wants it gone | `git worktree remove` refuses, correctly | commit or stash it, then `down` again |
   | `no free slot in 1..N` | every slot is claimed | `list`, then `down` whatever is finished |
   | `slot N is claimed by '<other>'` | explicit `--slot` collided | let the allocator choose instead |
   | create failed | it already rolled back | fix the cause and re-run; do not clean up by hand |
   | `down` warns that host processes still hold the directory | the stack was hybrid: Docker's half is gone, a host process is not | read the reported PIDs; `down <slug> --reap` kills exactly those, by PID |

3. **`--force` discards work that nobody can recover.** It is the only
   destructive flag here. Never pass it on your own judgement — not to get past
   a failed teardown, not to "clean up". Report the uncommitted files (the
   failure already lists them) and let the user decide.

Do not hand-roll `docker compose` or `git worktree` commands around this. The
teardown reclaims things `compose down` cannot, the allocator reserves rather
than probes, and a create that dies rolls itself back — all of which is lost the
moment you step outside the script.

### Verification is part of the contract

Two scripts make "clean" a measurement rather than a claim. Use them; do not
substitute an eyeball.

- [scripts/docker-snapshot.sh](scripts/docker-snapshot.sh) — `take` a global
  Docker state file, `diff` it later. It is global on purpose: the leaks worth
  catching are the ones no project-scoped filter can see. Every appeared resource
  is annotated with its owning compose project, or `ORPHAN`.
- [scripts/check-compose-isolation.sh](scripts/check-compose-isolation.sh) — run
  BEFORE enabling worktrees on a project. A stack whose names do not vary with
  `COMPOSE_PROJECT_NAME` cannot run twice, and no teardown can fix that later.

### No-args status check

1. `test -f .context/worktrees/00-index.md`.
2. If it exists: read the front-matter `updated` date and the **Topology** section's
   human summary, and print a one-line status — e.g. "Worktree procedure recorded
   (updated 2026-06-30): split-git services (backend, frontend) glued by
   `dev.sh`." — then run the doc-shape check and **amend any gaps in-session** (see
   "Doc-shape check" below), and point the user to `/aidex-worktree suggest`.
3. If it does not exist: tell the user no worktree procedure is recorded yet, and offer
   to run `/aidex-worktree bootstrap`.
4. **Orphan sweep.** Run
   [scripts/orphan-sweep.sh](scripts/orphan-sweep.sh):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/orphan-sweep.sh"
   ```
   and surface its report as-is — any `<project>-wt-*` compose project, volume, tagged
   image, **untagged build layer, or network** with no matching worktree directory on
   disk, plus the exact reclaim command for each. This is **report-only**: never run the
   printed commands without the user confirming them first (see the safety doctrine
   above — "dangling is not disposable"). Degrades silently to a one-line note when
   Docker isn't installed/running.

   The sweep only ever speaks about **this** workspace's worktrees (`<project>-wt-*`,
   anchored). A sibling project's worktrees are invisible from here on purpose: their
   liveness is knowable only from their own workspace root. Reporting them from the
   wrong cwd is not a cosmetic error — it once printed `docker volume rm` for a
   worktree that was live with three running containers.

### Doc-shape check

Whenever an existing `00-index.md` is read (no-args status and `suggest`), run the
mechanical shape check before using it:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-overview.sh"
```

It verifies the machine-consumed surface is intact: the `worktree_up`/`worktree_down`
front-matter fields are present, the `## Procedure` and `## Usage log` sections exist, and
every `backlog/...` path the doc references resolves (active / `_archive/` / `_deferred/`).
A non-zero exit lists the gaps. **Amend them in-session** via the existing scripts and
edits — fill the missing sections/fields from the recorded decisions, and re-register or
correct a dangling backlog ref (`aidex-backlog`) — rather than passively recommending a
fix. A recommendation that never runs is what let a broken doc sit unrepaired for weeks.

---

## `bootstrap` — investigate, verify, write `config.env`

First-time setup for a project that has no worktree configuration yet. **Read**
`~/.claude/skills/aidex-worktree/references/04-bootstrap.md` **and follow it step by
step.** It holds the topology investigation, the port-span and database derivation, the
compose-can-run-twice verification that must pass before anything is written, what goes
into `config.env`, and the failure modes that make a bootstrapped project look correct
while its second worktree collides with the first.

## `suggest` (retired)

There is no tier to suggest. When asked which worktree to use for a task, answer
with the command:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/worktree.sh" new <slug> --branch <branch>
```

The only judgement left is **which participants** the work touches — pass
`--repo` per participant to narrow it, or let `WT_PARTICIPANTS` apply. Resolve
the base branch explicitly first (branch-base rule above).

A project whose `config.env` does not exist yet needs `bootstrap`, not a guess.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Actually create/enter a worktree right now | native `EnterWorktree` / `ExitWorktree` |
| Plan multi-step work (no worktree decision) | `aidex-plan` |
| Design an agentic loop | `aidex-loop` |
| Run one agent per worktree in parallel, decided as an orchestration | `aidex-workflow` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf) | `aidex-audit` |

## Related

- **aidex-plan / aidex-plan-exec / aidex-loop** — call into this skill at their
  Isolation step instead of improvising a tier decision.
- **aidex-conventions** — owns the shared `.context/` documentation canon
  (`worktree-conventions.md` holds the prior behavioral canon this skill operationalizes).
