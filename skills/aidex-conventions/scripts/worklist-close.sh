#!/usr/bin/env bash
# worklist-close.sh — close a run-queue (status done|dropped), stamp updated.
#
# Usage:
#   worklist-close.sh <slug-or-path> [--status done|dropped]
#
# Optionally surfaces resolved upstream refs (backlog/plan/audit) for closure
# propagation — run the shared reconcile.sh yourself after close if desired.
# Prints "CLOSED <file>" to stdout.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WL_DIR="$ROOT/.context/worklists"

arg="${1:-}"; shift || true
[[ -n "$arg" ]] || { echo "usage: worklist-close.sh <slug-or-path> [--status done|dropped]" >&2; exit 2; }

status="done"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) status="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[[ "$status" == "done" || "$status" == "dropped" ]] || { echo "--status must be done|dropped" >&2; exit 2; }

# `|| true`: ls exits 2 on no match, which pipefail+errexit would turn into a
# silent exit 1 before the not-found diagnostic below ever runs.
if [[ -f "$arg" ]]; then file="$arg"; else file="$(ls "$WL_DIR/"*"$arg"*.md 2>/dev/null | head -1 || true)"; fi
[[ -n "${file:-}" && -f "$file" ]] || { echo "worklist not found: $arg" >&2; exit 2; }
today="$(date +%F)"

sed -i.bak -E "s/^status: .*/status: $status/" "$file" && rm -f "$file.bak"
sed -i.bak -E "s/^updated: .*/updated: $today/" "$file" && rm -f "$file.bak"

# surface any still-open upstream refs for manual closure propagation.
# `|| true`: grep exits 1 when a queue has only inline refs — without it,
# pipefail+errexit killed the script here, AFTER the status mutation above.
open_refs="$( (grep -oE '<!-- ref: (backlog|plan|audit) -->' "$file" || true) | wc -l | tr -d ' ')"
[[ "$open_refs" -gt 0 ]] && echo "note: $open_refs tracked upstream ref(s) — run reconcile.sh for closure propagation" >&2

echo "CLOSED $file"
