#!/usr/bin/env bash
# check-compose-isolation.sh — is this compose stack safe to run a SECOND time
# as an isolated Tier-2 worktree, alongside the main tree?
#
# Everything a teardown can reclaim was decided at CREATION. An image named
# after the main project, a container_name with no suffix, a volume that is not
# project-scoped — none of these can be fixed later: the resource is already
# shared with, or indistinguishable from, the main tree's. This check runs
# BEFORE a Tier-2 mechanism is built (bootstrap, Axis 3) rather than after the
# debris appears.
#
# Method — DIFFERENTIAL RENDERING, not pattern-matching. The file is rendered
# twice by compose itself: once as the main project, once under a probe project
# name. Any name that comes out IDENTICAL in both renders is not project-scoped,
# and two stacks will therefore collide on it (or silently share it).
#
# Usage:
#   check-compose-isolation.sh [compose-file] [--suffix-var VAR]
#
#   compose-file default: ./docker-compose.yml
#   --suffix-var: the variable the project uses to namespace container_name
#                 (default: WT_SUFFIX). Set to "" to skip container_name checks.
#
# Exit 0 = safe to run a second isolated stack. Exit 1 = findings (listed).
# Exits 0 with a note when docker is unavailable — this is a gate, not a
# requirement that every machine have Docker.

set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
# _lib.sh turns errexit ON; this script reports its own failures (see the header)
# and needs it off. Without this the failing `A="$(render ...)"` assignment killed
# the script before its own `die "docker compose config failed"` could run --
# exit 1, no message, no cause, on the one path a reader most needs explained.
set +e

FILE="docker-compose.yml"
SUFFIX_VAR="WT_SUFFIX"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suffix-var) SUFFIX_VAR="${2-}"; shift 2 ;;
    -h|--help) sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
    *) FILE="$1"; shift ;;
  esac
done

[[ -f "$FILE" ]] || die "compose file not found: $FILE"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "docker unavailable — skipping compose isolation check (degraded)."
  exit 0
fi

DIR="$(cd "$(dirname "$FILE")" && pwd -P)"
BASE="$(basename "$FILE")"
MAIN="$(basename "$DIR")"
PROBE="${MAIN}-wt-isolationprobe"

render() {  # render <project-name> <suffix-value>
  # `env` rather than an inline assignment: the suffix variable's NAME is data
  # here (--suffix-var), and `$VAR=value` as a command prefix is not an
  # assignment — bash looks for a command by that literal name and exits 127.
  local envs=(COMPOSE_PROJECT_NAME="$1")
  [[ -n "$SUFFIX_VAR" ]] && envs+=("$SUFFIX_VAR=$2")
  ( cd "$DIR" && env "${envs[@]}" \
      docker compose -f "$BASE" --profile '*' config --format json 2>/dev/null )
}

A="$(render "$MAIN" "")"
B="$(render "$PROBE" "-isolationprobe")"
# Third render with interpolation OFF. Without it a port written as
# ${BACKEND_PORT:-8700} is indistinguishable from a literal 8700 — both renders
# resolve to the default when the variable is unset, and a correctly
# parameterized port gets reported as hardcoded.
C="$( cd "$DIR" && docker compose -f "$BASE" --profile '*' config --no-interpolate --format json 2>/dev/null )"
[[ -n "$A" && -n "$B" ]] || die "docker compose config failed on $FILE (is the file valid, and are required vars set?)"

export SUFFIX_VAR MAIN PROBE
findings="$(python3 "$(dirname "${BASH_SOURCE[0]}")/check-compose-isolation.py" "$A" "$B" "$C")"

if [[ -z "$findings" ]]; then
  ok "compose isolation OK: $FILE — a second stack under \$COMPOSE_PROJECT_NAME gets its own images, containers, ports and volumes"
  exit 0
fi

n="$(grep -c . <<<"$findings")"
err "compose isolation: $n finding(s) in $FILE"
while IFS=$'\t' read -r svc kind what why; do
  [[ -z "$svc" ]] && continue
  printf '  [%s] %s: %s\n' "$kind" "$svc" "$what" >&2
  printf '      -> %s\n' "$why" >&2
done <<<"$findings"
exit 1
