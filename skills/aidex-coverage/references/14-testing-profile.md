# The testing profile

`<project>/.context/testing-profile.md` is the one file where a project records the
**facts** the canon in this skill needs to be applied to it. Template:
`assets/templates/testing-profile.md.template`. It is a delta over `aidex-coverage`:
everything in it is specific to that project, and nothing in it is a rule.

## Facts versus rules

| A fact (belongs in the profile) | A rule (never enters the profile) |
|---|---|
| A port: `dev_backend_port`, `e2e_frontend_port` | Which layer a behaviour is tested at ([01-layer-model.md](01-layer-model.md)) |
| A database name, user, password env var | When shared setup becomes a fixture ([03-fixtures-convention.md](03-fixtures-convention.md)) |
| A command: `backend_test_cmd` with `{path}` | `vi.mock` versus MSW (the `testing-vue` pack) |
| A path: `helpers_dir`, `module_map` | When the full suite runs ([13-affected-tests-expansion.md](13-affected-tests-expansion.md)) |
| A persona table (`personas_ref`), a UI locale, a UI stack | Selector strategy, cleanup strategy, login strategy |
| Which stack packs apply (`testing_packs`) | What a pack says once resolved |

The test: if the line would still be true in a different project, it is a rule and it
lives here in `references/`; if it is true only of this project, it is a fact and it
lives in the profile. The profile has **no `## ` sections**: the template's note is the
whole body, and a profile that grows past it (553 words against the template's 376, in
one adoption) is facts and explanation mixed in the one file scripts read —
`profile-init.py --check` reports it, together with any `references/testing/*.md` over
the ~2,500-word tripwire. A project that wants to **deviate** from a rule does not edit the
profile — it records the deviation as a decision in its own `.context/decisions/` and
the profile stays a list of values.

## Who reads it

| Reader | Keys used |
|---|---|
| This skill, to resolve the stack packs | `testing_packs` |
| The stack packs, when applying any `{{key}}` in their references | all |
| `testing-playwright-app/scripts/gen-test-e2e.sh` | `project_slug`, `project_kebab`, `db_port`, `db_user`, `db_password_env`, `dev_*_port`, `e2e_*_port`, `e2e_service`, `seed_bootstrap_cmd`, `seed_e2e_bootstrap_cmd` |
| `aidex-audit`'s `affected-tests`, once wired | `backend_test_cmd`, `frontend_test_cmd`, `e2e_test_cmd` — to render the CMD line without bare runners |
| `aidex-backlog`'s `sweep-gate.sh` (the end-of-sweep boundary gate) | `backend_suite_cmd`, `frontend_suite_cmd`, `e2e_suite_cmd`, `build_cmd` — the **full**-suite forms, worker flags included; `e2e_detached` — whether the E2E leg outlives the foreground ceiling and is printed as a detached invocation instead of run inline; optionally `<leg>_pre_cmd` (`backend_pre_cmd`, …) — a command run immediately before that leg and into the same log, for state a fresh checkout should not have inherited (`find . -name __pycache__ -prune -exec rm -rf {} +`). Absent is the normal case; a non-zero pre-command FAILS the leg and the leg does not run |
| A sweep's per-item selection (`sweep-execution-policy.md`, stage 3) | `blindspot_expansions` — the mandatory widenings of `affected-tests.sh`'s selection, one `- ` line each: a migration ⇒ every app referencing the changed model; a touched `*.test.ts` ⇒ `vue-tsc -b` (not `-p`, which excludes test files); a removed UI surface ⇒ grep `tests/e2e/` for the endpoints and testids it owned. Six of the nine problems the 2026-08-26 gate found were one of these three |

The sweep keys are **optional**: a project with no sweep validates without them, and `sweep-gate.sh` is what refuses (exit 2, naming the key) when a sweep runs against a profile that never filled them. The shape is aidex's; the bindings — `-n 4 --dist loadscope`, which runner, which build — are project facts, which is why they live here and not in a `CLAUDE.md` nobody commits.
| A reader orienting in the project | `personas_ref`, `cross_deps_ref`, `module_map`, `ui_stack`, `ui_locale` |

`cross_deps_ref` names **a folder or several modules, comma-separated** — never one
document by contract. A single file named here is where an adopter appends every later
workflow (execution groups, fan-out, order-dependent tests) until it holds four of them
and 4,282 words; the shape the skill writes is one workflow per `NN-<slug>.md` under the
`aidex-reference` tripwire, with `references/testing/00-index.md` as the entry (SKILL.md
§ The shape of the docs this skill writes).

## Stack packs

`testing_packs` is the one key that is a pointer rather than a value: a space-separated
list of skill names, each installed at `~/.claude/skills/<pack>/`. A pack carries what
this skill deliberately does not — the test shapes, helpers, traps and E2E infrastructure
of one framework as it is used in this fleet. The canon decides the layer, the selection
and the gate; the pack says what a test at that layer looks like in that framework.

| Pack | Covers | Typical profile |
|---|---|---|
| `testing-django` | pytest + pytest-django + DRF shapes and traps | app backend |
| `testing-vue` | Vitest + Vue Test Utils + Pinia + MSW shapes and traps | app frontend |
| `testing-playwright-app` | Playwright specs, helpers, seed generators and the disposable template-database environment (`test-e2e.sh` generator) | app E2E |
| `testing-payload` | Payload CMS integration tests (Vitest, Local API) | website backend |
| `testing-svelte` | Vitest + Svelte Testing Library shapes | website frontend |
| `testing-playwright-web` | Playwright for corporate sites: smoke, SEO, i18n, forms, setup | website E2E |

A pack is never model-triggered (`disable-model-invocation: true`): this skill reads its
files with Read once the profile names it. A blank `testing_packs` is a question, not a
default — `profile-init.py` fills it from dependency markers (`pyproject.toml`,
`package.json`), and a project whose stack has no pack yet says so in the profile and
gets a new pack in `myskills`, never a section in this skill.

## Seeding it

`scripts/profile-init.py <project>` derives the port, database, command and pack keys
from an existing `test-e2e.sh`, `docker-compose.yml`, `pyproject.toml` and
`package.json`, and leaves the reference keys (`personas_ref`, `cross_deps_ref`, the
locale) blank for the author to fill. Blank keys are unanswered, not zero; the script
names them. It refuses to overwrite without `--force`, and `--print` never writes.
