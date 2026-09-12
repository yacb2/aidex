#!/usr/bin/env bash
# render.sh — regenerate a `.context/` board/index as a self-contained HTML
# render. Thin wrapper; all logic lives in dash/render.py. The workspace root is
# discovered internally (walk up to the nearest `.context/`), so every argument
# is a render argument, not a path.
#
# Usage: render.sh <target> [arg]
#   render.sh backlog
#   render.sh plans [slug]
#   render.sh audit <methodology>
#   render.sh coverage

set -euo pipefail

# Shared resolver. This file used to carry its own copy, three fixes behind:
# no $HOME boundary, no project-marker fallback, and no linked-worktree hop --
# so from inside a worktree it wrote into a directory that vanishes on teardown
# while _lib.sh consumers wrote to the main tree. Pinned by
# aidex-conventions/scripts/test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

if [[ $# -lt 1 ]]; then
  echo "ERROR: usage: render.sh <target> [arg]  (targets: backlog | plans [slug] | audit <methodology> | coverage)" >&2
  exit 2
fi

ROOT="$(find_project_root)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

python3 "$SCRIPT_DIR/dash/render.py" "$ROOT" "$@"
