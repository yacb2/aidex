#!/usr/bin/env bash
# test-shared-helpers.sh — pins what the helpers shared by worktree.sh,
# worktree-multi.sh and the check-*.sh scripts must keep doing, at the boundary
# each caller sees (LOOP-013 wave 17, rows worktree-s31 s38 s42).
#
# Layer: script integration with a docker stub. The observable is what reaches
# `docker compose` (its environment), the files the script writes, and the usage text
# and exit code of each script; none of it is visible to a unit of the helper alone.
#
#   s38  the compose environment (project name, suffix, slot ports) is ONE source for
#        the three commands' `env` array, the root .env and the rendered templates.
#        Per command, with a slot and without one (a --no-infra tree gets no ports,
#        never the main tree's).
#   s31  the readiness probe runs under that environment in `new` and in `up`, and a
#        probe that passes is reported as "ready after Ns" by both.
#   s42  every script that prints its own header on -h keeps printing it (all its
#        leading comment lines), with the
#        exit code it had (0 for worktree.sh -h, 2 for the rest).
#
# Run with: bash skills/worktree/tests/test-shared-helpers.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$(cd "$DIR/.." && pwd -P)"
SCRIPTS="$SKILL/scripts"
WT="$SCRIPTS/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# A failed mktemp must stop the run: an empty TMP would make `cd ""` a no-op and the
# trap below would delete the current directory.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/w17.XXXXXX")" || { echo 'FAIL: mktemp'; exit 1; }
TMP="$(cd "$TMP" && pwd -P)" || exit 1
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/bin" "$TMP/slots" "$TMP/p/.context/worktrees/env-templates/backend" "$TMP/p/backend"
LOG="$TMP/docker.log"; : > "$LOG"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sleep"
# Names the declared service so parity passes, and one container so `new`'s
# attributability check (docker ps -a by project label) finds something; logs the environment of every
# `compose up` and `compose down` so the test can read what the script passed.
cat > "$TMP/bin/docker" <<'STUB'
#!/bin/sh
case " $* " in *" --services "*) echo db ;; esac
case " $* " in *" ps -a "*) echo "$COMPOSE_PROJECT_NAME-db-1" ;; esac
case " $* " in
  *" up "*)   echo "up CP=$COMPOSE_PROJECT_NAME SUF=${WT_SUFFIX-unset} DB=${DB_PORT-unset}" >> "$DOCKER_LOG" ;;
  *" down "*) echo "down CP=$COMPOSE_PROJECT_NAME SUF=${WT_SUFFIX-unset} DB=${DB_PORT-unset}" >> "$DOCKER_LOG" ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/sleep" "$TMP/bin/docker"

# Slot 2 -> DB_PORT 6400 + 2 * 100 (WT_PORT_STRIDE default). The probe exits 0 only
# when the script ran it under that exact port, so "ready" proves the environment.
cat > "$TMP/p/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS=""
WT_SERVICES="db"
WT_PORT_VARS="DB_PORT=6400"
WT_READY_CMD='test "$DB_PORT" = 6600'
WT_ENV_RENDER="backend/env.local"
ENV
printf 'slot=${WT_SLOT} slug=${WT_SLUG} port=${DB_PORT} cp=${COMPOSE_PROJECT_NAME} suf=${WT_SUFFIX}\n' \
  > "$TMP/p/.context/worktrees/env-templates/backend/env.local.tmpl"
printf 'services:\n  db:\n    image: postgres\n' > "$TMP/p/docker-compose.yml"
( cd "$TMP/p/backend" && /usr/bin/git init -q -b main . && /usr/bin/git config user.email t@e.com \
  && /usr/bin/git config user.name t && echo env.local > .gitignore && echo x > f \
  && /usr/bin/git add -A && /usr/bin/git commit -qm i ) >/dev/null 2>&1
PROJ="$(basename "$TMP/p")"

run() { ( cd "$TMP/p" && TMPDIR="$TMP/slots" DOCKER_LOG="$LOG" PATH="$TMP/bin:$PATH" bash "$WT" "$@" 2>&1 ); }

# --- new --slot 2: env array, .env, rendered template, readiness ---------------
out="$(run new a --branch wt/a --slot 2)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "new: exit $rc: $out"
grep -qx "up CP=$PROJ-wt-a SUF=-a DB=6600" "$LOG" \
  || fail "new: compose up must run under project, suffix and slot-2 port; docker saw: $(cat "$LOG")"
grep -q 'ready after 1s' <<<"$out" || fail "new: a passing WT_READY_CMD must be reported as 'ready after 1s': $out"
# Compose ignores line order: compare as sorted sets.
want_env="$(printf '%s\n' "COMPOSE_PROJECT_NAME=$PROJ-wt-a" "WT_SUFFIX=-a" "DB_PORT=6600" | sort)"
[[ "$(sed 1d "$TMP/p-wt-a/.env" 2>/dev/null | sort)" == "$want_env" ]] \
  || fail "new: .env body must be project, suffix, ports (any order); got: $(cat "$TMP/p-wt-a/.env" 2>&1)"
[[ "$(sed 1d "$TMP/p-wt-a/backend/env.local" 2>/dev/null)" == "slot=2 slug=a port=6600 cp=$PROJ-wt-a suf=-a" ]] \
  || fail "new: rendered template must carry every slot variable; got: $(cat "$TMP/p-wt-a/backend/env.local" 2>&1)"

# --- up: the same environment and the same readiness report --------------------
: > "$LOG"
out="$(run up a)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "up: exit $rc: $out"
grep -qx "up CP=$PROJ-wt-a SUF=-a DB=6600" "$LOG" \
  || fail "up: compose up must run under project, suffix and slot-2 port; docker saw: $(cat "$LOG")"
grep -q 'ready after 1s' <<<"$out" || fail "up: a passing WT_READY_CMD must be reported as 'ready after 1s': $out"

# --- down: the slot's ports are exported to the teardown -----------------------
: > "$LOG"
out="$(run down a)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "down: exit $rc: $out"
grep -qx "down CP=$PROJ-wt-a SUF=-a DB=6600" "$LOG" \
  || fail "down: compose down must run under project, suffix and slot-2 port; docker saw: $(cat "$LOG")"

# down of a tree with no slot: owned by test-teardown-and-scope.sh #5

# --- s42: each script prints its own header and keeps its exit code ------------
check_usage() {  # check_usage <name> <expected rc> <args...>
  local name="$1" want="$2" o r; shift 2
  o="$(cd "$TMP/p" && bash "$SCRIPTS/$name" "$@" 2>/dev/null)"; r=$?   # stdout only: usage is read from a pipe
  [[ "$r" -eq "$want" ]] || fail "$name $*: exit $r, want $want"
  ! grep -q '^#' <<<"$o" || fail "$name $*: usage still carries a comment marker: $(grep -m1 '^#' <<<"$o")"
  [[ "$(sed -n 1p <<<"$o")" == "$(sed -n '2s/^# \{0,1\}//p' "$SCRIPTS/$name")" ]] \
    || fail "$name $*: first usage line must be the script's own header line; got: $(sed -n 1p <<<"$o")"
  # The header block is the leading '#' lines from line 2 on; usage prints each, once.
  local n; n="$(awk 'NR==1{next} /^#/{c++; next} {exit} END{print c+0}' "$SCRIPTS/$name")"
  [[ "$(wc -l <<<"$o" | tr -d ' ')" -eq "$n" && "$n" -gt 3 ]] \
    || fail "$name $*: usage must print all $n leading '#' lines; got $(wc -l <<<"$o" | tr -d ' '): $o"
}
check_usage worktree.sh 0 --help
check_usage worktree.sh 2 bogus
check_usage worktree-multi.sh 2
check_usage check-compose-isolation.sh 0 --help
check_usage check-worktree-ports.sh 0 --help
check_usage check-worktree-isolation.sh 0 --help
check_usage check-worktree-runner.sh 0 --help
# -h exits 0 as well (owner Q11: asking for help is not an error), in all eight scripts that print usage.
for s in check-compose-isolation check-worktree-isolation check-worktree-ports check-worktree-runner \
         docker-snapshot orphan-sweep worktree-multi check-overview; do
  check_usage "$s.sh" 0 -h
done
check_usage docker-snapshot.sh 0 --help
check_usage orphan-sweep.sh 0 --help
check_usage worktree-multi.sh 0 --help
check_usage worktree-multi.sh 0 create --help
check_usage check-overview.sh 0 --help
# An unknown option keeps exiting 2, asserted only where an option is really parsed:
# orphan-sweep.sh (argument loop) and worktree-multi.sh (argument loop after create).
( cd "$TMP/p" && bash "$SCRIPTS/orphan-sweep.sh" --no-such-option >/dev/null 2>&1 ); [[ $? -eq 2 ]] \
  || fail "orphan-sweep.sh --no-such-option: must keep exiting 2"
( cd "$TMP/p" && bash "$SCRIPTS/worktree-multi.sh" create --no-such-option >/dev/null 2>&1 ); [[ $? -eq 2 ]] \
  || fail "worktree-multi.sh create --no-such-option: must keep exiting 2"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — shared helpers: one compose environment for new/up/down/.env/templates, readiness reported by new and up, usage text and exit code per script"
