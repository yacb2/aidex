# Worktree-overview Conventions

The `.context/worktrees/00-index.md` artifact written by `aidex-worktree`'s
`bootstrap`. Follows the shared `.context/` canon
(`aidex-conventions/references/00-global.md`); only the worktree-specific rules are
declared here.

---

## Location & naming

- **One file per project**, not one per topic: `.context/worktrees/00-index.md`. This
  mirrors the "single evergreen file" pattern for project-wide procedure docs — split
  into `NN-<slug>.md` siblings only if the doc genuinely outgrows one file, using the
  same "when to split" rule as any other reference (a section becomes its own file
  when it needs independent lifecycle or gets too large to review as one unit).
- No date in the filename — this is not a dated record like a plan or a decision; it
  is a living, single-per-project overview.

## The agent's own context is not isolated the same way the stack is

Isolation here is defined over ports, database and containers. The *session* that drives
the worktree has a second environment nobody declared, and the two placements differ —
measured 2026-07-26:

| Placement | Where | `<project>/.claude/` + `CLAUDE.md` |
|---|---|---|
| native `EnterWorktree` | `<project>/.claude/worktrees/<name>` — **inside** the repo | **apply** (verified: a project `skillOverrides` entry still blocked its skill from inside the worktree) |
| `worktree.sh` | `<project>/../<project>-wt-<slug>` — a **sibling of** the repo | **do not apply** |

`worktree.sh` places worktrees outside the project root by design, so the upward search
for project settings never passes through it. The mechanism mirrors nothing of the sort
either: `.claude` and `CLAUDE.md` appear **zero** times across `worktree.sh` and the
shipped profiles.

**When this bites, and when it does not.** Only when those paths are gitignored — then the
checkout does not carry them and the walk cannot reach them, so an agent driving the
worktree silently loses the project's `skillOverrides`, permissions and conventions while
believing it is working on the same project. A project that commits `.claude/` and
`CLAUDE.md` is unaffected: the checkout brings them.

**Fix, where it applies:** list them in `WT_LINKS`. This is precisely that field's
category — unversioned root paths a fresh checkout would lack. Worth stating in the
project's overview either way, so the next reader knows which of the two cases they are in.

## Front-matter

```yaml
title: "Worktree procedure — <project>"
status: doing          # base lifecycle: open | doing | done | dropped
created: YYYY-MM-DD
updated: YYYY-MM-DD
version: 1.0.0
```

- `status` uses the shared base vocabulary — typically `doing` once bootstrapped
  (there is always more to refine as the project's topology or infra evolves) or
  `done` once the team considers the procedure stable.
- `version` bumps on a material change to the recorded decision (e.g. adding a new
  participant, changing infra strategy) — not on typo fixes.

## Required body sections

In order: **Topology · Participants & scope · Tier decision · Tier 2 infra strategy ·
Lifecycle & cleanup · Open questions** — the four-axis structure from
[03-case-taxonomy.md](03-case-taxonomy.md), bracketed by the raw topology facts and any
unresolved questions the interview flagged.

- **Topology** — the raw facts from `scripts/detect-topology.sh` plus the human
  summary (single-repo monorepo / split-git services + unversioned wrapper / classic
  multi-repo / a hybrid actually observed). Never assumed — always detected
  per-project (see [01-topology-detection.md](01-topology-detection.md)).
- **Participants & scope** — Axis 2: which directories/repos participate in worktree
  work at all, and the cross-repo branch-naming convention (if any) that keeps
  coordinated work together.
- **Tier decision** — Axis 1: the concrete, project-specific signal distinguishing
  Tier 0/1/2.
- **Tier 2 infra strategy** — Axis 3: which strategy applies (clone full, clone
  partial, share with logical partitioning, or not yet available), only meaningful
  when Tier 2 is reachable.
- **Lifecycle & cleanup** — Axis 4: ephemeral vs persistent, the concrete cleanup
  steps, and the deterministic port/offset allocation rule for N concurrent
  worktrees.
- **Open questions** — anything the interview left unresolved; not a placeholder
  section to skip.

Leave nothing as a template placeholder — every section is filled from the topology
detection + interview answers before the doc is considered scaffolded.

## Evergreen vs task-scoped content (prune rule)

This doc is **evergreen** — it records the project's standing procedure, not the state of
any one run. Task-scoped facts — the branches currently in flight, the tier a specific
task chose, the analysis of today's work — live in the **triggering artifact** (the plan,
loop-spec, backlog item, or audit that prompted the run), **never** in the overview. When
they leak in, the doc drifts and can end up contradicting its own body.

- The **Usage log** holds only the distilled one-liner per run (date · tier · participants
  · collisions observed) and codified patterns promoted from it — not a task's working
  notes.
- **Open questions** is not a scratchpad for a run's in-flight doubts. At teardown, the
  run **prunes** the entries it resolved: delete the Open-questions lines the run answered
  (the answer belongs in the section it settled, or in the triggering artifact), leaving
  only questions still genuinely open. `aidex-plan-exec` does this symmetrically with its
  Usage-log append at teardown.

## Family-defaults seed (optional)

Projects born from a shared template often share constant axis answers (the same
tier-2 signals, branch convention, port-family scheme, worktree recipes). Re-deriving
those through a full interview per project wastes the interview on constants and lets
the shared parts drift apart. The seed is the **generic** fix — a data contract, not a
family registry:

```
.context/worktrees/family-defaults.md   # optional; any provenance
```

```markdown
---
tier2_signals: "test-e2e.sh clones the DB by template; COMPOSE_PROJECT_NAME isolation"
branch_convention: "feat/<slug> off main"
port_family: "dev +10 e2e, +20 worktrees"
worktree_up: "./worktree-up.sh"        # optional recipe defaults
worktree_down: "./worktree-down.sh"
---
Free prose: family provenance, sync mechanism, rationale.
```

Rules of the contract:

- **Every front-matter key is optional**; each one present is the pre-filled answer
  for its axis. Bootstrap adopts them as stated recommendations, declares the adoption
  in one line, and interviews **only the axes the seed leaves open** (participants and
  other genuinely per-project judgments are never seeded).
- **Provenance-agnostic.** The seed may come from a project template's sync mechanism,
  an org-wide scaffold, or be written by hand — this skill neither knows nor cares.
  aidex **never writes or edits the seed**; it is owned by whoever distributes it.
  User overrides land in `00-index.md`, annotated `(overrides family-defaults)`.
- **The seed does not replace the overview.** Bootstrap still scaffolds the full
  `00-index.md`; seed-sourced values are recorded there with a `(family-defaults)`
  provenance marker so `suggest` keeps reading one doc.
- Absent seed → nothing changes: full recommend-first interview.

## Lifecycle

- **No archive — versioned in place.** Unlike plans or loop-specs, this doc does not
  move to an `_archive/` folder when superseded — it is the project's single
  evergreen worktree procedure. Supersession happens via a labeled in-place note (per
  `00-global.md` §5: bump `version`, update `updated`, and note what changed and why
  directly in the relevant section) rather than by creating a new file or archiving
  the old one.
- `status` moves `doing` -> `done` as the procedure stabilizes, and can move back to
  `doing` if the project's topology or infra strategy changes materially enough to
  need re-interviewing.

## Relationship to other artifacts

- **Consumed by `aidex-plan` / `aidex-plan-exec` / `aidex-loop`'s Isolation step** —
  each of those calls `aidex-worktree suggest` to resolve the tier for the work at
  hand instead of re-deriving a generic recipe inline.
- **Never hand-copied between projects.** Each project's facts (topology, infra
  strategy, cleanup steps) are its own — a doc from one project is not a template for
  another; `bootstrap`'s interview must run per project, even ones that look similar
  on the surface.
- **`aidex-conventions/references/worktree-conventions.md`** holds the shared
  *behavioral* canon (when to isolate, the two-tier heuristic) that this artifact
  operationalizes into project-specific facts; this doc is the record, that one is
  the doctrine.
