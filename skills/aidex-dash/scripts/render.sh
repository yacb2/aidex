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

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

if [[ $# -lt 1 ]]; then
  echo "ERROR: usage: render.sh <target> [arg]  (targets: backlog | plans [slug] | audit <methodology> | coverage)" >&2
  exit 2
fi

ROOT="$(find_project_root)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

python3 "$SCRIPT_DIR/dash/render.py" "$ROOT" "$@"
