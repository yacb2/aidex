# Changed-lines coverage with `diff-cover` (`q5`)

**What it is not:** a hook, a CI gate, or a pre-commit check. `q4` forecloses all three in
this repo family — no CI, no pre-commit that runs a suite. This is an on-demand command a
human runs against a branch diff, in the same read-only family as the coverage sweep
(`skills/aidex-audit/scripts/coverage-config-check.sh`).

**Why changed lines, not a global `fail_under`.** Whole-codebase line-coverage numbers
usually span a wide enough range across packages that any single enforceable global value
either blocks everything or demands nothing. A changed-lines check only ever measures the
much smaller surface a branch actually touches, so it can sit well above the codebase-wide
average without being absurd.

## Prerequisite chain

1. `coverage.include` (Phase 2) fixes the denominator — why a threshold on an implicit
   denominator is not a measurement is `m7`, stated in
   [03-fixtures-convention.md](03-fixtures-convention.md#m7-as-an-authoring-rule).
2. The `cobertura` reporter (Phase 9 Task 9.1) is the report file `diff-cover` reads. Every
   `vitest.config.*` this rollout touched emits `['text', 'html', 'lcov', 'cobertura']` —
   the existing reporters stay, `cobertura` is additive.
3. `diff-cover` itself is a Python tool, and its version belongs pinned as a dev dependency
   in a project's **backend** `pyproject.toml` (`[tool.poetry.group.dev.dependencies]`),
   the group that already carries `pytest-cov` and `factory-boy` — not because it runs
   against backend coverage (it does not; backend `diff-cover` is separately out of scope,
   see below), but because that group is where a project keeps its Python tooling. Pin it
   (`poetry add --group dev diff-cover`) in a project's backend before running the command
   there for the first time.

## The invocation

Run from the **host**, not inside `docker compose` — the dependency-group placement above
invites the opposite assumption, so say this explicitly every time the command is quoted.
`diff-cover` needs the host's `git` (to compute the diff against the trunk) and the
frontend's `coverage/cobertura-coverage.xml` on the host filesystem; neither requires a
running backend container, and nothing in this command starts one.

```bash
cd <project>/backend
.venv/bin/diff-cover ../frontend/coverage/cobertura-coverage.xml \
  --compare-branch=<trunk-ref> \
  --src-roots ../frontend \
  --fail-under=60
```

- `<project>/backend` is where the pinned `diff-cover` lives (its own `.venv`, via
  `poetry add --group dev diff-cover`).
- `../frontend/coverage/cobertura-coverage.xml` is Task 9.1's report — run
  `pnpm exec vitest run --coverage` from `../frontend` first if it is stale or missing
  (prerequisite 2 above: the `cobertura` reporter must be in `coverage.reporter`).
- `--compare-branch` names the trunk ref the current branch diverged from (`main` in most
  of this fleet).
- `--fail-under=60` is the threshold (see below) — kept explicit on the command line so
  the number is never silently stale relative to its ADR. `diff-cover` exits non-zero under
  the threshold; nothing wires that exit code to anything. A human reads the printed
  percentage and decides — `q4` forecloses turning this into a gate.

Illustrative output — a changed-lines percentage plus a per-file breakdown of missing
lines is the whole output contract:

```
-------------
Diff Coverage
Diff: <base>...HEAD, staged and unstaged changes
-------------
frontend/plugins/changelog.ts (100%)
frontend/src/router/index.ts (9.1%): Missing lines 327,329,333,338-340,344,347-348,352
-------------
Total:   66 lines
Missing: 15 lines
Coverage: 77%
-------------
```

## Backend `diff-cover`: out of scope, and why

Frontend-only while the backend suite's clean run under `pytest-cov` is still unverified —
the reason is that outstanding verification, never a decision to exclude the backend
permanently.

## Threshold

**60%**, one number rather than one per project. It is derived from real `diff-cover` runs
against this fleet's own recent branches, not from a margin over any whole-codebase
baseline — a changed-lines percentage and a whole-codebase percentage are different
quantities, and asserting a margin between them would be exactly the "picked round" failure
the number is required to avoid. The sampled diffs cluster well above 60% with one genuine
outlier below it, so the number discriminates instead of passing everything.

Re-derive if a larger sample changes the shape of that distribution, or if `q4` is
revisited and a gate becomes viable (a gated threshold needs different arithmetic than an
on-demand one). The project's own ADR is the single owner of the current value.
