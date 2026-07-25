#!/usr/bin/env bash
# test-compose-isolation.sh — fixture test for check-compose-isolation.sh.
#
# Two fixtures: one that violates every rule the check knows, one that is
# worktree-safe. The bad fixture is modelled on the real defects found in the
# field (2026-07-25): a service pinning the MAIN project's image name, a fixed
# container_name, a literal host port, and an explicitly-named volume that two
# stacks would share.
#
# Requires a working Docker daemon (the check renders through `docker compose
# config`). Skips with a clear note when Docker is absent, mirroring the
# script's own degradation.
#
# Run with: bash skills/aidex-worktree/scripts/test-compose-isolation.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/check-compose-isolation.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "SKIP — docker unavailable; check-compose-isolation needs it to render compose files"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The main project's name is the compose file's parent directory basename.
BAD="$TMP/myproj"; GOOD="$TMP/goodproj"
mkdir -p "$BAD/app" "$GOOD/app"
touch "$BAD/app/Dockerfile" "$GOOD/app/Dockerfile"

cat > "$BAD/docker-compose.yml" <<'YML'
services:
  api:
    build: ./app
    container_name: myproj-api
    ports:
      - "8000:8000"
    volumes:
      - pgdata:/data
  worker:
    image: myproj-api:latest
volumes:
  pgdata:
    name: myproj_pgdata
YML

cat > "$GOOD/docker-compose.yml" <<'YML'
services:
  api:
    build: ./app
    image: ${COMPOSE_PROJECT_NAME:-goodproj}-api
    container_name: goodproj-api${WT_SUFFIX:-}
    ports:
      - "${API_PORT:-8000}:8000"
    volumes:
      - pgdata:/data
  worker:
    build: ./app
    image: ${COMPOSE_PROJECT_NAME:-goodproj}-api
    container_name: goodproj-worker${WT_SUFFIX:-}
volumes:
  pgdata:
YML

# --- the unsafe stack: every rule fires ---
out="$(bash "$SCRIPT" "$BAD/docker-compose.yml" 2>&1)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "unsafe stack must exit 1, got $rc"

grep -q "worker: pins the main project" <<<"$out" \
  || fail "missed: a service pinning the MAIN project image (in a worktree it starts from the main tree's image while siblings build their own)"
grep -q "container_name.*api: fixed name" <<<"$out" \
  || fail "missed: fixed container_name (a second stack cannot even start)"
grep -q "ports.*api: host port(s) \['8000'\]" <<<"$out" \
  || fail "missed: literal host port"
grep -q "volume.*pgdata: named volume resolves to 'myproj_pgdata' in both" <<<"$out" \
  || fail "missed: explicitly-named volume — the worktree stack would read and write the MAIN tree's data"

# --- the safe stack: silent, exit 0 ---
out_ok="$(bash "$SCRIPT" "$GOOD/docker-compose.yml" 2>&1)"; rc_ok=$?
[[ "$rc_ok" -eq 0 ]] || fail "worktree-safe stack must exit 0, got $rc_ok — output: $out_ok"
grep -q 'compose isolation OK' <<<"$out_ok" || fail "safe stack should report OK, got: $out_ok"

# --- a parameterized port must NOT be reported as literal ---
# This is the false positive the third (--no-interpolate) render exists to
# prevent: ${API_PORT:-8000} renders as 8000 when unset, and a naive check
# calls a correctly-parameterized port hardcoded.
grep -q '\[ports\]' <<<"$out_ok" && fail "parameterized \${API_PORT:-8000} must not be reported as a literal port"

# --- a service that builds without an explicit tag is NOT a finding ---
# Compose derives <project>-<service>, which is already project-scoped. Whether
# two such services were MEANT to share an image is intent, not isolation.
mkdir -p "$TMP/plainproj/app"; touch "$TMP/plainproj/app/Dockerfile"
cat > "$TMP/plainproj/docker-compose.yml" <<'YML'
services:
  api:
    build: ./app
    container_name: plainproj-api${WT_SUFFIX:-}
YML
bash "$SCRIPT" "$TMP/plainproj/docker-compose.yml" >/dev/null 2>&1 \
  || fail "a build with no explicit image tag is project-scoped by compose — must not be a finding"

# --- --suffix-var "" disables the container_name rule ---
bash "$SCRIPT" "$BAD/docker-compose.yml" --suffix-var "" 2>&1 | grep -q 'container_name' \
  && fail "--suffix-var '' must disable the container_name rule"

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — compose isolation: pinned-main-image, fixed container_name, literal port, shared named volume; safe stack silent; no parameterized-port false positive"
