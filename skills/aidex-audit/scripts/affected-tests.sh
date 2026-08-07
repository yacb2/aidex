#!/usr/bin/env bash
# affected-tests.sh — map current diff -> affected modules -> which tests to
# run (module-level, advisory). Thin wrapper; all logic lives in
# coverage/affected_tests.py. Never executes tests.
#
# Usage: affected-tests.sh [workspace-root] [--since <ref>] [--command]
#   workspace-root defaults to the discovered project root.

set -euo pipefail

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Split off an optional leading workspace-root positional from the --since flag.
ROOT=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      ARGS+=("--since" "${2:?--since requires a value}"); shift 2 ;;
    --command)
      ARGS+=("--command"); shift ;;
    *)
      if [[ -z "$ROOT" ]]; then ROOT="$1"; else ARGS+=("$1"); fi
      shift ;;
  esac
done

[[ -n "$ROOT" ]] || ROOT="$(find_project_root)"

if [[ ${#ARGS[@]} -gt 0 ]]; then
  python3 "$SCRIPT_DIR/coverage/affected_tests.py" "$ROOT" "${ARGS[@]}"
else
  python3 "$SCRIPT_DIR/coverage/affected_tests.py" "$ROOT"
fi
