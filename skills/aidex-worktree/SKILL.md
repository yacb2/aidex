---
name: aidex-worktree
description: Use when the user wants to set up a git worktree for parallel work and needs to decide whether to isolate the environment (database, ports, containers) or share it, or when a project has no worktree procedure yet and one needs to be bootstrapped by investigating the repo's topology and interviewing the user — "set up a worktree for X", "should this run isolated or share the dev DB", "how do we do worktrees on this project", first-time worktree setup. Also fires when aidex-plan/aidex-plan-exec/aidex-loop reach their Isolation step and no `.context/worktrees/00-index.md` exists yet. Not for: actually creating the worktree directory (native EnterWorktree/ExitWorktree); planning multi-step work (aidex-plan); designing a loop (aidex-loop).
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
| `/aidex-worktree down <slug>` | Tear it down completely and verify nothing remains |
| `/aidex-worktree list` | Every worktree of this project: slot, branch, stack state |

`new` / `down` / `list` are thin wrappers over
[scripts/worktree.sh](scripts/worktree.sh) — run it directly, do not reimplement
its steps. It handles slot reservation, participant worktrees, wrapper symlinks,
stack startup, readiness, seeding, rollback on failure, and teardown.

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

The output is a machine-readable `.context/worktrees/config.env`, not a prose
recipe. Prose is what let 15 projects each implement isolation differently.

1. **Detect existing config.** If `.context/worktrees/config.env` exists, do not
   overwrite it — show it and stop. Amend it in place if something is wrong.

2. **Investigate topology.** Run
   [scripts/detect-topology.sh](scripts/detect-topology.sh) and describe what it
   actually found in plain language. Never assume monorepo or any prior default.

3. **Verify the stack can be isolated AT ALL.** Run
   [scripts/check-compose-isolation.sh](scripts/check-compose-isolation.sh).
   Every finding is a blocker, not a warning — each one is a name that will not
   vary between two stacks:
   - an image pinned to the main project, or one that resolves identically in
     both renders
   - a `container_name` that does not carry a suffix variable
   - a literal host port
   - a named volume that both projects would share

   **Fix these before writing a config**, in the form that keeps the main tree
   byte-identical when the variables are unset:
   ```yaml
   image: ${COMPOSE_PROJECT_NAME:-<main-project>}-<service>
   container_name: <name>${WT_SUFFIX:-}
   ports: ["${SOME_PORT:-<dev-default>}:<container-port>"]
   ```
   Services meant to run the SAME environment must share ONE explicit tag — a
   shared `build:` block is not enough, compose derives a per-service name from
   it. A service pinning the main project's image by name is the specific defect
   that made one service start from the main tree's image while its siblings
   built their own.

4. **Start from the family profile when one fits.** For the Django + Vue +
   Compose family, copy
   [assets/profiles/django-vue-compose.env](assets/profiles/django-vue-compose.env)
   and fill only its three `PROJECT` lines. Do not re-derive from a blank page
   what a validated profile already answers.

5. **Interview only what the profile leaves open** (`AskUserQuestion`, one
   question at a time, each leading with a recommendation grounded in what
   step 2 and 3 actually found):
   - **Participants** — which repos can take part. Some never need one.
   - **Wrapper links** — the unversioned root files a fresh checkout of a single
     participant would lack (compose file, dev scripts, Dockerfile context,
     gitignored `.env`). Relative paths are mirrored, so `backend/.env` lands at
     `<worktree>/backend/.env`.
   - **Port band** — a free 4-digit band for this project. Two rules, both
     enforced by `worktree.sh` at startup rather than left to care: the stride
     must EXCEED the span between the lowest and highest base, and the bases
     belong in a narrow window with the stride separating slots. Bases spread
     across 210 with a stride of 100 put slot 1's DB port on dev's backend port —
     a structural fault that merely looked like a busy slot, because the
     allocator skipped past it.
   - **Services, readiness, seed** — which services the stack starts, the command
     that proves it is ready, and how data arrives. Prefer migrations over a dump
     of dev: schema-only is seconds and does not couple every worktree to
     whatever dev happens to hold.

6. **Prove it before recording it.** Create a throwaway worktree, confirm the
   stack answers, tear it down, and show `docker-snapshot.sh diff` reporting
   ZERO RESIDUE. A config that has never completed a cycle is a guess.

7. **Record the human-facing overview** at `.context/worktrees/00-index.md`
   (topology, participants, port band, the one-line commands). It documents;
   `config.env` decides.

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
| Audit the Claude Code ecosystem | `aidex` |
| Audit project state (UX/security/perf) | `aidex-audit` |

## Related

- **aidex-plan / aidex-plan-exec / aidex-loop** — call into this skill at their
  Isolation step instead of improvising a tier decision.
- **aidex-conventions** — owns the shared `.context/` documentation canon
  (`worktree-conventions.md` holds the prior behavioral canon this skill operationalizes).
