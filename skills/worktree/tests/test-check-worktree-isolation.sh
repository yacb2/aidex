#!/usr/bin/env bash
# test-check-worktree-isolation.sh — the umbrella's own honesty.
#
# The umbrella adds no checking logic, so it has no findings of its own to test.
# What it CAN get wrong is its verdict line, and both ways it can are here.
#
# Lives in tests/, not scripts/: run-all.sh treats every
# skills/worktree/scripts/test-*.sh as Docker-dependent. Every fixture
# below is deliberately compose-less, so nothing here needs a daemon and the
# umbrella's own sequencing runs in the DEFAULT suite.
#
# Run with: bash skills/worktree/tests/test-check-worktree-isolation.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHECK="$DIR/../scripts/check-worktree-isolation.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# --- 1. a project with no worktree config is not "every surface holds" ------
# Each sub-check returns 0 when it has nothing to examine, so the umbrella
# aggregated three vacuous zeros into a full green verdict for a project that
# has no worktree setup at all. The census path already refused this; the
# single-project path did not.
p="$TMP/bare"; mkdir -p "$p/.git"
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "bare: a project with no worktree config must NOT report every surface holding, got: $out"
grep -qi 'nothing was checked' <<<"$out" || fail "bare: must say it examined nothing, got: $out"

# --- 2. do not claim compose was verified when it never ran -----------------
# The compose check is gated on the literal filename `docker-compose.yml`, but
# the success line named compose unconditionally. A project using `compose.yaml`
# — or none at all — was told its compose addressing holds when that surface was
# never looked at.
p="$TMP/nocompose"; mkdir -p "$p/.context/worktrees" "$p/backend"
cat > "$p/.context/worktrees/config.env" <<'ENV'
WT_PARTICIPANTS="backend"
WT_LINKS="dev.sh"
WT_PORT_VARS="BACKEND_PORT=8401"
ENV
cat > "$p/dev.sh" <<'SH'
#!/usr/bin/env bash
BACKEND_PORT=${BACKEND_PORT:-8400}
SH
out="$(bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "nocompose: the other surfaces are clean, so this must pass, got: $out"
grep -qi 'compose' <<<"$out" && ! grep -qi 'no compose file' <<<"$out" \
  && fail "nocompose: must not claim compose holds when no compose file was found, got: $out"

# --- 3. compose cells, against a stub `docker` (no daemon needed) -----------
# The stub answers `info`, and renders a one-service stack whose container_name
# varies with $MY_SFX (and with $WT_SUFFIX unless FAKE_ONLY_MYSFX is set).
# FAKE_INFO_RC makes the daemon unreachable;
# FAKE_NOINTERP_FAIL makes the --no-interpolate render fail (an old compose).
mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'SH'
#!/usr/bin/env bash
case "$1" in
  info) exit "${FAKE_INFO_RC:-0}" ;;
  compose)
    if [[ " $* " == *" --no-interpolate "* ]]; then
      [[ -n "${FAKE_NOINTERP_FAIL:-}" ]] && exit 1
      printf '{"services":{"api":{"image":"x","container_name":"cn","ports":["${P:-8000}:8000"]}}}'
    else
      sfx="${MY_SFX:-}${WT_SUFFIX:-}"; [[ -n "${FAKE_ONLY_MYSFX:-}" ]] && sfx="${MY_SFX:-}"
      [[ -n "${FAKE_FIXED_NAME:-}" ]] && sfx=""
      printf '{"services":{"api":{"image":"x","container_name":"cn%s","ports":["8000:8000"]}}}' "$sfx"
    fi ;;
esac
SH
chmod +x "$TMP/bin/docker"
mk_compose_project() {  # mk_compose_project <name> <extra config line>
  local d="$TMP/$1"
  mkdir -p "$d/.context/worktrees" "$d/backend"
  printf 'WT_PARTICIPANTS="backend"\nWT_LINKS="dev.sh"\nWT_PORT_VARS="BACKEND_PORT=8401"\n%s\n' "$2" \
    > "$d/.context/worktrees/config.env"
  printf '#!/usr/bin/env bash\nBACKEND_PORT=${BACKEND_PORT:-8400}\n' > "$d/dev.sh"
  : > "$d/docker-compose.yml"
  echo "$d"
}

# 3a. Docker unreachable: the compose check skips itself (exit 0), and the
# umbrella used to count that as a pass and say compose holds.
p="$(mk_compose_project nodaemon "")"
out="$(PATH="$TMP/bin:$PATH" FAKE_INFO_RC=1 bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "nodaemon: the other surfaces are clean, so this must pass, got: $out"
grep -q 'compose, host ports and test runners all hold' <<<"$out" \
  && fail "nodaemon: must not claim compose holds when Docker was unavailable, got: $out"
grep -qi 'compose.*not checked' <<<"$out" || fail "nodaemon: must say compose was not checked, got: $out"

# 3a'. The census path must not claim every surface holds when Docker was down.
CROOT="$TMP/census-nodaemon"; mkdir -p "$CROOT"; cp -R "$p" "$CROOT/"
out="$(PATH="$TMP/bin:$PATH" FAKE_INFO_RC=1 AIDEX_PROJECTS_DIR="$CROOT" bash "$CHECK" --census 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "census-nodaemon: the other surfaces are clean, so this must pass, got: $out"
grep -q 'every surface holds' <<<"$out" \
  && fail "census-nodaemon: must not claim every surface holds when Docker was unavailable, got: $out"
grep -q 'compose was not checked' <<<"$out" || fail "census-nodaemon: must say compose was not checked, got: $out"
out="$(PATH="$TMP/bin:$PATH" FAKE_INFO_RC=0 AIDEX_PROJECTS_DIR="$CROOT" bash "$CHECK" --census 2>&1)"; rc=$?
grep -q 'every surface holds' <<<"$out" || fail "census-daemon-up: must say every surface holds, got: $out"

# 3a''. A wedged daemon (info hangs) is bounded and reads as unavailable.
mkdir -p "$TMP/slowbin"
printf '#!/usr/bin/env bash\n[[ "$1" == info ]] && sleep 5\nexit 0\n' > "$TMP/slowbin/docker"
chmod +x "$TMP/slowbin/docker"
t0=$SECONDS
out="$(PATH="$TMP/slowbin:$PATH" AIDEX_DOCKER_TIMEOUT=1 bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ $((SECONDS - t0)) -lt 4 ]] || fail "wedged: run took $((SECONDS - t0)) s, docker info was not bounded once"
grep -qi 'compose.*not checked' <<<"$out" || fail "wedged: must say compose was not checked, got: $out"

# 3b. The project's own WT_SUFFIX_VAR must reach the compose check.
p="$(mk_compose_project mysuffix 'WT_SUFFIX_VAR="MY_SFX"')"
out="$(PATH="$TMP/bin:$PATH" FAKE_ONLY_MYSFX=1 bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "mysuffix: a container_name that varies with WT_SUFFIX_VAR is not a finding, got: $out"
grep -q 'container_name' <<<"$out" && fail "mysuffix: false container_name blocker, got: $out"

# 3b'. ...and it must be the variable the check VARIES: a container_name that ignores
# WT_SUFFIX_VAR is a finding only when the check was told the variable's name (the
# container_name rule is skipped without one), so this fails if the name is not read.
p="$(mk_compose_project fixedname 'WT_SUFFIX_VAR="MY_SFX"')"
out="$(PATH="$TMP/bin:$PATH" FAKE_FIXED_NAME=1 bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "fixedname: a container_name that does not vary with WT_SUFFIX_VAR must fail, got: $out"
grep -q 'container_name' <<<"$out" || fail "fixedname: must report the container_name finding, got: $out"

# 3c. A failed --no-interpolate render must not silently switch the literal-port
# finding off.
p="$(mk_compose_project nointerp "")"
out="$(PATH="$TMP/bin:$PATH" FAKE_NOINTERP_FAIL=1 bash "$CHECK" "$p" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] || fail "nointerp: a failed --no-interpolate render must not pass, got: $out"
grep -q 'no-interpolate' <<<"$out" || fail "nointerp: must name the failed render, got: $out"


if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — umbrella: a project with nothing to examine is refused, and compose is only claimed when it ran"
