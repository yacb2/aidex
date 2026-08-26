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
| A command: `backend_test_cmd` with `{path}` | `vi.mock` versus MSW ([08-frontend-test-shapes.md](08-frontend-test-shapes.md)) |
| A path: `helpers_dir`, `module_map` | When the full suite runs ([13-affected-tests-expansion.md](13-affected-tests-expansion.md)) |
| A persona table (`personas_ref`), a UI locale, a UI stack | Selector strategy, cleanup strategy, login strategy |

The test: if the line would still be true in a different project, it is a rule and it
lives here in `references/`; if it is true only of this project, it is a fact and it
lives in the profile. A project that wants to **deviate** from a rule does not edit the
profile — it records the deviation as a decision in its own `.context/decisions/` and
the profile stays a list of values.

## Who reads it

| Reader | Keys used |
|---|---|
| This skill, when applying any `{{key}}` in files 09–13 | all |
| `scripts/gen-test-e2e.sh` | `project_slug`, `project_kebab`, `db_port`, `db_user`, `db_password_env`, `dev_*_port`, `e2e_*_port`, `e2e_service`, `seed_bootstrap_cmd`, `seed_e2e_bootstrap_cmd` |
| `aidex-audit`'s `affected-tests`, once wired | `backend_test_cmd`, `frontend_test_cmd`, `e2e_test_cmd` — to render the CMD line without bare runners |
| A reader orienting in the project | `personas_ref`, `cross_deps_ref`, `module_map`, `ui_stack`, `ui_locale` |

## Seeding it

`scripts/profile-init.py` (written separately; not yet in this skill) derives the
port, database and command keys from an existing `test-e2e.sh` and
`docker-compose.yml`, and leaves the reference keys (`personas_ref`, `cross_deps_ref`)
blank for the author to fill. Until it exists, copy the template and fill the values
by hand from those two files; every key is a single line, and the generator names the
first missing one.
