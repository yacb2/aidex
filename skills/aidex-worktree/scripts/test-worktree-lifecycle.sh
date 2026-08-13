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

# Exit 2, never 0, on every path that does not execute the suite. A caller
# gating on this script cannot tell "passed" from "never ran" if both are 0 —
# which is precisely how a stale lock kept it green for seventeen days.
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "SKIP — docker unavailable; the worktree mechanism cannot be exercised"
  exit 2
fi

# --- singleton -------------------------------------------------------------
#
# The fixture's project name, its slot directory and its host ports are all
# fixed, so two instances of this test destroy each other: one's purge step
# removes the other's containers, and both draw from the same slot claims. That
# is a harness error, not a scenario to support — fail loudly instead of
# emitting failures that look like defects in the code under test. (Observed:
# a stray background run overlapping a suite run produced exactly that.)
#
# The lock is anchored to its owner PID, because a bare `mkdir` lock cannot tell
# "a run is in progress" from "a run died here in July". One that did exactly
# that disabled this suite for seventeen days while reporting success.
RUNLOCK="${AIDEX_WT_LIFECYCLE_LOCK:-${TMPDIR:-/tmp}/aidex-wt-lifecycle-test.lock}"
# A SYMLINK, not a directory, and the owner PID is its target: `ln -s` publishes
# the name and the owner in one atomic step. `mkdir` then writing a pid file
# leaves a window in which a second instance sees an ownerless lock, calls it
# stale and takes it — reintroducing the double-run this guard exists to stop.
lock_owner() { readlink "$RUNLOCK" 2>/dev/null; }
if ! ln -s "$$" "$RUNLOCK" 2>/dev/null; then
  owner="$(lock_owner)"
  if [[ "$owner" =~ ^[0-9]+$ ]] && kill -0 "$owner" 2>/dev/null; then
    echo "SKIP — another test-worktree-lifecycle.sh is running (lock: $RUNLOCK, pid $owner)."
    echo "       Two instances share the wtfix fixture and would corrupt each other."
    exit 2
  fi
  # Stale: the owner is gone, or the lock is a bare directory from before PID
  # anchoring and names nobody — the seventeen-day shape. Reclaim, then let
  # `ln -s` arbitrate again so a real racer that wins it is still refused.
  #
  # Residual, knowingly left: two instances that find the SAME stale lock at the
  # same instant can both reclaim it. Closing that needs more than a symlink,
  # and the payoff is small — a live owner (the case that actually happens when
  # someone runs the suite twice) is refused atomically above, and a double-run
  # fails loudly rather than silently, which is what this guard asks for.
  echo "note: reclaiming a stale lock at $RUNLOCK (owner ${owner:-unrecorded})" >&2
  rm -rf "$RUNLOCK"
  if ! ln -s "$$" "$RUNLOCK" 2>/dev/null; then
    echo "SKIP — another test-worktree-lifecycle.sh took the lock (lock: $RUNLOCK)."
    exit 2
  fi
fi

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
WS="$TMP/wtfix"
STRAY_PIDS=""
cleanup() {
  # First, whatever the host-process cases spawned. A test about processes that
  # outlive a teardown must not itself leak one, and a run that dies mid-case
  # would otherwise leave a `sleep 600` holding a deleted directory — this
  # plan's own subject.
  for p in $STRAY_PIDS; do kill "$p" 2>/dev/null; done
  for s in a b c d fail1; do ( cd "$WS" 2>/dev/null && bash "$WT" down "$s" ) >/dev/null 2>&1; done
  rm -rf "$TMP" "${TMPDIR:-/tmp}/aidex-wt-slots-wtfix"
  [[ -n "${RUNLOCK:-}" ]] && rm -rf "$RUNLOCK"
}
trap cleanup EXIT

# Test seam: test-lifecycle-lock.sh exercises the singleton guard above, and a
# case that costs a full Docker cycle would not get run. Stop here, having
# proved acquisition, and let the trap release the lock.
if [[ -n "${AIDEX_WT_LIFECYCLE_LOCK_PROBE:-}" ]]; then
  echo "LOCK-ACQUIRED $RUNLOCK"
  exit 0
fi

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

# The pristine config, so a case that needs an extra line writes base+line and
# restores rather than appending onto whatever the previous case appended.
CONF="$WS/.context/worktrees/config.env"
CONF_BASE="$TMP/config.base.env"
cp "$CONF" "$CONF_BASE"

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

# --- 3c. WT_PRE_DOWN_CMD: the project's own stop recipe ----------------------
#
# `down` reclaims only what Docker owns, so a hybrid stack keeps running the
# half that is a host process. This hook is where a project says how to stop it.
# Three things must hold and none of them shows up in a smoke test: it runs
# BEFORE the teardown, it runs with the worktree's own cwd and environment, and
# its failure does not abort the teardown.
#
# The hook is a script file, not an inline command, so the fixture does not have
# to nest three levels of quoting inside a config line to write a sentinel.
SENTINEL="$TMP/pre-down.sentinel"
cat > "$TMP/pre-down.sh" <<'HOOK'
{ pwd -P
  echo "$COMPOSE_PROJECT_NAME"
  echo "$APP_PORT"
  # The live container count is the ordering proof: it can only be non-zero if
  # the hook ran before `docker compose down`.
  docker ps -q --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" | wc -l | tr -d ' '
} > "$(dirname "$0")/pre-down.sentinel"
HOOK

{ cat "$CONF_BASE"; echo "WT_PRE_DOWN_CMD='bash $TMP/pre-down.sh'"; } > "$CONF"
grep -qF "WT_PRE_DOWN_CMD='bash $TMP/pre-down.sh'" "$CONF" \
  || fail "pre-down: the fixture's own config line did not survive quoting: $(grep WT_PRE_DOWN_CMD "$CONF")"

bash "$WT" new a --branch feat/predown >/dev/null 2>&1 || fail "pre-down: create failed"
bash "$WT" down a >/dev/null 2>&1 || fail "pre-down: down failed"
if [[ ! -f "$SENTINEL" ]]; then
  fail "pre-down: WT_PRE_DOWN_CMD never ran"
else
  h_cwd="$(sed -n 1p "$SENTINEL")"; h_proj="$(sed -n 2p "$SENTINEL")"
  h_port="$(sed -n 3p "$SENTINEL")"; h_live="$(sed -n 4p "$SENTINEL")"
  [[ "$h_cwd" == "$TMP/wtfix-wt-a" ]] \
    || fail "pre-down: the hook ran in '$h_cwd', not in the worktree"
  [[ "$h_proj" == "wtfix-wt-a" ]] \
    || fail "pre-down: the hook did not receive COMPOSE_PROJECT_NAME, got '$h_proj'"
  [[ "$h_port" =~ ^470[1-9]0$ ]] \
    || fail "pre-down: the hook did not receive the slot's port — a stop recipe reading it would target dev; got '$h_port'"
  [[ "${h_live:-0}" -ge 1 ]] \
    || fail "pre-down: the stack was already gone when the hook ran; it must run BEFORE the teardown"
fi
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "pre-down: RESIDUE after a teardown with a hook"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
[[ "$(claims)" == "0" ]] || fail "pre-down: slot claim not released"

# A hook that fails is reported and the Docker teardown still happens: the hook
# is the project's best effort, not a precondition of reclaiming Docker's half.
{ cat "$CONF_BASE"; echo "WT_PRE_DOWN_CMD='exit 1'"; } > "$CONF"
bash "$WT" new a --branch feat/predown-fail >/dev/null 2>&1 || fail "pre-down/fail: create failed"
out="$(bash "$WT" down a 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "pre-down/fail: a failing hook must not abort the teardown (exit $rc)"
grep -q 'WT_PRE_DOWN_CMD failed' <<<"$out" \
  || fail "pre-down/fail: the failure must be reported, not swallowed; got: $(tr '\n' ' ' <<<"$out")"
[[ -e "$TMP/wtfix-wt-a" ]] && fail "pre-down/fail: the worktree directory survived"
[[ "$(claims)" == "0" ]] || fail "pre-down/fail: slot claim not released"
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "pre-down/fail: RESIDUE after a teardown whose hook failed"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }

# And it is skipped, not failed, when the directory is already gone — `down`
# runs against a removed worktree on the failed-teardown recovery path.
#
# "Skipped" has to be asserted as the ABSENCE OF A COMPLAINT, not the absence of
# the sentinel: an unguarded hook cannot write one either, because its `cd`
# fails first. Only the warning tells the two apart.
rm -f "$SENTINEL"
{ cat "$CONF_BASE"; echo "WT_PRE_DOWN_CMD='bash $TMP/pre-down.sh'"; } > "$CONF"
out="$(bash "$WT" down a 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "pre-down/gone: down against an already-removed worktree must still succeed (exit $rc)"
grep -q 'WT_PRE_DOWN_CMD failed' <<<"$out" \
  && fail "pre-down/gone: the hook was attempted with no directory to run in, and reported as a failure"
[[ -e "$SENTINEL" ]] && fail "pre-down/gone: the hook ran with no worktree directory to run in"
cp "$CONF_BASE" "$CONF"

# --- 3d. a host process that survives the teardown must be REPORTED ----------
#
# The field bug: `down` reclaims Docker's half, prints "removed", and exits 0
# while a dev server started on the host keeps holding the slot's port and the
# worktree directory it was started from. No hook is configured here on purpose
# — the scan is the safety net for whatever the hook did not think to stop.
#
# `exec` so the PID that `$!` reports is the PID that ends up holding the cwd,
# and `trap - EXIT` so killing it never runs this script's own cleanup in the
# forked child (that deleted $TMP mid-run once already).
PORT_PROBE=47999
if lsof -nP -iTCP:"$PORT_PROBE" -sTCP:LISTEN >/dev/null 2>&1; then
  fail "stray: port $PORT_PROBE is already in use; the port column cannot be asserted against a known value"
elif ! command -v python3 >/dev/null 2>&1; then
  fail "stray: python3 is required to hold a listening port for this case"
else
  bash "$WT" new a --branch feat/stray >/dev/null 2>&1 || fail "stray: create failed"
  ( trap - EXIT; cd "$TMP/wtfix-wt-a" && exec python3 -m http.server "$PORT_PROBE" --bind 127.0.0.1 ) >/dev/null 2>&1 &
  stray_pid=$!
  STRAY_PIDS="$STRAY_PIDS $stray_pid"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    lsof -nP -a -p "$stray_pid" -iTCP:"$PORT_PROBE" -sTCP:LISTEN >/dev/null 2>&1 && break
    sleep 0.5
  done

  out="$(bash "$WT" down a 2>&1)"; rc=$?
  # Exit 0 is deliberate and load-bearing: the Docker teardown DID complete, and
  # every `down && …` caller in the field depends on that. The report is the
  # thing that must change, not the exit code.
  [[ "$rc" -eq 0 ]] || fail "stray: down must still exit 0 (exit $rc)"
  grep -qE "pid $stray_pid( |\$)" <<<"$out" \
    || fail "stray: down reported success over a live process holding the worktree; pid $stray_pid absent from: $(tr '\n' ' ' <<<"$out")"
  grep -qE "pid $stray_pid .*port $PORT_PROBE" <<<"$out" \
    || fail "stray: the survivor's port is what tells an operator WHY the next 'new' will collide; not reported in: $(tr '\n' ' ' <<<"$out")"
  kill -0 "$stray_pid" 2>/dev/null \
    || fail "stray: the process died on its own — the case proves nothing about reporting"

  # The field shape, and the reason the scan resolves its path through the
  # PARENT: `down` re-run against an already-removed worktree, with the process
  # still holding the deleted path. macOS does not mark a deleted cwd, so the
  # only thing that finds it is a prefix match on a path that is canonical even
  # though nothing is there any more.
  out="$(bash "$WT" down a 2>&1)"
  grep -qE "pid $stray_pid( |\$)" <<<"$out" \
    || fail "stray/removed-dir: a process holding the DELETED worktree path is invisible on a re-run; pid $stray_pid absent from: $(tr '\n' ' ' <<<"$out")"

  kill "$stray_pid" 2>/dev/null; wait "$stray_pid" 2>/dev/null

  # --reap: opt-in, by PID, and only the PIDs the scan reported.
  bash "$WT" new a --branch feat/stray-reap >/dev/null 2>&1 || fail "reap: create failed"
  ( trap - EXIT; cd "$TMP/wtfix-wt-a" && exec sleep 600 ) &
  reap_pid=$!
  STRAY_PIDS="$STRAY_PIDS $reap_pid"
  sleep 1
  out="$(bash "$WT" down a --reap 2>&1)"; rc=$?
  [[ "$rc" -eq 0 ]] || fail "reap: down --reap must exit 0 (exit $rc)"
  grep -qE "pid $reap_pid( |\$)" <<<"$out" || fail "reap: the killed process must still be reported, not silently reaped"
  for _ in 1 2 3 4 5 6; do kill -0 "$reap_pid" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$reap_pid" 2>/dev/null && fail "reap: pid $reap_pid survived --reap"
  bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
    || { fail "stray/reap: RESIDUE"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
  [[ "$(claims)" == "0" ]] || fail "stray/reap: slot claim not released"
fi

# --- 3e. a resurrected directory is not a worktree ---------------------------
#
# The field shape: a dev server that outlived the teardown rewrote
# `frontend/.vite/deps/`, recreating the tree it had been started in. `list` then
# showed a row for a directory git has never heard of, and an agent reading that
# row would try to `up` something that does not exist.
bash "$WT" new a --branch feat/stray-dir >/dev/null 2>&1 || fail "straydir: create failed"
bash "$WT" down a >/dev/null 2>&1 || fail "straydir: down failed"
mkdir -p "$TMP/wtfix-wt-a/svc/.vite/deps"
: > "$TMP/wtfix-wt-a/svc/.vite/deps/chunk.js"
rec="$(bash "$WT" list --porcelain 2>/dev/null | grep '^a	' || true)"
[[ "$(cut -f6 <<<"$rec")" == STRAY-DIR:* ]] \
  || fail "straydir: a directory with neither a git worktree nor a slot claim must be marked stray, got: [$rec]"
rm -rf "$TMP/wtfix-wt-a"

# The false positive a naive fix introduces, and the reason the discriminator
# needs BOTH signals absent: --keep-dir leaves the directory AND the claim on
# purpose, and that worktree is ordinary. So does a failed removal.
bash "$WT" new b --branch feat/keepdir >/dev/null 2>&1 || fail "keepdir: create failed"
bash "$WT" down b --keep-dir >/dev/null 2>&1 || fail "keepdir: down --keep-dir failed"
rec="$(bash "$WT" list --porcelain 2>/dev/null | grep '^b	' || true)"
[[ "$(cut -f6 <<<"$rec")" == STRAY-DIR:* ]] \
  && fail "keepdir: a --keep-dir worktree must still list as a worktree, got: [$rec]"
[[ "$(cut -f4 <<<"$rec")" == "down" ]] \
  || fail "keepdir: the stack column vocabulary must be unchanged for a real worktree, got: [$rec]"
bash "$WT" down b >/dev/null 2>&1 || fail "keepdir: final teardown failed"
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "straydir/keepdir: RESIDUE"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
[[ "$(claims)" == "0" ]] || fail "straydir/keepdir: slot claim not released"

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
