# aidex-coverage references — provenance

The table of what to read for which question lives in [`../SKILL.md`](../SKILL.md)
("When to read what"); it is not repeated here.

Origin: `.context/plans/2026-08-22-suite-speed-and-coverage-rollout/03-coverage-skill.md`
Task 3.1, executing ledger entries `q9`/`s2` of
`.context/decisions/2026-08-22-suite-speed-and-coverage-programme.md` (files 01–03). File
04 (originally the EchoLab worked example, `s3` — relocated to the workspace's private
`.context/references/aidex-coverage/` by BL-211, leaving the template) and the `s4`
ratchet in file 03 were added by the rollout plan's Phase 11
(`.context/plans/2026-08-22-suite-speed-and-coverage-rollout/11-e2e-layer-and-layout.md`).
File 05 was added by Phase 9
(`.context/plans/2026-08-22-suite-speed-and-coverage-rollout/09-diff-cover.md`). File 06
was added after the playbook's field test against `echo_lab_ws` on 2026-08-23.

Files 07–14, `assets/templates/test-e2e.sh.template`, `assets/templates/testing-profile.md.template`
and `scripts/gen-test-e2e.sh` were folded in on 2026-08-26 under
`decision/2026-08-26-coverage-canon-consolidation-and-targeted-runs.md` from five personal
skills (`test-backend-django`, `test-frontend-vue`, `test-e2e`, `test-e2e-setup`,
`test-runner`), which were deleted afterwards; this is the surviving copy of their generic
content, with every project-specific value replaced by a `{{key}}` of the testing profile.

- 07 — `test-backend-django` (SKILL.md, `test-patterns.md`, `test-structure.md`).
- 08 — `test-frontend-vue` (SKILL.md, `frontend-testing-guide.md`, `test-patterns.md`).
- 09 — `test-e2e` (`test-patterns.md`, `adding-tests.md`).
- 10 — `test-e2e` (SKILL.md helpers section, `adding-tests.md`) + `test-e2e-setup/06-base-helpers.md`.
- 11 — `test-e2e-setup` (`01`–`05`, `08`) + `test-e2e/e2e-testing-guide.md`; the "no dev-mode config" rule from `04-playwright-configs.md`.
- 12 — `test-e2e-setup/07-seed-data-pattern.md` + `test-e2e/adding-tests.md` generator rules.
- 13 — `test-runner` (SKILL.md, `confidence-framework.md`, `inference-algorithm.md`, `output-format.md`), rewritten so escalation widens the selection instead of running the full suite.
- 14 + `testing-profile.md.template` — new, no prior source; the fact/rule boundary is the ADR's.
- `test-e2e.sh.template` + `gen-test-e2e.sh` — `test-e2e-setup/03-shell-script.md`, with the `aidex-worktree` `.env` precondition applied.
