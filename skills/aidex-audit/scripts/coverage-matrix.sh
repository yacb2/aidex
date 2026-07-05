#!/usr/bin/env bash
# coverage-matrix.sh — regenerate the breadth matrix (modules x tests) from
# module-map.json. Thin wrapper; all logic lives in coverage/coverage_matrix.py.
#
# Usage: coverage-matrix.sh [workspace-root]  (defaults to the discovered project root)

set -euo pipefail

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

ROOT="${1:-$(find_project_root)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

python3 "$SCRIPT_DIR/coverage/coverage_matrix.py" "$ROOT"
