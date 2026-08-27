#!/usr/bin/env bash
# sweep-report.sh — the one artifact a sweep leaves, generated from disk.
#
# Usage:
#   sweep-report.sh <worklist slug|path> [--out <file>] [--print]
#
# Resolves the work-list (active or worklists/_archive/), then renders
# `.context/worklists/_archive/<worklist-basename>-report.md` — the run's COMPANION: it is
# born from the work-list and archived with it (owner's call 2026-08-27, Q12: research/
# is for investigations, not for what a run did). Rendered by sweep-report.py: closed
# items with their commits and
# `## Verification` rows; the OWNER rows aggregated across every item — the one list the
# owner reads; the NEEDS-DECISION list recorded at kickoff, unchanged; deferrals and
# mid-flight skips; emergent growth (flagged past 25 % of the kickoff queue); the gate
# rows from `_tmp/sweep-gate/gate-history.jsonl` verbatim; and the per-sweep metrics —
# items, commits, wall time, share of time in gate suites, legs re-run.
#
# Anchored `origin_ref: worklist/<file>` (ADR 2026-08-27, worklists are referenceable).
# Never hand-narrated: if a section is empty on disk, the report says so.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

ARG="" OUT="" PRINT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)   [[ $# -ge 2 ]] || die "--out needs a file"; OUT="$2"; shift 2 ;;
    --print) PRINT=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*)      die "unknown option: $1" ;;
    *)       ARG="$1"; shift ;;
  esac
done
[[ -n "$ARG" ]] || die "usage: sweep-report.sh <worklist slug|path> [--out <file>] [--print]"

ROOT="$(find_project_root)"
WL_DIR="$ROOT/.context/worklists"
if [[ -f "$ARG" ]]; then WL="$ARG"
else
  WL="$(ls "$WL_DIR/"*"$ARG"*.md "$WL_DIR/_archive/"*"$ARG"*.md 2>/dev/null | head -1 || true)"
fi
[[ -n "${WL:-}" && -f "$WL" ]] || die "worklist not found: $ARG"

if [[ $PRINT -eq 1 ]]; then
  python3 "$SCRIPT_DIR/sweep-report.py" "$ROOT" "$WL" --print
  exit 0
fi
if [[ -z "$OUT" ]]; then
  mkdir -p "$ROOT/.context/worklists/_archive"
  OUT="$ROOT/.context/worklists/_archive/$(basename "$WL" .md)-report.md"
fi
python3 "$SCRIPT_DIR/sweep-report.py" "$ROOT" "$WL" --out "$OUT"
