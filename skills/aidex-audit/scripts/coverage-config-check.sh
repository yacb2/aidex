#!/usr/bin/env bash
# coverage-config-check.sh — read-only drift check for the five suite-speed-
# and-coverage configuration keys (hasher_pytest, hasher_e2e, vitest_include,
# coverage_provider, no_n_auto) across every project. Thin wrapper; all logic
# lives in coverage/config_check.py. Mirrors compliance-sweep.sh's contract
# in full: read-only, on-demand, silent when clean, exit 1 when any project
# drifts.
#
# Usage:
#   coverage-config-check.sh                       # every project under the workspace root
#   coverage-config-check.sh --root <dir>           # ...under <dir> instead
#   coverage-config-check.sh --include-worktrees    # include *-wt-* copies (excluded by default)
#   coverage-config-check.sh --verbose              # also print the table when nothing drifted
#   coverage-config-check.sh --json                 # machine-readable roll-up (always full, never silent)
#   coverage-config-check.sh <project> [<proj>..]   # only these, a named list

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

ARGS=()
ROOT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

# Default root is the WORKSPACE root, not a single project's root: the
# parent directory of the project find_project_root() resolves from cwd
# (this script itself lives inside one such project). --root overrides it.
if [[ -z "$ROOT" ]]; then
  ROOT="$(dirname "$(find_project_root)")"
fi

if [[ ${#ARGS[@]} -gt 0 ]]; then
  python3 "$SCRIPT_DIR/coverage/config_check.py" --root "$ROOT" "${ARGS[@]}"
else
  python3 "$SCRIPT_DIR/coverage/config_check.py" --root "$ROOT"
fi
