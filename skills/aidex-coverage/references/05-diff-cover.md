# Changed-lines coverage with `diff-cover` (`q5`)

**What it is not:** a hook, a CI gate, or a pre-commit check. `q4` forecloses all three in
this repo family — no CI, no pre-commit that runs a suite. This is an on-demand command a
human runs against a branch diff, in the same read-only family as the coverage sweep
(`skills/aidex-audit/scripts/coverage-config-check.sh`).

**Why changed lines, not a global `fail_under`.** The fleet's whole-codebase line-coverage
numbers are low enough — 0.70% to 84.49% across the 14 Vitest packages this applies to —
that any single enforceable global value either blocks everything or demands nothing
(`q5`'s ADR, on arithmetic). A changed-lines check only ever measures the much smaller
surface a branch actually touches, so it can sit well above the codebase-wide average
without being absurd.

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
   see below), but because the backend's Python dev-dependency group is where every project
   in this rollout already keeps its Python tooling. `dashboard_template_ws/backend` carries
   the pin today (`poetry add --group dev diff-cover@^10.5.1`), as the template (`q8`) —
   this is not yet a fleet-wide install; pin it the same way in a project's backend before
   running the command there for the first time.

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
- `--fail-under=60` is the threshold from
  `.context/decisions/2026-08-23-changed-lines-coverage-threshold.md` — kept explicit on
  the command line so the number is never silently stale relative to that ADR. `diff-cover`
  exits non-zero under the threshold; nothing in this rollout wires that exit code to
  anything. A human reads the printed percentage and decides — `q4` forecloses turning this
  into a gate.

**Verified 2026-08-23** against `dashboard_template_ws`, comparing `HEAD` to commit
`9b35705` (a real multi-commit frontend diff, not a synthetic one):

```
-------------
Diff Coverage
Diff: 9b35705...HEAD, staged and unstaged changes
-------------
frontend/plugins/changelog.ts (100%)
...
frontend/src/router/index.ts (9.1%): Missing lines 327,329,333,338-340,344,347-348,352
-------------
Total:   66 lines
Missing: 15 lines
Coverage: 77%
-------------
```

The command prints a changed-lines percentage and a per-file breakdown of missing lines;
that is the whole output contract.

**Also verified against a real, still-open feature branch** —
`echo_lab_ws-wt-editor-week/frontend` on `feat/bl-461-multi-selection`, compared to `main`
(1344 changed lines, `Coverage: 90%`) — so the acceptance criterion is closed literally
against a branch, not only against a commit range on the trunk.

## Backend `diff-cover`: out of scope, and why

Not a tooling gap any more — `Q4` (Phase 13) installed `pytest-cov` fleet-wide. What is
still open is the verification Phase 13 itself required: that NS's suite collects and runs
under `pytest-cov` **without failures across its full 4,504 tests** (`p2`). Phase 2 Task
2.5 verified the `apps/parties/` (276 passed, 6 skipped) and `apps/billing/` (1469 passed)
subsets, not the full suite. Until `p2` closes, this stays frontend-only —
the reason is the outstanding verification, never a decision to exclude the backend
permanently.

## Threshold

**60%.** (Repeated here and in the quoted command on purpose — each copy names the ADR
below as its single owner.) Full arithmetic and reopen condition:
`.context/decisions/2026-08-23-changed-lines-coverage-threshold.md`. In short: it is
derived from 8 real `diff-cover` runs against this fleet (7 trunk diffs plus the
`feat/bl-461-multi-selection` branch above), not from a margin over any whole-codebase
baseline — a changed-lines percentage and a whole-codebase percentage are different
quantities, and asserting a margin between them would be exactly the "picked round" failure
the number is required to avoid. Seven of the eight sampled diffs cluster at 77–90%; one
(`ph_backoffice_ws`, 46%) sits well below that cluster. 60% sits in the gap between them, so
it has real discriminating power against this fleet's actual recent work: 7 of 8 sampled
diffs clear it, the one genuine outlier does not.

It is one fleet-wide number, not per-project. Re-derive if a larger sample changes the
shape of that distribution, or if `q4` is revisited and a gate becomes viable (a gated
threshold needs different arithmetic than an on-demand one).

Source: `.context/plans/_archive/2026-08-22-suite-speed-and-coverage-rollout/09-diff-cover.md`
(Phase 9), executing `q5` of
`.context/decisions/2026-08-22-suite-speed-and-coverage-programme.md`.
