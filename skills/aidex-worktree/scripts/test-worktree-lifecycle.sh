#!/usr/bin/env bash
# test-worktree-lifecycle.sh — the worktree mechanism, end to end, repeatedly.
#
# Hermetic: builds its own throwaway workspace with a busybox compose stack, so
# a full cycle is seconds and nothing depends on a real project being present.
#
# What it pins, each one a bug that actually happened:
#   - create -> every resource attributable, slot claimed
#   - down   -> ZERO residue against a global snapshot, claim released
#   - N concurrent creates -> N DISTINCT slots. Five concurrent runs once all
#     probed the same free ports and four picked slot 2; the fix was to reserve
#     under a lock rather than probe, and to anchor the claim to the owner PID so
#     a reaper cannot mistake an in-flight reservation for abandoned garbage.
#   - a failed create rolls back completely — "recoverable mess" is not "no mess"
#   - repeated cycles are IDENTICAL. The point is not that it works once.
#
# Run with: bash skills/aidex-worktree/scripts/test-worktree-lifecycle.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/worktree.sh"; SNAP="$DIR/docker-snapshot.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "SKIP — docker unavailable; the worktree mechanism cannot be exercised"
  exit 0
fi

# --- singleton -------------------------------------------------------------
#
# The fixture's project name, its slot directory and its host ports are all
# fixed, so two instances of this test destroy each other: one's purge step
# removes the other's containers, and both draw from the same slot claims. That
# is a harness error, not a scenario to support — fail loudly instead of
# emitting failures that look like defects in the code under test. (Observed:
# a stray background run overlapping a suite run produced exactly that.)
RUNLOCK="${TMPDIR:-/tmp}/aidex-wt-lifecycle-test.lock"
if ! mkdir "$RUNLOCK" 2>/dev/null; then
  echo "SKIP — another test-worktree-lifecycle.sh is running (lock: $RUNLOCK)."
  echo "       Two instances share the wtfix fixture and would corrupt each other."
  exit 0
fi

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
WS="$TMP/wtfix"
cleanup() {
  for s in a b c d fail1; do ( cd "$WS" 2>/dev/null && bash "$WT" down "$s" ) >/dev/null 2>&1; done
  rm -rf "$TMP" "${TMPDIR:-/tmp}/aidex-wt-slots-wtfix"
  rmdir "$RUNLOCK" 2>/dev/null
}
trap cleanup EXIT

# --- fixture: one git repo + an unversioned compose wrapper -----------------
mkdir -p "$WS/svc"
git -C "$WS/svc" init -q
git -C "$WS/svc" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
: > "$WS/CLAUDE.md"   # project-root marker (there is no root .git)

cat > "$WS/docker-compose.yml" <<'YML'
services:
  app:
    image: busybox:latest
    container_name: wtfix-app${WT_SUFFIX:-}
    command: sh -c "while true; do sleep 3600; done"
    ports:
      - "${APP_PORT:-47000}:8080"
    volumes:
      - appdata:/data
volumes:
  appdata:
YML

mkdir -p "$WS/.context/worktrees"
cat > "$WS/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="svc"
WT_LINKS="docker-compose.yml"
WT_SERVICES="app"
WT_PORT_VARS="APP_PORT=47000"
WT_PORT_STRIDE=10
WT_MAX_SLOTS=9
WT_SUFFIX_VAR="WT_SUFFIX"
WT_POST_CMD='docker compose exec -T app touch /data/post-ran'
ENV

docker image inspect busybox:latest >/dev/null 2>&1 || docker pull -q busybox:latest >/dev/null 2>&1
cd "$WS" || exit 1

# --- purge anything a previous run of THIS test left behind ------------------
#
# The baseline is only meaningful if it is taken on a clean slate. A prior run
# that died mid-flight (or was run against a deliberately broken build, as the
# RED check does) leaves `wtfix-wt-*` containers and a stale claim; the next run
# then counts them and fails with symptoms that have nothing to do with the code
# under test. Everything purged here is named for this fixture and cannot belong
# to a real project.
for proj in $(docker ps -a --format '{{.Label "com.docker.compose.project"}}' | sort -u | grep '^wtfix-wt-' || true); do
  docker compose -p "$proj" down -v --rmi local --remove-orphans >/dev/null 2>&1
done
for v in $(docker volume ls --format '{{.Name}}' | grep '^wtfix-wt-' || true); do docker volume rm "$v" >/dev/null 2>&1; done
for n in $(docker network ls --format '{{.Name}}' | grep '^wtfix-wt-' || true); do docker network rm "$n" >/dev/null 2>&1; done
rm -rf "${TMPDIR:-/tmp}/aidex-wt-slots-wtfix"

BASE="$TMP/base.snap"
bash "$SNAP" take "$BASE" >/dev/null 2>&1

SLOTDIR="${TMPDIR:-/tmp}/aidex-wt-slots-wtfix"
claims() { ls "$SLOTDIR" 2>/dev/null | grep -c '^slot-' | tr -d ' '; }

# --- 1. single cycle, twice, must be identical ------------------------------
for round in 1 2; do
  bash "$WT" new a --branch "feat/a$round" >/dev/null 2>&1 \
    || fail "round $round: create failed"
  [[ -d "$TMP/wtfix-wt-a" ]] || fail "round $round: worktree directory missing"
  [[ "$(claims)" == "1" ]] || fail "round $round: expected exactly 1 slot claim, got $(claims)"
  docker ps -q --filter "label=com.docker.compose.project=wtfix-wt-a" | grep -q . \
    || fail "round $round: no container for the worktree project"
  docker compose -p wtfix-wt-a exec -T app test -f /data/post-ran >/dev/null 2>&1 \
    || fail "round $round: WT_POST_CMD did not run (the hook projects use to provision an isolated E2E)"

  # The slot's environment must survive the create, or every LATER command run
  # in the worktree silently falls back to the compose defaults — i.e. dev's
  # container names and dev's ports, under the worktree's project name. That
  # shipped once: a bare `docker compose up -d db` in a worktree recreated the
  # db container on dev's port, and a project's `test-e2e.sh` invoked there
  # drove dev's database. `new` passing proves nothing about it, because `new`
  # always exports the environment itself.
  [[ -f "$TMP/wtfix-wt-a/.env" ]] || fail "round $round: no .env in the worktree — later commands would resolve dev's ports"
  wt_conf="$( cd "$TMP/wtfix-wt-a" && env -u WT_SUFFIX -u APP_PORT -u COMPOSE_PROJECT_NAME \
      docker compose config 2>/dev/null )"
  grep -q 'container_name: wtfix-app-a' <<<"$wt_conf" \
    || fail "round $round: clean-env compose config in the worktree does not resolve the suffixed container name; got: $(grep -E 'container_name|published' <<<"$wt_conf" | tr '\n' ' ')"
  grep -qE 'published: "470[1-9]0"' <<<"$wt_conf" \
    || fail "round $round: clean-env compose config in the worktree resolves dev's port, not this slot's; .env=[$(tr '\n' ' ' < "$TMP/wtfix-wt-a/.env")] got: $(grep -E 'published' <<<"$wt_conf" | tr '\n' ' ')"
  # ...and the main tree must be untouched by it: dev's defaults still win there.
  main_conf="$( cd "$WS" && env -u WT_SUFFIX -u APP_PORT -u COMPOSE_PROJECT_NAME \
      docker compose config 2>/dev/null )"
  grep -q 'container_name: wtfix-app$' <<<"$main_conf" \
    || fail "round $round: the main tree no longer resolves its own defaults; got: $(grep -E 'container_name|published' <<<"$main_conf" | tr '\n' ' ')"

  bash "$WT" down a >/dev/null 2>&1 || fail "round $round: down failed"
  bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
    || { fail "round $round: RESIDUE after teardown"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
  [[ "$(claims)" == "0" ]] || fail "round $round: slot claim not released"
  [[ -e "$TMP/wtfix-wt-a" ]] && fail "round $round: worktree directory survived"
done

# --- 2. four concurrent creates must take four DISTINCT slots ---------------
for s in a b c d; do ( bash "$WT" new "$s" --branch "feat/$s" >/dev/null 2>&1 ) & done
wait
got="$(cat "$SLOTDIR"/slot-* 2>/dev/null | awk '{print $2}' | sort | tr '\n' ' ')"
n_claims="$(claims)"
[[ "$n_claims" == "4" ]] || fail "concurrent: expected 4 distinct slot claims, got $n_claims (slugs: $got)"
for s in a b c d; do
  docker ps -q --filter "label=com.docker.compose.project=wtfix-wt-$s" | grep -q . \
    || fail "concurrent: worktree '$s' has no running container — a slot collision would look exactly like this"
done

# distinct published ports, one per slot
n_ports="$(docker ps --filter "name=wtfix-app-" --format '{{.Ports}}' | grep -oE ':[0-9]+->' | sort -u | wc -l | tr -d ' ')"
[[ "$n_ports" == "4" ]] || fail "concurrent: expected 4 distinct host ports, got $n_ports"

# --- 3. concurrent teardown returns to baseline exactly ---------------------
for s in a b c d; do ( bash "$WT" down "$s" >/dev/null 2>&1 ) & done
wait
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "concurrent: RESIDUE after tearing 4 down"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
[[ "$(claims)" == "0" ]] || fail "concurrent: $(claims) slot claim(s) leaked"

# --- 3b. up recovers a stack that went down, and `down` on a DIRTY worktree
#         must not strand it ---------------------------------------------------
#
# The state an agent most needs to resolve: git refuses to remove a dirty
# worktree AFTER the stack is already down, so the directory is left with no
# stack. Before `up` existed there was no way back, and the slot had already
# been released — so the limbo could not even be resumed deterministically.
bash "$WT" new a --branch feat/dirty >/dev/null 2>&1 || fail "dirty: create failed"
echo "uncommitted" > "$TMP/wtfix-wt-a/svc/UNCOMMITTED.txt"

bash "$WT" down a >/dev/null 2>&1 && fail "dirty: down must fail rather than discard uncommitted work"
[[ -d "$TMP/wtfix-wt-a" ]] || fail "dirty: down must not remove a worktree holding uncommitted work"
[[ "$(claims)" == "1" ]] || fail "dirty: the slot must stay claimed so 'up' can resume it deterministically"

rec="$(bash "$WT" list --porcelain 2>/dev/null | grep '^a	')"
[[ "$(cut -f5 <<<"$rec")" == "YES" ]] || fail "list --porcelain must report the worktree as DIRTY, got: $rec"
[[ "$(cut -f4 <<<"$rec")" == "down" ]] || fail "list --porcelain must report the stack as down, got: $rec"

bash "$WT" up a >/dev/null 2>&1 || fail "up: must bring a downed stack back"
docker ps -q --filter "label=com.docker.compose.project=wtfix-wt-a" | grep -q . \
  || fail "up: no running container after resume"
[[ "$(bash "$WT" list --porcelain 2>/dev/null | grep '^a	' | cut -f4)" == up:* ]] \
  || fail "list must report the stack as up after 'up'"

bash "$WT" down a --force >/dev/null 2>&1 || fail "down --force: must remove a dirty worktree when explicitly asked"
[[ -e "$TMP/wtfix-wt-a" ]] && fail "down --force: directory survived"
[[ "$(claims)" == "0" ]] || fail "down --force: claim not released"
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "dirty/up cycle: RESIDUE"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }

# --- 4. a failed create must roll back completely ---------------------------
# WT_READY_CMD that can never succeed: the stack starts, readiness never comes.
cat >> "$WS/.context/worktrees/config.env" <<'ENV'
WT_READY_CMD='false'
ENV
# shorten the wait by pointing the readiness loop at a stack that is already up
( bash "$WT" new fail1 --branch feat/fail1 ) >/dev/null 2>&1
rc=$?
[[ "$rc" -ne 0 ]] || fail "rollback: a create whose readiness never succeeds must exit non-zero"
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "rollback: a FAILED create left resources behind"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
[[ -e "$TMP/wtfix-wt-fail1" ]] && fail "rollback: failed create left its directory behind"
[[ "$(claims)" == "0" ]] || fail "rollback: failed create leaked its slot claim"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — worktree lifecycle: repeatable cycle, 4 concurrent creates on distinct slots, zero residue, complete rollback"
