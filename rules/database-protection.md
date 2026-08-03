# Database Protection — no destructive op on real data, ever unattended

Canon for database lifecycle. `rules/autonomy.md` class 1 defers to this file;
a project's `CLAUDE.md` may name its own databases but may not loosen it.

## The one distinction that decides everything

**Real data vs. disposable.** Every rule below turns on which of the two a command
touches. Getting this wrong in either direction is a failure: treating a disposable
DB as sacred blocks the E2E workflow, and treating a real DB as disposable is the
incident this rule exists to prevent.

- **Real** — any database holding state someone would miss: the application DB in
  any environment (local, dev, staging, production), and anything seeded by hand.
- **Disposable** — databases whose lifecycle *is* creation and destruction: E2E
  template clones, per-worktree throwaway databases, ephemeral CI databases.
  Destroying these is their designed behaviour, not an incident.

## NEVER (real databases)

- Reset, drop, recreate, truncate, or wipe a real database without the user's
  explicit, in-the-moment authorization for that specific action
- Run `dropdb`, `DROP DATABASE`, `TRUNCATE`, `flush`, `reset_db`, or
  `migrate --fake-initial` after a drop — even on local — unless the user asked for
  it in the current message
- Treat past authorization as standing permission. "We reset the DB last week" does
  **not** authorize resetting it now
- Run sync scripts that drop the destination DB without an explicit request in the
  current turn
- Use `--reset` flags on ETL or tooling that wipes data, unless the user explicitly
  said reset / wipe / start fresh
- Read ambiguous instructions ("clean up", "fix the data", "make it work") as
  authorization to reset
- Drop or recreate a DB as a shortcut around migration conflicts, schema drift, or
  seed-data problems — investigate the root cause instead
- Remove a Docker volume that carries a real database

## Unattended runs — no pre-authorization exists

Inside an unattended run (`aidex-plan-exec`, `aidex-audit`, `aidex-loop`), a
destructive op on a real database is **class 1: never, and never pre-authorizable**.
It is deliberately unlike publication (class 2), which *can* be granted up front.

Two reasons. At planning time the need is unknown — if it were known, the plan would
carry the non-destructive alternative instead. And a permission granted in advance,
for an action nobody expected to need, decays into a rubber stamp.

So: if a run cannot proceed without one, that is a **hard blocker** — stop and
surface it. Stopping is cheap precisely because the case is rare.

## ALWAYS

- If a task seems to require a reset, stop and ask explicitly, naming the database:
  "This requires dropping/resetting `<name>`. Confirm?"
- Prefer non-destructive alternatives: targeted updates, idempotent bootstrap
  commands, partial backfills
- Migrate forward only — never unapply or `migrate <app> zero` without an explicit ask
- Treat disposable databases as routine work: `test-e2e.sh` creating and resetting its
  own template clone needs no authorization and must not be blocked
- Name the databases in the project's `CLAUDE.md` when they are easy to confuse — the
  app DB and its `_e2e` counterpart usually differ by a suffix, which is exactly the
  kind of near-miss that causes the wrong one to be dropped

## Why

A silent reset destroyed real data and dev state that had been set up by hand. The
cost was not the SQL — it was losing imported records, manual fixtures, and
in-progress scenarios with no warning, and recovering meant a full production→local
sync. This rule exists so that cannot happen silently again.

## How to apply

Fires whenever a tool call touches DB lifecycle: `dropdb`, `createdb`, `pg_restore`
over an existing DB, `flush`, `reset_db`, `TRUNCATE`, sync scripts, ETL `--reset`, or
Docker volume removal that includes a database volume. First classify the target as
real or disposable; if you cannot tell, it is real — ask.
