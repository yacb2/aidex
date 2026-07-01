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
