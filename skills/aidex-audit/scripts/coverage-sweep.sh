#!/usr/bin/env bash
# coverage-sweep.sh — drift report: which modules changed without their tests
# moving since the last matrix. Thin wrapper; all logic lives in
# coverage/coverage_sweep.py. Advisory only (always exits 0).
#
# Usage: coverage-sweep.sh [workspace-root] [--since ISO]
#   workspace-root defaults to the discovered project root.

set -euo pipefail

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Split off an optional leading workspace-root positional from the --since flag.
ROOT=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --since)
      ARGS+=("--since" "${2:?--since requires a value}"); shift 2 ;;
    *)
      if [[ -z "$ROOT" ]]; then ROOT="$1"; else ARGS+=("$1"); fi
      shift ;;
  esac
done

[[ -n "$ROOT" ]] || ROOT="$(find_project_root)"

if [[ ${#ARGS[@]} -gt 0 ]]; then
  python3 "$SCRIPT_DIR/coverage/coverage_sweep.py" "$ROOT" "${ARGS[@]}"
else
  python3 "$SCRIPT_DIR/coverage/coverage_sweep.py" "$ROOT"
fi
