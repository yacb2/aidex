---
title: Testing profile
status: open
created: 2026-09-01
updated: 2026-09-01
project_slug: aidex
project_kebab: aidex
test_cmd: bash {path}
suite_cmd: bash tests/run-all.sh
blindspot_expansions:
  - a touched skills/*/scripts/*.sh => that skill's test-*.sh siblings, which the runner discovers by name
  - a touched install.sh => the whole suite, because every test drives it
  - a touched rules/*.md or SKILL.md front matter => that skill's evals/, which the suite does not run
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

Canon: `~/.claude/skills/aidex-coverage/references/14-testing-profile.md`.
