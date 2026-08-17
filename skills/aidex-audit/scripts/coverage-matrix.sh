#!/usr/bin/env bash
# coverage-matrix.sh — regenerate the breadth matrix (modules x tests) from
# module-map.json. Thin wrapper; all logic lives in coverage/coverage_matrix.py.
#
# Usage: coverage-matrix.sh [workspace-root]  (defaults to the discovered project root)

set -euo pipefail

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

ROOT="${1:-$(find_project_root)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

python3 "$SCRIPT_DIR/coverage/coverage_matrix.py" "$ROOT"
