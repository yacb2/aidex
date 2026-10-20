---
name: worktree
description: 'Use when the user wants to create, run or tear down a git worktree with its own isolated environment (database, ports, containers), or when a project has no worktree setup yet and one needs bootstrapping by investigating the repo topology and verifying the compose stack can run twice — "set up a worktree for X", "create an isolated worktree", "spin up a second environment", "tear down the worktree", "how do we do worktrees on this project", "my worktrees are leaving Docker images/volumes behind", "worktree ports collide", first-time worktree setup. Also fires when plan/plan-exec/loop reach their Isolation step. Not for: planning multi-step work (/aidex:plan); designing a loop (/aidex:loop); a single-repo code-only checkout with no services (native EnterWorktree).'
argument-hint: "[status | bootstrap | new <slug> --branch <b> | down <slug> | list]"
disable-model-invocation: false
allowed-tools: Bash Read Write Edit Glob Grep
---

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

This rule applies wherever a branch is created — this skill's Procedure commands and the sibling skills that create branches without going
through here (`plan-exec` at its Isolation step, `bugfix` at branch creation).
To fork from anything but the default branch, pass `worktree.sh new ... --base <commit-ish>`.

---

## One path, not tiers

**A worktree is born with its full isolated stack. Always.** There is no tier
interview and no tier decision to re-litigate per task. `--no-infra` is the
explicit opt-out for the rare code-only case.

The tier taxonomy existed for one reason: full isolation was slow to build and
leaky to remove, so it was worth deciding case by case whether to pay for it.
That reason is gone — the shipped mechanism creates a full stack in seconds and
tears it down leaving no residue. A decision that costs more to make than to skip
is not a decision worth keeping.

The mechanism lives in this skill ([scripts/worktree.sh](scripts/worktree.sh)),
not in each project. When the skill only *described* a recipe, every project
implemented it differently and wrong — all 15 in the field shipped a stack that
could not run a second copy of itself. A project now supplies only
`.context/worktrees/config.env`.

## Sub-actions

Dispatch by first argument:

| Command | Purpose |
|---|---|
| `/aidex:worktree` (no args) | Status: config present? worktrees live? orphan sweep |
| `/aidex:worktree status` | Same as no args (explicit alias) |
| `/aidex:worktree bootstrap` | Investigate topology, verify the stack is isolatable, write `config.env` |
| `/aidex:worktree new <slug> --branch <b> [--base <commit-ish>]` | Create a fully isolated worktree (`scripts/worktree.sh new`). The branch forks from `--base`, else the default branch's tip, never the ambient checkout; the report names it (`base feat/x (+1 over main)`). For per-repo SHAs, pre-create the branches (`git -C <repo> branch <b> <sha>`): an existing branch is used at its own tip, and `--base` with an existing branch is refused |
| `/aidex:worktree down <slug>` | Tear the stack down, keeping any volume that is name-pinned or mounted by another project (`down -v` only when none is, with a `keeping volume` warning otherwise), then verify nothing else attributable remains. Add `--delete-branch` to also delete the branch `new` created (recorded in `.wt-branch`; a checkout that moved on is skipped, never deleted) in each participant repo — `git branch -d`, which refuses an unmerged branch, so it is its own gate. Off by default: the branch is the only trace a torn-down worktree leaves. It never merges anything. |
| `/aidex:worktree list` | Every worktree of this project: slot, branch, stack state |
| `bash "${CLAUDE_SKILL_DIR}/scripts/test-db-preflight.sh" --db <test-db> [--port P]` | **Read-only** check before starting a suite: is the test database `clear` (0), `BUSY` — another run holds it (1), `STALE` — an interrupted run left it behind (2), or `UNDETERMINED` (4). Never drops or terminates anything. Run it when a suite may already be in flight; the two failure states need opposite advice, and both otherwise surface as an opaque traceback |

**Tearing a worktree down is not integrating its branch.** `down` never merges, and
that is deliberate — but the rule belongs where a session that is not running this
skill can see it, which is `skills/conventions/references/autonomy-conventions.md`
§ *Integrating a branch is not a commit* (class 2: pre-authorizable up front, never
assumed mid-run) — a rule stated only inside
`worktree.sh` is invisible to the session that would do the merging. Leave the branch
ready to merge; say so; do not merge it.

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
- [scripts/check-worktree-isolation.sh](scripts/check-worktree-isolation.sh) —
  **the one command.** Runs every isolation check in order and reports them
  together; `--census` does it across every project with a `config.env`. Run this
  once `config.env` is written (bootstrap step 6), before enabling worktrees, and
  again whenever the compose file or a linked script changes. Every finding is a
  blocker, not a warning. Before `config.env` exists, only the compose check below
  can run (bootstrap step 3); the umbrella refuses with "nothing was checked".
  Once the config exists, run the umbrella, not one of the checks below: each is
  correct about the surface it covers, and a defect lives outside whichever one
  you pick.
  - [scripts/check-compose-isolation.sh](scripts/check-compose-isolation.sh) —
    compose addressing. A stack whose names do not vary with
    `COMPOSE_PROJECT_NAME` cannot run twice, and no teardown can fix that later.
  - [scripts/check-worktree-ports.sh](scripts/check-worktree-ports.sh) — host
    ports a linked script can bind, or `kill -9` the holder of. `./dev.sh` in a
    worktree killed dev's Vite and took its port.
  - [scripts/check-worktree-runner.sh](scripts/check-worktree-runner.sh) — test
    harnesses that reach dev's stack when invoked directly instead of through
    the project's own wrapper. That path DROPs dev's E2E database.

### No-args status check

1. `test -f .context/worktrees/config.env` — the file `worktree.sh` actually reads, so
   it alone decides "configured"; then `test -f .context/worktrees/00-index.md`.
2. If `config.env` exists and `00-index.md` exists: read the front-matter `updated` date and the **Topology** section's
   human summary, and print a one-line status — e.g. "Worktree procedure recorded
   (updated 2026-06-30): split-git services (backend, frontend) glued by
   `dev.sh`." — then run the doc-shape check and **amend any gaps in-session** (see
   "Doc-shape check" below), and point the user to `worktree.sh new`. If `config.env`
   exists without `00-index.md`, say it is configured but the overview is missing and
   offer `/aidex:worktree bootstrap` to write it.
3. If `config.env` does not exist: tell the user no worktree procedure is recorded yet
   (whatever `00-index.md` says), and offer to run `/aidex:worktree bootstrap`.
4. **Orphan sweep.** Run
   [scripts/orphan-sweep.sh](scripts/orphan-sweep.sh):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/orphan-sweep.sh"
   ```
   and surface its report as-is — any `<project>-wt-*` compose project, volume, tagged
   image, **untagged build layer, or network** with no matching worktree directory on
   disk, plus the exact reclaim command for each one proven orphaned (a volume, a `LIVE`
   or a `NOT JUDGED` entry carries none; see below). This is **report-only**: never run the
   printed commands without the user confirming them first (see the Docker safety doctrine in
   `conventions/references/worktree-conventions.md` — "dangling is not disposable"). Degrades silently to a one-line note when
   Docker isn't installed/running.

   An untagged layer under a **live** worktree's project is not this skill's to fix:
   `worktree.sh` never rebuilds, so it was orphaned by a rebuild inside a
   `test-e2e.sh` run, and the generated script reclaims it at the end of that run
   (`coverage` contract, BL-372/BL-377). A trail of them behind a live worktree
   means the project's `test-e2e.sh` predates the contract.

   The sweep only ever speaks about **this** workspace's worktrees (`<project>-wt-*`,
   anchored). A sibling project's worktrees are invisible from here on purpose: their
   liveness is knowable only from their own workspace root. Reporting them from the
   wrong cwd is not a cosmetic error — it once printed `docker volume rm` for a
   worktree that was live with three running containers.

### Machine-wide orphan listing (`--all`)

The session-start Docker nudge (`hooks/docker-orphan-nudge.sh`) points only at this
script, by absolute path. Answer it with this listing, never with the no-args status
check above:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/orphan-sweep.sh" --all
```

It lists a compose project — `-wt-` or ad-hoc — as a CANDIDATE ORPHAN only when every
one of its containers carries Docker's `working_dir` label and none of those
directories exists; it never parses a name. It prints the project, its working dirs,
its container count and its volumes (as "attached to", never as removable), and no
removal command. A live worktree moved with a plain `mv` reads as a candidate until its
stack is recreated, so verify by hand with the user before removing anything.

The default sweep of step 4 is not a second opinion on a candidate: it judges liveness
by `$WS_PARENT/$WS_NAME-wt-*` directories, then by the same `working_dir` label, then by
container state, so a worktree moved with a plain `mv` whose stack is stopped (stale
label, nothing running) still gets `down`, `rmi` and `network rm`. A project whose
`working_dir` exists prints `LIVE (working_dir exists)`, one with a running, restarting or
paused container `LIVE (container running)`, one without the label `NOT JUDGED`, its
volumes too. An `ORPHAN compose project` block names its proof, one
`# judged gone: <working_dir> does not exist` line per directory. No volume gets
`volume rm` from this sweep (`--slug`, the attribution pre-flight, keeps it): a moved
worktree with a stopped stack looks identical to a removed one, so a gone project's volume is listed as `ORPHAN volume: <vol>  (verify by hand; ...)` and one
with no container to read as `NOT JUDGED volume:`. The project line is always `down`
without `-v` (under `--slug` too): run from the workspace root, `-p <project> down -v`
would remove the main stack's name:-pinned volume whenever nothing mounts it. A shared
volume or one not named `<project>_*` is named on a `# no -v:` line. When the container
listing failed, even partway, no removal command is printed at all (BL-857). Every `docker rmi` and `docker network rm` line carries a one-line `# ...` reason above it: `# no live worktree or running container for <project>; the image rebuilds from its compose file` (or `...; the network has no endpoints`), and under `--slug`, where containers may still exist, `# belongs to <project> (--slug); ...`. The commands are still only printed, never run.

### Doc-shape check

Whenever an existing `00-index.md` is read (no-args status), run the
mechanical shape check before using it:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-overview.sh"
```

It verifies the machine-consumed surface is intact: the `worktree_up`/`worktree_down`
front-matter fields are present **and non-empty**, the `## Procedure`, `## Usage log`,
`## Running this worktree` and `## Never run here` sections exist, no `## Tier …` section
documents the retired tier mechanism, every script `## Procedure` names actually exists,
and every `backlog/...` path the doc references resolves (active / `_archive/` /
`_deferred/`).
A non-zero exit lists the gaps. **Amend them in-session** via the existing scripts and
edits — fill the missing sections/fields from the recorded decisions, and re-register or
correct a dangling backlog ref (`backlog`) — rather than passively recommending a
fix. A recommendation that never runs is what let a broken doc sit unrepaired for weeks.

---

## `bootstrap` — investigate, verify, write `config.env`

First-time setup for a project that has no worktree configuration yet. **Read**
`${CLAUDE_PLUGIN_ROOT}/skills/worktree/references/04-bootstrap.md` **and follow it step by
step.** It holds the topology investigation, the port-span and database derivation, the
compose-can-run-twice verification that must pass before anything is written, what goes
into `config.env`, and the failure modes that make a bootstrapped project look correct
while its second worktree collides with the first.

## Runner limits

`worktree.sh down` bounds its Docker calls: `AIDEX_DOWN_TIMEOUT` (default 300 s) for
`compose down`, `AIDEX_DOCKER_TIMEOUT` (default 30 s) for the other daemon calls. Each
must be a positive integer, else `down` refuses with exit 2. A call that times out is
reported (`compose down failed (exit 142)`) and the slot claim is kept; re-run
`worktree.sh down <slug>` once the daemon answers.

`WT_MAX_SLOTS` in `config.env` must be an integer in 1..9999 with no leading zero; any
other value makes `new`, `up`, `down` and `list` refuse with exit 2, naming it.

## Boundaries

| The user wants to… | Route to |
|---|---|
| Create a worktree right now (own database, ports or containers) | `worktree.sh new` (this skill); native `EnterWorktree` / `ExitWorktree` only for a single-repo, code-only checkout with no services |
| Plan multi-step work (no worktree decision) | `plan` |
| Design an agentic loop | `loop` |
| Run one agent per worktree in parallel, decided as an orchestration | `workflow` |
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf) | `audit` |

## Related

- **plan / plan-exec / loop** — call into this skill at their
  Isolation step instead of improvising a tier decision.
- **conventions** — owns the shared `.context/` documentation canon
  (`worktree-conventions.md` holds the prior behavioral canon this skill operationalizes).
