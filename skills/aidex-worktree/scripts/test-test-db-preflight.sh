#!/usr/bin/env bash
# test-test-db-preflight.sh — the four states test-db-preflight.sh must tell apart.
#
# No live Postgres: PREFLIGHT_PSQL is stubbed, which is also what proves the
# script issues only SELECTs (the stub records every statement and the test
# asserts no DROP/TRUNCATE/terminate ever reaches it).

set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PRE="$SCRIPTS/test-db-preflight.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures+1)); }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
LOG="$TMP/sql.log"

# $1 = value for the pg_database existence probe, $2 = session count
make_stub() {
  cat > "$TMP/psql" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do :; done
sql="\${!#}"
echo "\$sql" >> "$LOG"
case "\$sql" in
  *pg_database*)       printf '%s\n' "$1" ;;
  *pg_stat_activity*)  printf '%s\n' "$2" ;;
  *)                   printf '1\n' ;;
esac
EOF
  chmod +x "$TMP/psql"
}

run() { PREFLIGHT_PSQL="$TMP/psql" bash "$PRE" "$@" 2>"$TMP/err"; }

# (a) no target named -> UNDETERMINED (4), and nothing is queried.
: > "$LOG"
make_stub "1" "0"
run --db "" ; rc=$?
[[ $rc -eq 4 ]] || fail "(a) missing --db should exit 4 (got $rc)"
grep -qi 'undetermined' "$TMP/err" || fail "(a) must say UNDETERMINED: $(cat "$TMP/err")"
[[ ! -s "$LOG" ]] || fail "(a) must not query anything without a target"

# (b) database absent -> clear (0)
: > "$LOG"; make_stub "" "0"
run --db test_x ; rc=$?
[[ $rc -eq 0 ]] || fail "(b) absent database should exit 0 (got $rc)"
grep -qi 'clear' "$TMP/err" || fail "(b) must report clear: $(cat "$TMP/err")"

# (c) database present WITH sessions -> BUSY (1), naming the count.
#     This is the `is being accessed by other users` case: 12 in the corpus.
: > "$LOG"; make_stub "1" "3"
run --db test_echo_lab ; rc=$?
[[ $rc -eq 1 ]] || fail "(c) busy database should exit 1 (got $rc)"
grep -qi 'BUSY' "$TMP/err" || fail "(c) must report BUSY: $(cat "$TMP/err")"
grep -q '3 session' "$TMP/err" || fail "(c) must name the session count: $(cat "$TMP/err")"

# (d) database present with NO sessions -> STALE (2), distinct from BUSY.
#     The `already exists` case, and the MORE common one: 23 in the corpus.
#     Collapsing it into BUSY would give the opposite advice ("wait for the
#     other run") for a database no run is holding.
: > "$LOG"; make_stub "1" "0"
run --db test_echo_lab ; rc=$?
[[ $rc -eq 2 ]] || fail "(d) stale database should exit 2 (got $rc)"
grep -qi 'STALE' "$TMP/err" || fail "(d) must report STALE: $(cat "$TMP/err")"
grep -qi 'busy' "$TMP/err" && fail "(d) STALE must not also read as BUSY: $(cat "$TMP/err")"

# (e) READ-ONLY: across every state above, only SELECTs were issued.
grep -qiE 'drop|truncate|pg_terminate_backend|delete|alter' "$LOG" \
  && fail "(e) preflight issued a non-read-only statement: $(cat "$LOG")"
grep -qi 'select' "$LOG" || fail "(e) expected the probes to be SELECTs: $(cat "$LOG")"

if [[ $failures -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — test-db-preflight: undetermined/clear/busy/stale kept distinct, read-only"
