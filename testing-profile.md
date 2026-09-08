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

Facts only — a DELTA over `aidex-coverage`. The explanation of this project's test
surface (why there is one leg, why the profile is at the repo root, how per-item
selection resolves) is `tests/README.md`; a 250-word body limit is what keeps the two
apart, and `profile-init.py --check` enforces it.

Canon: `skills/aidex-coverage/references/14-testing-profile.md`.
