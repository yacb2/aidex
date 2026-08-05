# E2E Testing — Isolated Environment Only

The rule is about **what the run targets**, not about which script invokes it. E2E may
never touch a *real* database; it must run against a *disposable* one. That is the same
distinction `database-protection.md` draws, and this rule defers to it rather than
restating it.

## NEVER

- Run E2E against a real database or the dev environment — including `npx playwright test`
  or `pnpm test:e2e` pointed at dev, which is the usual way this happens
- Create, modify, or delete data on the development database from tests
- Skip isolation because no `test-e2e.sh` exists yet — absence of the script is not
  permission to fall back to dev

## ALWAYS

- Prefer `./test-e2e.sh` from the workspace root: it creates an isolated test database
  (cloned from template), starts separate backend/frontend on different ports (dev + 10),
  and runs Playwright with `playwright.e2e.config.ts`. When it exists, it is the way.
- **When the project has no `test-e2e.sh`:** the legal path is to establish a disposable
  environment first — generate the script (`aidex-worktree` knows how) or stand up an
  equivalent throwaway database and point the runner at it. Running E2E is allowed the
  moment the target is disposable; it is the target that gates, not the filename.
- Unit tests (Vitest) are safe — they run in happy-dom with no database connection

## Port Convention

| Service | Dev | E2E (dev + 10) |
|---------|-----|----------------|
| Frontend | project-specific | +10 |
| Backend | project-specific | +10 |
| Database | `<project>` | `<project>_e2e` (template clone) |

## Worktrees

- In an isolated (Tier 2) worktree, E2E runs via that worktree's own generated `test-e2e.sh` — never fall back to the root/dev environment.
- A Tier-2 isolated worktree includes isolated E2E capability by default — do not ask whether to include it.
