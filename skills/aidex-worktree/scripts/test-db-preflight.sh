#!/usr/bin/env bash
# test-db-preflight.sh — name the test-database collision before the suite hits it.
#
# Usage:
#   test-db-preflight.sh --db <name> [--host H] [--port P] [--user U]
#
# Exit codes — distinct on purpose, because the two failures need opposite advice:
#   0  clear: the test database does not exist, nothing to collide with
#   1  BUSY:  it exists and another session holds it -> a run is in flight
#   2  STALE: it exists with no sessions -> an interrupted run left it behind
#   4  UNDETERMINED: the target could not be resolved, or psql is unreachable
#
# READ-ONLY BY CONSTRUCTION. It queries `pg_database` and `pg_stat_activity` and
# does nothing else. It never DROPs, never TRUNCATEs and never calls
# pg_terminate_backend — killing another session's run is precisely the
# destructive-by-surprise class `rules/database-protection.md` forbids, and it is
# not needed: naming the collision is the whole point.
#
# WHY (BL-136). Measured across the transcript corpus: 12 runs died on
# `database "test_x" is being accessed by other users` while another run held it,
# and 23 more on `database "test_x" already exists` with no live session — a stale
# database from an interrupted run. The second is the MORE common case, and both
# surface as an opaque Django/pytest traceback several screens long. The expensive
# part is never the failure; it is the misdiagnosis afterwards, which is why this
# reports a state and a next step instead of just failing.
#
# Exit 4 is deliberately not 0: a preflight that quietly no-ops converts "mystery
# failure" into "mystery failure that passed a check".

set -uo pipefail

if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  C_Y=$'\033[33m' C_R=$'\033[31m' C_G=$'\033[32m' C_0=$'\033[0m'
else C_Y='' C_R='' C_G='' C_0=''; fi

DB="" HOST="${PGHOST:-127.0.0.1}" PORT="${PGPORT:-${DB_PORT:-}}" USER="${PGUSER:-${DB_USER:-}}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)   DB="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --user) USER="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 4 ;;
  esac
done

# The suite's target database, not the app's. A caller that cannot name it has
# nothing to check, and guessing would check the wrong database.
if [[ -z "$DB" ]]; then
  printf '%sUNDETERMINED%s: no target database. Pass --db <name> (the TEST database,\n' "$C_Y" "$C_0" >&2
  printf '  e.g. test_<app> for Django). Nothing was checked.\n' >&2
  exit 4
fi
[[ -n "$PORT" ]] || PORT=5432

# The name is interpolated into both probes, so a hostile value turns a read-only
# script into an arbitrary-SQL one — `x'; DROP DATABASE prod; --` reached the
# server before this guard existed. Postgres database names here are plain
# identifiers, so anything outside [A-Za-z0-9_$] is refused rather than escaped:
# a whitelist cannot be defeated by a quoting subtlety, and nothing legitimate
# is lost.
if [[ ! "$DB" =~ ^[A-Za-z_][A-Za-z0-9_$]*$ ]]; then
  printf '%sUNDETERMINED%s: %q is not a plain database identifier — refusing to\n' \
    "$C_Y" "$C_0" "$DB" >&2
  printf '  interpolate it into a query. Nothing was checked.\n' >&2
  exit 4
fi

# Overridable so the guard is testable without a live server.
PSQL="${PREFLIGHT_PSQL:-psql}"
q() {
  "$PSQL" -h "$HOST" -p "$PORT" ${USER:+-U "$USER"} -d postgres -tAc "$1" 2>/dev/null
}

EXISTS="$(q "SELECT 1 FROM pg_database WHERE datname = '$DB'")"
if [[ $? -ne 0 || -z "${EXISTS:-}" && -z "$(q 'SELECT 1')" ]]; then
  printf '%sUNDETERMINED%s: cannot reach postgres at %s:%s — nothing was checked.\n' \
    "$C_Y" "$C_0" "$HOST" "$PORT" >&2
  exit 4
fi

if [[ -z "$EXISTS" ]]; then
  printf '%sclear%s: %s does not exist — no collision.\n' "$C_G" "$C_0" "$DB" >&2
  exit 0
fi

N="$(q "SELECT count(*) FROM pg_stat_activity WHERE datname = '$DB'")"
N="${N:-0}"

if [[ "$N" -gt 0 ]]; then
  printf '%sBUSY%s: %s exists and %s session(s) are using it.\n' "$C_R" "$C_0" "$DB" "$N" >&2
  printf '  Another test run is in flight against %s:%s. Wait for it or cancel it —\n' "$HOST" "$PORT" >&2
  printf '  starting now fails with ObjectInUse several screens into a traceback.\n' >&2
  exit 1
fi

printf '%sSTALE%s: %s exists with no live sessions.\n' "$C_Y" "$C_0" "$DB" >&2
printf '  An interrupted run left it behind. Reuse it (--reuse-db) or let the runner\n' >&2
printf '  recreate it (--create-db); this script will not drop it for you.\n' >&2
exit 2
