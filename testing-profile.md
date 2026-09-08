---
title: Testing profile
status: open
created: 2026-09-01
updated: 2026-09-08
project_slug: aidex
project_kebab: aidex
test_cmd: bash {path}
suite_cmd: bash tests/run-all.sh
module_map: .context/audits/test-coverage/module-map.json
blindspot_expansions:
  - a touched skills/*/scripts/*.sh => that skill's test-*.sh siblings, which the runner discovers by name
  - a touched install.sh => the whole suite, because every test drives it
  - a touched rules/*.md or SKILL.md front matter => that skill's evals/, which the suite does not run
  - a touched skills/*/SKILL.md => tests/test-readme-sync.sh, tests/test-skill-description-language.sh, tests/test-spec-audit-complete.sh — the three cross-skill lockstep tests break from any skill
  - a NEW or RENAMED test file anywhere => tests/test-discovery-census.sh, which asserts the runner's globs still find it
  - a touched tests/run-all.sh or tests/lib/* => the whole suite at both roots (RUN_INSTALL_PARITY=full): the runner's own change cannot be verified by a subset it selects
testing_packs: none
---

# Testing profile

This file is a DELTA over `aidex-coverage`. Facts about this project only.

aidex is a Bash and Claude Code skills toolkit: there is no frontend, backend service,
database or browser, so the `frontend`, `build` and `e2e` legs do not exist and their keys
are deliberately absent rather than empty. `sweep-gate.sh` must therefore be run as
`--only suite`; a bare invocation would refuse on the four unbound legs, which is the
correct behaviour and not a defect.

This file is TRACKED, at the repo root rather than in `.context/`, because aidex
gitignores `.context/` by policy — a profile there could never travel with a checkout, so
the gate was unrunnable on a fresh clone (BL-289). `.context/testing-profile.md` still
wins wherever it exists.

The one leg is the shell suite, `tests/run-all.sh`, which auto-discovers `test-*.sh` across
`skills/*/scripts/` and `hooks/`. It skips 9 docker-dependent tests unless
`RUN_DOCKER_TESTS=1`, so its count is a floor.

`testing_packs: none` is a value, not an unanswered question: no stack pack applies to a
project whose entire test surface is shell scripts.

**Per-item selection (added 2026-09-08).** `module_map` names the map
`affected-tests.sh` resolves through: one module per `skills/<name>/`, plus `hooks`,
`install`, `rules` and the suite harness. The map's repo `test_hint` is a **loop**, not a
bare runner — a shell suite has one file per test, so `bash a.sh b.sh` would run only the
first and pass the second as an argument. Verified 2026-09-08: a diff touching
`skills/aidex-dash/scripts/dash/check_artifact.py` selects that skill's tests plus the
three cross-skill lockstep tests, not `tests/run-all.sh`.

The map lives under the gitignored `.context/`, so it does **not** travel with a checkout
and a fresh clone falls back to the full suite until it is regenerated. `module_map` is
declared here anyway; that the key is not yet read by `affected_tests.py` is BL-366.

**Evals are not tests and never enter a selection.** `tests/eval-*.sh` is not in
`run-all.sh`'s discovered set — the runner globs `tests/test-*.sh`. A first cut of the
module map listed `tests/eval-local-first-behavior.sh` among a module's unit tests and the
targeted run hung on it, costing more than the full-suite gate it was meant to replace.
Map only what the runner runs.

Canon: `~/.claude/skills/aidex-coverage/references/14-testing-profile.md`.
