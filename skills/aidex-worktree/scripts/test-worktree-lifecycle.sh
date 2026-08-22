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

# --- 3f. --delete-branch: the branch is the last thing a teardown leaves -----
#
# Nothing in the suite ever removed it, so every finished worktree left a branch
# in each participant repo, indistinguishable from live work. `git branch -d` is
# its own merged-ness gate, so the two cases are "merged -> gone" and "unmerged
# -> kept, and SAID SO". The second is the one that matters: a silent keep is
# the same failure as a silent delete, one branch later.
branch_exists() { git -C "$WS/$1" show-ref --verify --quiet "refs/heads/$2"; }

# (a) merged: the branch carries nothing the trunk lacks, so -d accepts it.
bash "$WT" new a --branch feat/merged >/dev/null 2>&1 || fail "delete-branch: create failed"
out="$(bash "$WT" down a --delete-branch 2>&1)"
[[ -e "$TMP/wtfix-wt-a" ]] && fail "delete-branch: directory survived"
for pp in svc; do
  branch_exists "$pp" feat/merged \
    && fail "delete-branch: a merged branch survived in $pp — $(printf '%s' "$out" | tr '\n' ' ' | tail -c 200)"
done

# (b) unmerged: the branch carries a commit the trunk does not have. It must be
#     KEPT, the run must still succeed, and the branch name must appear in the
#     output — a teardown that quietly leaves work behind is how work is lost.
bash "$WT" new b --branch feat/unmerged >/dev/null 2>&1 || fail "delete-branch: create (b) failed"
echo "work" > "$TMP/wtfix-wt-b/svc/NEWFILE.txt"
git -C "$TMP/wtfix-wt-b/svc" add -A >/dev/null 2>&1
git -C "$TMP/wtfix-wt-b/svc" -c user.email=t@t -c user.name=t commit -qm "unmerged work" >/dev/null 2>&1
out="$(bash "$WT" down b --delete-branch 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "delete-branch: an unmerged branch must not fail the teardown (exit $rc)"
[[ -e "$TMP/wtfix-wt-b" ]] && fail "delete-branch: directory survived the unmerged case"
branch_exists svc feat/unmerged \
  || fail "delete-branch: an UNMERGED branch was deleted — git branch -d is the gate and it must have refused"
[[ "$out" == *"feat/unmerged"* ]] \
  || fail "delete-branch: the kept branch was not named in the output: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 200)"
git -C "$WS/svc" branch -D feat/unmerged >/dev/null 2>&1

# (c) without the flag, nothing is deleted — the default must stay off.
bash "$WT" new a --branch feat/kept >/dev/null 2>&1 || fail "delete-branch: create (c) failed"
bash "$WT" down a >/dev/null 2>&1 || fail "delete-branch: plain down failed"
branch_exists svc feat/kept \
  || fail "delete-branch: a plain 'down' deleted the branch — the flag must be opt-in"
git -C "$WS/svc" branch -D feat/kept >/dev/null 2>&1

# (d) THE WRONG-TARGET CASE. `branch --show-current` answers with whatever is
#     checked out at teardown. A worktree switched to a pre-existing main-tree
#     branch would hand that unrelated ref to the deletion, and leave the branch
#     the flag exists to remove. Silent wrong-target mutation of someone else's
#     ref, printed as success.
git -C "$WS/svc" branch colleague/review >/dev/null 2>&1
bash "$WT" new a --branch feat/created --no-infra >/dev/null 2>&1 || fail "delete-branch: create (d) failed"
git -C "$TMP/wtfix-wt-a/svc" checkout -q colleague/review 2>/dev/null
out="$(bash "$WT" down a --delete-branch 2>&1)"
branch_exists svc colleague/review \
  || fail "delete-branch: deleted 'colleague/review', a main-tree branch the worktree merely had checked out — only the CREATED branch is ever a candidate"
branch_exists svc feat/created \
  || fail "delete-branch: deleted the created branch while the checkout was elsewhere — the recorded name must match the current one"
[[ "$out" == *"not the created"* ]] \
  || fail "delete-branch: the mismatch was not reported: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 200)"
git -C "$WS/svc" branch -D colleague/review feat/created >/dev/null 2>&1

# (e) THE EMPTY-ARRAY CASE. On bash 3.2 (the macOS system shell) expanding an
#     empty array under `set -u` is fatal, so a teardown with nothing eligible
#     aborted with a raw "unbound variable" and exit 1 — over a teardown that had
#     already fully succeeded. Reached by the stranded-directory recovery path
#     that `list` itself prescribes.
bash "$WT" new a --branch feat/gone --no-infra >/dev/null 2>&1 || fail "delete-branch: create (e) failed"
rm -rf "$TMP/wtfix-wt-a"
out="$(bash "$WT" down a --delete-branch 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] \
  || fail "delete-branch: a teardown with no eligible branch must still exit 0 (got $rc): $(printf '%s' "$out" | tr '\n' ' ' | tail -c 220)"
[[ "$out" != *"unbound variable"* ]] \
  || fail "delete-branch: empty array expanded under set -u — the guard must be an else-branch"
# `rm -rf` left git's worktree registry pointing at a path that no longer exists,
# so the next `new` on this slug would hit "missing but already registered".
# That is the test's own mess, not the tool's.
git -C "$WS/svc" worktree prune >/dev/null 2>&1
git -C "$WS/svc" branch -D feat/gone >/dev/null 2>&1

# (f) A worktree created before .wt-branch existed has no recorded name. It must
#     SKIP, never fall back to the current branch — that fallback IS case (d).
bash "$WT" new a --branch feat/legacy --no-infra >/dev/null 2>&1 || fail "delete-branch: create (f) failed"
rm -f "$TMP/wtfix-wt-a/.wt-branch"
out="$(bash "$WT" down a --delete-branch 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "delete-branch: a worktree with no .wt-branch must not fail the teardown (got $rc)"
branch_exists svc feat/legacy \
  || fail "delete-branch: fell back to the current branch when .wt-branch was absent — absence must skip"
git -C "$WS/svc" branch -D feat/legacy >/dev/null 2>&1

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

# --- 5. services parity: the set is DERIVED from compose, not declared -------
#
# The defect this pins: `WT_SERVICES` was a static "db backend" and the
# instruction to override it per project lived in prose. Two of the three field
# projects with an always-on worker never did, and the symptom was silent — a
# worktree whose queue never drained, with every port check passing.
#
# Four cases, and (c) is the one that would otherwise have shipped a WRONG
# blocker: a naive "must equal the profile-less set" rule flags a healthy
# worktree, because a profile-gated service can legitimately be up here.
COMPOSE_BASE="$TMP/compose.base.yml"
cp "$WS/docker-compose.yml" "$COMPOSE_BASE"
cp "$CONF_BASE" "$CONF"

write_compose_with_extra() {  # write_compose_with_extra [profiles-line]
  { sed '/^volumes:/,$d' "$COMPOSE_BASE"
    echo '  extra:'
    echo '    image: busybox:latest'
    echo '    container_name: wtfix-extra${WT_SUFFIX:-}'
    echo '    command: sh -c "while true; do sleep 3600; done"'
    [[ -n "${1:-}" ]] && printf '    profiles: [%s]\n' "$1"
    echo 'volumes:'
    echo '  appdata:'
  } > "$WS/docker-compose.yml"
}

# (a) a profile-less service the config does not list -> refuse, create NOTHING.
write_compose_with_extra ""
out="$(bash "$WT" new p1 --branch feat/p1 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "parity(a): a profile-less service missing from WT_SERVICES must refuse"
grep -q 'extra' <<<"$out" || fail "parity(a): the refusal must NAME the service, got: $out"
grep -q 'WT_SERVICES="app extra"' <<<"$out" \
  || fail "parity(a): the refusal must print the exact line to add, got: $out"
[[ -e "$TMP/wtfix-wt-p1" ]] && fail "parity(a): a refusal must create nothing"
[[ "$(claims)" == "0" ]] || fail "parity(a): a refusal must claim no slot"

# (b) the same service excluded WITH a reason -> the escape works.
cp "$CONF_BASE" "$CONF"
echo 'WT_SERVICES_EXCLUDE="extra # busybox filler, nothing depends on it"' >> "$CONF"
bash "$WT" new p2 --branch feat/p2 >/dev/null 2>&1 \
  || fail "parity(b): WT_SERVICES_EXCLUDE with a reason must allow the create"

# (a2) the SAME refusal, reached through `up` rather than `new`. Not redundant:
# `up` and `new` are separate call sites, and deleting the one in `up` leaves
# every other case in this file green — verified by mutation on 2026-08-21.
# `up` is also the path an EXISTING worktree takes when the compose file gains a
# service later, which is the drift this check exists to catch.
slot_before="$(cat "$TMP/wtfix-wt-p2/.wt-slot" 2>/dev/null)"
cp "$CONF_BASE" "$CONF"          # drop the EXCLUDE line; `extra` is now undeclared
out="$(bash "$WT" up p2 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "parity(a2): 'up' must refuse a profile-less service that is unlisted"
grep -q 'extra' <<<"$out" || fail "parity(a2): the refusal must NAME the service, got: $out"
[[ "$(cat "$TMP/wtfix-wt-p2/.wt-slot" 2>/dev/null)" == "$slot_before" ]] \
  || fail "parity(a2): a refusal must come BEFORE the slot re-claim, not after"

cp "$CONF_BASE" "$CONF"
echo 'WT_SERVICES_EXCLUDE="extra # busybox filler, nothing depends on it"' >> "$CONF"
bash "$WT" down p2 >/dev/null 2>&1 || fail "parity(b): teardown failed"

# (b2) ...and WITHOUT a reason it is itself a refusal. An escape nobody has to
# justify becomes the default, which is how the original prose failed.
cp "$CONF_BASE" "$CONF"
echo 'WT_SERVICES_EXCLUDE="extra"' >> "$CONF"
out="$(bash "$WT" new p3 --branch feat/p3 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "parity(b2): WT_SERVICES_EXCLUDE with no '# reason' must refuse"
grep -qi 'reason' <<<"$out" || fail "parity(b2): the refusal must say a reason is required, got: $out"

# (c) THE CASE THAT WOULD HAVE SHIPPED A WRONG BLOCKER.
# `extra` is profile-gated and RUNNING, declared only in WT_SERVICES_BY_HOOK and
# deliberately NOT in WT_SERVICES. A healthy worktree looks exactly like this —
# in the field it is `backend-test`, started by the E2E run. Parity must PASS.
cp "$CONF_BASE" "$CONF"
echo 'WT_SERVICES_BY_HOOK="extra # started by the E2E run, not by WT_SERVICES"' >> "$CONF"
write_compose_with_extra "e2e"
bash "$WT" new p4 --branch feat/p4 >/dev/null 2>&1 \
  || fail "parity(c): a BY_HOOK service must not be required in WT_SERVICES"
( cd "$TMP/wtfix-wt-p4" && docker compose --profile e2e up -d extra ) >/dev/null 2>&1 \
  || fail "parity(c): could not start the profile-gated service"
out="$(bash "$WT" up p4 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "parity(c): a RUNNING BY_HOOK service must not fail the running check, got: $out"

# (d) the same service running, declared NOWHERE -> the running check fires.
# Without this, WT_SERVICES_BY_HOOK is unfalsifiable: deleting the key would
# break no test. In the field this is echo_lab's `worker`, whose `ai` profile
# makes paid API calls if someone leaves it up.
cp "$CONF_BASE" "$CONF"
out="$(bash "$WT" up p4 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "parity(d): an undeclared profile-gated service running here must fail"
grep -q 'extra' <<<"$out" || fail "parity(d): the failure must NAME the service, got: $out"
grep -q 'WT_SERVICES_BY_HOOK' <<<"$out" \
  || fail "parity(d): the failure must print the line that declares it, got: $out"

bash "$WT" down p4 >/dev/null 2>&1 || fail "parity: teardown of p4 failed"
cp "$COMPOSE_BASE" "$WS/docker-compose.yml"
cp "$CONF_BASE" "$CONF"
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "parity: RESIDUE after the parity cases"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
[[ "$(claims)" == "0" ]] || fail "parity: slot claim not released"

# --- 6. WT_ENV_RENDER: slot-dependent host env files are generated ----------
#
# The defect: worktree.sh generated the root .env for Compose and stopped, so the
# HOST half's env file was hand-written per worktree. The two live echo_lab
# worktrees held two different versions, one missing the warning that keeps the
# other working. Neither WT_LINKS nor WT_COPIES can supply it -- both carry the
# main tree's ports.
cp "$CONF_BASE" "$CONF"
mkdir -p "$WS/.context/worktrees/env-templates/svc"
cat > "$WS/.context/worktrees/env-templates/svc/.env.local.tmpl" <<'TMPL'
APP_URL=http://localhost:${APP_PORT}/api
SLOT=${WT_SLOT}
TMPL
printf '.env.local\n' > "$WS/svc/.gitignore"
git -C "$WS/svc" -c user.email=t@t -c user.name=t add .gitignore >/dev/null 2>&1
git -C "$WS/svc" -c user.email=t@t -c user.name=t commit -q -m gitignore >/dev/null 2>&1
echo 'WT_ENV_RENDER="svc/.env.local"' >> "$CONF"

# (a) the rendered file carries THIS slot's port, on two different slots.
render_port_for() {  # render_port_for <slug> <slot>
  bash "$WT" new "$1" --branch "feat/$1" --slot "$2" >/dev/null 2>&1 \
    || { fail "render($1): create failed"; return 1; }
  sed -n 's/^APP_URL=http:\/\/localhost:\([0-9]*\)\/api$/\1/p' "$TMP/wtfix-wt-$1/svc/.env.local"
}
p1="$(render_port_for r1 3)"
p2="$(render_port_for r2 4)"
[[ "$p1" == "47030" ]] || fail "render(a): slot 3 must render APP_PORT=47030, got '$p1'"
[[ "$p2" == "47040" ]] || fail "render(a): slot 4 must render APP_PORT=47040, got '$p2'"
[[ "$p1" != "$p2" ]] || fail "render(a): two slots rendered the SAME port -- the template is not slot-aware"

# (b) the do-not-edit header, same guarantee the root .env carries.
head -1 "$TMP/wtfix-wt-r1/svc/.env.local" | grep -q 'do not edit' \
  || fail "render(b): the rendered file must carry the generated/do-not-edit header"

# (c) a hand-edited file is NOT silently clobbered on `up`.
echo 'HAND EDITED' > "$TMP/wtfix-wt-r1/svc/.env.local"
out="$(bash "$WT" up r1 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "render(c): a file worktree.sh did not write must not be overwritten"
grep -qi 'refusing to overwrite' <<<"$out" || fail "render(c): wrong refusal, got: $out"
bash "$WT" down r1 >/dev/null 2>&1 || fail "render: teardown r1 failed"
bash "$WT" down r2 >/dev/null 2>&1 || fail "render: teardown r2 failed"

# (d) a template naming an unknown variable fails LOUDLY and creates nothing.
# A hole rendered as an empty string is worse than a failed create: the file
# looks right and the app fails somewhere else entirely.
cat > "$WS/.context/worktrees/env-templates/svc/.env.local.tmpl" <<'TMPL'
APP_URL=http://localhost:${APP_PORT}/api
OOPS=${NO_SUCH_VARIABLE}
TMPL
out="$(bash "$WT" new r3 --branch feat/r3 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "render(d): an undefined template variable must fail the create"
grep -q 'NO_SUCH_VARIABLE' <<<"$out" || fail "render(d): the failure must NAME the variable, got: $out"
[[ -e "$TMP/wtfix-wt-r3" ]] && fail "render(d): a failed render left its directory behind"

# (e) a destination that is NOT gitignored is refused. `git worktree remove`
# refuses a tree holding untracked non-ignored files, so this would build a
# worktree that can never be torn down -- surfacing at teardown, not at create.
cat > "$WS/.context/worktrees/env-templates/svc/.env.local.tmpl" <<'TMPL'
APP_URL=http://localhost:${APP_PORT}/api
TMPL
: > "$WS/svc/.gitignore"
git -C "$WS/svc" -c user.email=t@t -c user.name=t commit -aqm 'unignore' >/dev/null 2>&1
out="$(bash "$WT" new r4 --branch feat/r4 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "render(e): a non-gitignored destination must be refused"
grep -qi 'gitignored' <<<"$out" || fail "render(e): the refusal must say why, got: $out"

printf '.env.local\n' > "$WS/svc/.gitignore"
git -C "$WS/svc" -c user.email=t@t -c user.name=t commit -aqm 'reignore' >/dev/null 2>&1
cp "$CONF_BASE" "$CONF"
bash "$SNAP" diff "$BASE" >/dev/null 2>&1 \
  || { fail "render: RESIDUE after the WT_ENV_RENDER cases"; bash "$SNAP" diff "$BASE" 2>&1 | sed 's/^/    /'; }
[[ "$(claims)" == "0" ]] || fail "render: slot claim not released"

# --- 7. --no-infra starts no stack, so no services-parity refusal applies ----
# Code review, 2026-08-21: assert_services_declared sat ~114 lines above the
# --no-infra early return, so a code-only checkout hard-refused over services it
# would never have started. Nothing covered --no-infra at all.
cp "$CONF_BASE" "$CONF"
write_compose_with_extra ""          # a profile-less service NOT in WT_SERVICES
bash "$WT" new codeonly --branch feat/codeonly --no-infra >/dev/null 2>&1 \
  || fail "no-infra: a code-only checkout must not be refused over services it never starts"
[[ -d "$TMP/wtfix-wt-codeonly" ]] || fail "no-infra: worktree directory missing"
bash "$WT" down codeonly >/dev/null 2>&1 || fail "no-infra: teardown failed"
cp "$COMPOSE_BASE" "$WS/docker-compose.yml"
cp "$CONF_BASE" "$CONF"

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
echo "OK — worktree lifecycle: repeatable cycle, 4 concurrent creates on distinct slots, services parity derived + refused, slot env files rendered, zero residue, complete rollback"
