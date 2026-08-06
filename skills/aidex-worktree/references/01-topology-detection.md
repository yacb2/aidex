# Topology Detection

How `bootstrap` figures out what a project's git/orchestration topology actually is
before recommending anything. This is a **generic, stack-agnostic** procedure — the
script gathers facts, a person (or the model, interviewing the person) interprets
them into Participants + a topology label. Never the other way around.

---

## What the script automates

[scripts/detect-topology.sh](../scripts/detect-topology.sh) reports plain facts, no
interpretation:

- Whether the project root itself has a `.git` (root-git signal).
- Which immediate subdirectories have their own `.git` (split-git / multi-repo
  signal).
- Orchestration / dev-workflow files at root or one level deep (`docker-compose*.yml`,
  `Dockerfile*`, `Procfile`, `dev.sh`, `test-e2e.sh`, …) — evidence of an unversioned
  wrapper gluing multiple repos together.
- Directories that look like services, by generic signals (`package.json`,
  `pyproject.toml`, `requirements.txt`, `go.mod`, or an own `.git`) — reported, never
  framework-guessed.

The script always exits 0: it is informational and must never block `bootstrap`. It
makes no recommendation and assumes no stack.

## What stays a human judgment call

The script cannot tell you:

- **Which directories are actual participants** in worktree work versus incidental
  (a `docs/` folder with no `.git` and no service signal is not a participant even if
  it exists at root).
- **Whether a found orchestration file (`dev.sh`, `docker-compose.yml`) is itself
  versioned** by any participant repo, or is an unversioned glue layer that belongs to
  no single repo (see the cross-cutting note in
  [03-case-taxonomy.md](03-case-taxonomy.md)).
- **The topology label** that best describes what was found — this is a summary
  written from the facts, never assumed in advance.

The interview turns the raw facts into these judgments; the script's job ends at
reporting them.

## Placement is a fourth axis, and it is not isolated by the other three

Isolation is defined over **database, ports and containers** — the three the interview
sizes. Placement is the axis that decides where the worktree directory lands, and it is
the only one that touches the *agent's* environment rather than the stack's.

`worktree.sh` places worktrees as a **sibling** of the repo
(`<project>/../<project>-wt-<slug>`) so a git worktree never nests inside its own working
tree. That is deliberate and not configurable. Its consequence is what the interview must
surface: the upward search for project settings never passes through a sibling, so a
gitignored `.claude/` or `CLAUDE.md` is simply absent inside the worktree — the session
loses `skillOverrides`, permissions and conventions with no error, while the database,
ports and containers are perfectly isolated. The three axes being right says nothing about
the fourth.

The remedy is the mechanism that already exists: list those paths in `WT_LINKS`, exactly
like any other unversioned root file. Projects that commit `.claude/` and `CLAUDE.md` are
unaffected. Placement-vs-settings comparison in full:
[02-worktree-overview-conventions.md](02-worktree-overview-conventions.md).

## The disproven assumption, corrected for posterity

Earlier aidex research assumed monorepo was the default topology for this kind of
project. A 2026-07-01 session investigation found 6/6 sampled projects were actually
split-git services glued by an unversioned orchestration wrapper (no root `.git`). The
lesson is structural, not a new default: **never assume a topology — detect it per
project, every time.**

## Illustrative topology shapes (not an exhaustive enum)

These three shapes come up often enough to name, but a real project may not fit
neatly into any of them — the interview's job is to capture what is actually true, not
to force-fit a label onto it.

- **Single-repo monorepo** — one root `.git`, all participants live under it. The
  worktree unit is the whole tree at one branch (no per-service worktreeing without
  `git sparse-checkout`, which rarely pays off).
- **Split-git services + shared wrapper** — no root `.git`; each service directory is
  its own git repo; an unversioned wrapper (compose file, `dev.sh`) at root glues them
  together for local dev. Each participant worktrees independently; the wrapper itself
  is not a worktree participant unless it is versioned somewhere.
- **Classic multi-repo** — each repo is fully self-sufficient (its own dependencies,
  its own dev workflow), with no shared wrapper at all. Coordination across repos, if
  any, is a branch-naming convention rather than shared tooling.

If the real project is a hybrid or doesn't match any of these, record what's actually
there — do not bend the facts to fit one of the three labels.
