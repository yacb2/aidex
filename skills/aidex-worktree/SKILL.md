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

## Sub-actions

Dispatch by first argument:

| Command | Purpose |
|---|---|
| `/aidex-worktree` (no args) | Check whether `.context/worktrees/00-index.md` exists; if yes print a one-line status + point to `suggest`; if no, offer to run `bootstrap` |
| `/aidex-worktree status` | Same as no args (explicit alias) |
| `/aidex-worktree bootstrap` | Investigate topology + interview + scaffold the doc |
| `/aidex-worktree suggest` | Read the existing doc and recommend Tier 1/2 (which participants, which infra strategy, which cleanup) for the task at hand |

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
3. **Interview — recommend-first, confirm/override.** Before asking anything, check
   two pre-fill sources in order:

   **(a) Family-defaults seed (optional).** If `.context/worktrees/family-defaults.md`
   exists, read it: each front-matter key it carries is the pre-filled answer for its
   axis (see the contract in
   [references/02-worktree-overview-conventions.md](references/02-worktree-overview-conventions.md)
   §Family-defaults seed). State the adoption in one line — "axes tier-2-signals /
   branch-convention / port-family pre-filled by family-defaults (provenance in the
   seed); interviewing only the deltas" — and ask only the axes the seed leaves open.
   Seed values are still recommend-first: the user can override any of them, and the
   override lands in `00-index.md` (never edit the seed — it is owned by whoever
   distributes it). No seed → full interview, exactly as below.

   **(b) Calling artifact.** If this
   bootstrap was reached from a calling artifact (an `aidex-plan`/`aidex-plan-exec`/
   `aidex-loop` Isolation step, a backlog item, an audit finding), read that artifact
   and pre-resolve every axis it already answers — which participants the work touches,
   whether it runs migrations / needs the stack live, ephemeral vs persistent — the
   same no-re-ask rule as `suggest` step 3. Only the axes the artifact leaves open get
   a question.

   Then walk the remaining axes below **one question at a time** (`AskUserQuestion`),
   each **leading with your recommendation and its rationale** as the first,
   "(Recommended)"-marked option. The recommendation is derived from the detected
   topology, the orchestration files just read, and the triggering task, and must cite
   those facts ("`test-e2e.sh` already clones the DB by template → clone-partial is
   the natural Tier-2 strategy") — never generic worktree advice. Do not flatten the
   axes into a single "case A/B/C" question — each axis is a genuinely separate
   decision. If the user is unsure ("don't know yet"), record your conservative
   default and mark that axis **"assumed — revisit"** in the doc instead of blocking
   or silently canonizing a guess; the same marker goes on any convention inferred
   from a single observation without asking (e.g. a branch-naming rule read off the
   repos' current state). Full detail on each axis lives in
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

     **Before recording any Tier-2 strategy, run the creation-time check.** For a
     compose-based project:
     ```bash
     bash "${CLAUDE_SKILL_DIR}/scripts/check-compose-isolation.sh" [compose-file]
     ```
     It renders the file twice under different project names and reports every name
     that does **not** vary: an image pinned to the main project, a fixed
     `container_name`, a literal host port, a explicitly-named volume two stacks would
     share. Each is unfixable after the fact — a second stack has already collided
     with, or borrowed from, the main tree. Surface the findings and fold them into the
     recorded strategy; do not record Tier 2 as available over a stack that fails this.
     Field-verified: run against a real project it reproduced that project's own
     independently-filed isolation bug and found two residuals the fix had missed.

     **Ask the image question, not just the strategy question.** How a Tier-2 stack
     names and builds its images is decided at *creation*, and it determines both how
     fast a worktree comes up and whether its storage is ever reclaimable. Getting it
     wrong is not self-correcting — no teardown can fix an image that was named wrong.
     Three rules, each learned from a real failure:

     1. **Every service that must share one runtime environment needs an explicit,
        project-derived tag — a shared `build:` block is NOT enough.** Compose names a
        built image `<project>-<service>`, so two services pointing at the same build
        context still produce two separately-resolved images. Record the form:
        ```yaml
        image: ${COMPOSE_PROJECT_NAME:-<main-project>}-<service>
        ```
        With `COMPOSE_PROJECT_NAME` unset the main tree stays byte-identical; inside a
        worktree project every service lands on that project's single image.
     2. **Never hardcode another project's image name** (`image: <main-project>-backend:latest`).
        In a worktree project it makes one service start from the *main tree's* image
        while its siblings build their own — the exact divergence the shared tag exists
        to prevent — and adds a silent dependency on the main tree having been built at
        all. Field case: a separately-resolved second build produced a divergent torch
        resolution that broke `silero_vad` on import.
     3. **A per-worktree build is not merely slow, it anchors storage.** Steps like
        `RUN apt-get update` are not reproducible, so any cache miss mints a whole new
        multi-GB dependency generation, and *every surviving image keeps its generation
        alive*. Measured on a real workspace: two images belonging to worktrees that no
        longer existed held 4.1GB of otherwise-reclaimable layers. This is why rule 1 of
        the naming contract (`-wt-` infix) is a storage rule, not a cosmetic one — an
        unattributable image is one nobody can ever decide to delete.

     **The reuse lever, and its mandatory guard.** When the source is bind-mounted
     (`- ./backend:/app`), the image supplies only the dependency layer and the
     worktree's code arrives through the mount — so a worktree whose branch does not
     change dependencies does not need its own image at all. Expose that as an
     *override with a project-derived default*, never as a hardcoded name (rule 2):
     ```yaml
     image: ${SERVICE_IMAGE:-${COMPOSE_PROJECT_NAME:-<main-project>}-<service>}
     ```
     `worktree_up` exports `SERVICE_IMAGE=<main-project>-<service>` **only** when the
     branch leaves the image inputs untouched; otherwise it leaves it unset and the
     project builds its own, preserving rule 1. The guard is not optional — a branch
     that changes deps and reuses a stale image fails silently, which is worse than
     building:
     ```bash
     # non-empty => this branch changes the image; must build its own
     git diff --name-only <base>...HEAD -- <dockerfile-path> <deps-manifest>
     ```
     When the source is **baked in** with no mount, every worktree must build; record
     that and note `cache_from` as the only lever.

     **Judge storage by UNIQUE size, never by the Docker Desktop row.** The UI's
     per-image size counts shared layers in full: a workspace showing 87 images at
     ~3GB each held 37GB of actual unique data. `docker system df -v`'s UNIQUE column
     is the only figure worth acting on — a decision made off the displayed size will
     chase the wrong resource entirely.

   - **Axis 4 — Lifecycle & cleanup.** Ephemeral (spin up -> run -> auto-teardown) or
     persistent (iterate for hours/days -> explicit teardown on exit)? What exactly
     must be cleaned up when a Tier-2 worktree closes: isolated DB dropped, isolated
     compose project/containers/network stopped, images built for the worktree removed
     (`--rmi local`), anonymous volumes reclaimed (**never** shared named volumes),
     allocated port offset freed, worktree directory kept or removed. If N worktrees
     can run at once, what is the concrete, deterministic port/offset allocation rule
     (not just "offset by index" — how are collisions between concurrent sessions
     avoided)? Adopt the naming/teardown contract for Tier 2 —
     `COMPOSE_PROJECT_NAME=<project>-wt-<slug>` and
     `worktree_down: docker compose -p <project>-wt-<slug> down -v --rmi local
     --remove-orphans` — as `worktree_down`'s value, unless the project has a
     documented reason to deviate; the `-wt-` infix is what makes `orphan-sweep.sh`
     (below) able to tell a worktree's Docker resources apart from everything else.

     **`compose down` alone is not a complete teardown — it has two blind spots, and
     both were field-measured on a real workspace (2026-07-25: 15GB reclaimable, 24%
     of all image storage, plus a network orphaned for two days).** A `worktree_down`
     that stops at `compose down` looks clean and is not. Every Tier-2 teardown must
     also:

     1. **Reclaim the worktree's untagged build layers.** `--rmi local` removes only
        images the compose file *currently references by their default tag*. Each
        rebuild of a service orphans the previous image as `<none>` — a 3GB layer set
        per E2E run — and no `compose` verb ever revisits them. They stay attributable
        because compose stamps `com.docker.compose.project` on the image itself, so the
        reclaim can be scoped to exactly this worktree and nothing else:
        ```bash
        DANGLING="$(docker images -f dangling=true \
          -f "label=com.docker.compose.project=$PROJECT" -q)"
        [[ -n "$DANGLING" ]] && docker rmi $DANGLING
        ```
        Enumerate-then-`rmi`, never a bare `prune`: the label filter is what proves
        nothing outside `$PROJECT` can be reached, and a prune whose filter silently
        fails to match still deletes.
     2. **Verify, don't assume.** Finish by re-running the attribution pre-flight
        (`orphan-sweep.sh --slug <slug>`) and reporting whatever survived. `compose
        down` exits 0 while leaving the project network behind whenever a container
        from another stack was attached to it — a zero exit code is not evidence of a
        clean namespace.

     **Teardown is coupled to directory removal, not suggested next to it.**
     `worktree-multi.sh remove` runs the recorded `worktree_down` *before* deleting the
     worktree directory, and refuses if resources exist with no `worktree_down`
     recorded. Order is load-bearing: once the directory is gone, nothing can tell a
     dead worktree's Docker resources from a live one's, and they become permanent.
     Never document teardown as a separate step the user is trusted to remember —
     that is precisely the step that got skipped in the field.
     **Safety doctrine: "dangling is not disposable."** A dev DB volume whose
     containers were removed by `compose down` still holds real data — never
     `docker volume prune -a`/`--all`. Permitted reclaim verbs: anonymous-volume
     prune (`docker volume prune -f`) and an explicit `docker volume rm <name>` for a
     named volume taken from a sweep report the user confirmed. Full doctrine in
     `aidex-conventions/references/worktree-conventions.md`.

4. **Scaffold.** Run
   [scripts/new-worktree-overview.sh](scripts/new-worktree-overview.sh):
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/new-worktree-overview.sh"
   ```
   then fill every section of the generated `.context/worktrees/00-index.md` from the
   interview answers. Leave nothing as a placeholder.

5. **Fill the Procedure section with exact commands, not prose.** This is the step
   that makes later runs progressively simpler — decisions alone are not executable.
   From the detected topology, write the verbatim Tier-1 create/teardown commands
   (for split-git topologies use
   [scripts/worktree-multi.sh](scripts/worktree-multi.sh) — one worktree per touched
   participant plus wrapper symlinks; native `EnterWorktree` alone only covers the
   single-repo case), and set the front-matter `worktree_up`/`worktree_down` fields
   if the project already has a Tier-2 mechanism. If not, leave `""` and cite the
   project's pending backlog item — **registering one via `aidex-backlog` (its
   `scripts/register-item.sh`, non-interactive flags) in that project if none exists
   yet**; a prose mention ("BL-XXX-style follow-up") is not a registration, and a
   hand-written entry gets the front-matter wrong — use the script. Executors read the front-matter fields and the Procedure
   section — they never re-derive the recipe.

## suggest

Recommend a tier for the **current task**, grounded entirely in this project's own
recorded doc — never re-derive a generic recipe.

1. **Require the doc.** `test -f .context/worktrees/00-index.md`. If it does not exist,
   say so plainly and point to `/aidex-worktree bootstrap` — never invent a topology or
   guess a tier for a project that hasn't recorded one. If it does exist, run the
   **doc-shape check** (above) and amend any gaps in-session before recommending.
2. **Read the doc's four axis sections plus Procedure.** Load **Participants &
   scope**, **Tier decision**, **Tier 2 infra strategy**, and **Lifecycle & cleanup**
   — the four axes from
   [references/03-case-taxonomy.md](references/03-case-taxonomy.md) — plus the
   **Procedure** section and the `worktree_up`/`worktree_down` front-matter fields.
   Do not read only the front-matter; the recommendation is built from the body.
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
   all) need a worktree; the **exact create/teardown commands from the doc's Procedure
   section** (and `worktree_up`/`worktree_down` for Tier 2) — quoting the project's own
   recorded procedure text verbatim, never a generic recipe. If the
   doc records Tier 2 as "not yet available" for this case, say so and fall back to
   Tier 1 (or Tier 0) instead of inventing an isolation mechanism. If the doc predates
   the Procedure section, **amend it in-session** (fill Procedure + front-matter fields
   from the recorded decisions) rather than improvising or only recommending it.
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
