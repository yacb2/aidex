# Isolated E2E infrastructure

A second backend on its own port, a clone of a PostgreSQL template database per run,
one orchestrator script. `rules/e2e-testing.md` is the rule (E2E targets a disposable
database, always); this file is the mechanism. Every `{{key}}` is a fact in the testing
profile ([14-testing-profile.md](14-testing-profile.md)).

## Port convention

| Service | Dev | E2E |
|---|---|---|
| Frontend | `{{dev_frontend_port}}` | `{{e2e_frontend_port}}` = dev + 10 |
| Backend | `{{dev_backend_port}}` | `{{e2e_backend_port}}` = dev + 10 |
| Database | `{{db_port}}` | same server; `{{db_name}}_e2e`, cloned from `{{db_name}}_e2e_template` |

Same Postgres, different database: isolation is by name, which is what every guard checks.

## Compose: the `{{e2e_service}}` service

A copy of `backend` (same build, same volume) with three differences and one guard:

```yaml
  {{e2e_service}}:
    ports: ["{{e2e_backend_port}}:{{dev_backend_port}}"]
    environment:
      - DJANGO_SETTINGS_MODULE=config.settings.test_e2e
      - DB_NAME={{db_name}}_e2e            # explicit; no env_file, or dev's DB_NAME leaks in
      - DB_HOST=db
      - FRONTEND_URL=http://localhost:{{e2e_frontend_port}}
      - EMAIL_MODE=mailhog
    depends_on: { db: { condition: service_healthy } }
    profiles: [e2e]                        # the guard: `docker compose up -d` never starts it
```

## Django: `config/settings/test_e2e.py`

Inherits dev (so `DEBUG=True`, which is what makes the dev-login endpoint and
`loginFast` available on the E2E backend), then trims for speed:

```python
from .dev import *  # noqa

INSTALLED_APPS = [a for a in INSTALLED_APPS if a != "debug_toolbar"]
MIDDLEWARE = [m for m in MIDDLEWARE if "debug_toolbar" not in m]
Q_CLUSTER = {"name": "e2e", "orm": "default", "sync": True}        # no worker container (Celery: CELERY_TASK_ALWAYS_EAGER)
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]  # login ~10x faster
SIMPLE_JWT = {**SIMPLE_JWT, "ACCESS_TOKEN_LIFETIME": timedelta(seconds=60),
              "REFRESH_TOKEN_LIFETIME": timedelta(minutes=5)}      # refresh flows testable in a run
```

`DB_NAME` comes from compose, not this file. A settings guard that allowlists database
names must be updated when a project is renamed, or the E2E backend refuses its own DB.

## Playwright: `playwright.e2e.config.ts`

```typescript
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: false,
  workers: 1,
  globalSetup: './tests/e2e-setup/global-setup.ts',
  globalTeardown: './tests/e2e-setup/global-teardown.ts',
  reporter: [['html', { outputFolder: 'playwright-report-e2e' }], ['list']],
  use: { baseURL: process.env.E2E_FRONTEND_URL, screenshot: 'only-on-failure', video: 'retain-on-failure' },
  webServer: {
    command: 'pnpm dev --port {{e2e_frontend_port}}',
    port: {{e2e_frontend_port}},
    reuseExistingServer: !process.env.CI,
    env: { VITE_API_URL: process.env.E2E_API_BASE },
  },
})
```

`workers: 1` / `fullyParallel: false` because specs share one database and one auth
session; two workers as the same persona race on cookies and row counts. Parallelism
here is bought with per-worker databases, not a flag (the suite-speed campaign demoted
the worker count as a lever). The report directory is separate so an E2E run never
overwrites a unit-test report.

**There is no dev-mode Playwright config.** A `playwright.config.ts` on the dev ports
is how E2E ends up mutating a real database; the rule forbids it and this design does
not ship one.

## `tests/e2e-setup/test-config.ts`

```typescript
export const TEST_CONFIG = {
  FRONTEND_URL: process.env.E2E_FRONTEND_URL || 'http://localhost:{{e2e_frontend_port}}',
  API_BASE:     process.env.E2E_API_BASE     || 'http://localhost:{{e2e_backend_port}}/api/v1',
  BACKEND_URL:  process.env.E2E_BACKEND_URL  || 'http://localhost:{{e2e_backend_port}}',
} as const
```

Fallbacks are the **E2E** ports, never dev's: a helper run outside the orchestrator must still miss the real database.

## Global setup and teardown

`global-setup.ts` runs once per invocation, using `psql` on the host (`brew install
libpq` / `apt install postgresql-client`) and `E2E_DB_PORT` exported by the
orchestrator:

1. verify `{{db_name}}_e2e_template` exists — else fail with "run `--setup-template`";
2. `pg_terminate_backend` on every connection to `{{db_name}}_e2e`;
3. `DROP DATABASE IF EXISTS {{db_name}}_e2e`;
4. `CREATE DATABASE {{db_name}}_e2e TEMPLATE {{db_name}}_e2e_template` (about 200 ms);
5. `docker compose --profile e2e restart {{e2e_service}}` (falls back to `up -d`) — the
   backend must reconnect to the fresh database;
6. poll `${BACKEND_URL}/api/v1/` until status < 400, up to 60 s.

`global-teardown.ts` leaves the database alone on purpose: preserved for inspecting a failure, destroyed by step 3 of the next run.

## Template lifecycle

`./test-e2e.sh --setup-template` builds the template: start `db`, unmark and drop any
existing template and clone, `CREATE DATABASE`, then via `docker compose run --rm` with
`DB_NAME={{db_name}}_e2e_template`: `migrate`, `{{seed_bootstrap_cmd}}` (catalogs, base
personas), `{{seed_e2e_bootstrap_cmd}}` (E2E scenarios,
[12-e2e-seed-generators.md](12-e2e-seed-generators.md)); finally
`UPDATE pg_database SET datistemplate = true`.

Rebuild whenever a migration, `{{seed_bootstrap_cmd}}` or an E2E generator changes; not otherwise.

## Generating `test-e2e.sh`

Run `scripts/gen-test-e2e.sh [--force] [<project-root>]`: it reads
`.context/testing-profile.md`, fills `assets/templates/test-e2e.sh.template`, and the
result is the project's only E2E entry point. The script sources the project's `.env`
**before** its `${DB_PORT:-default}` fallbacks apply, so an `aidex-worktree` checkout
(which writes its own `.env`) drives its own Postgres instead of dev's; it exports
`E2E_DB_PORT` for global-setup and never sets `COMPOSE_PROJECT_NAME` (the worktree owns
it). Precondition: `skills/aidex-worktree/assets/profiles/django-vue-compose.defaults.env`.

```bash
./test-e2e.sh e2e/foo.spec.ts          # one spec — the usual invocation
./test-e2e.sh --grep "creates"         # forwarded to playwright test
./test-e2e.sh                          # whole suite: integration boundary only (13-affected-tests-expansion.md)
./test-e2e.sh --setup-template         # after migrations / seed changes
./test-e2e.sh --ui | --stop | --help
```

## Verification checklist

- `docker compose ps` does not list `{{e2e_service}}`; `--profile e2e ps` does.
- `SELECT datname, datistemplate FROM pg_database WHERE datname LIKE '%e2e%'` shows `t`.
- The dev database has **zero** `e2e%` users: `SELECT count(*) FROM auth_user WHERE
  email LIKE 'e2e%'` is 0 against `{{db_name}}` and non-zero against `{{db_name}}_e2e`.
- A one-spec run passes twice in a row.
- "relation already exists" during `--setup-template` means the old template was still
  flagged and not dropped: `UPDATE pg_database SET datistemplate = false WHERE datname =
  '{{db_name}}_e2e_template'`, then rerun.
