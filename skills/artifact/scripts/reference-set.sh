#!/usr/bin/env bash
# reference-set.sh — one page for a diagram reference set, probed and shot.
#
# Usage: reference-set.sh [--no-probe] <set-dir> <out-dir>
#   Builds <out-dir>/reference-set.html (reference_set.py), then runs render-probe
#   on it and saves the shots: full-page <out-dir>/reference-set-1280.png and -390.png,
#   viewport tiles and <out-dir>/reference-set-shots.json. --no-probe
#   stops after the build (the unit test's route: it needs no Chromium).
#   The last lines are the grader handoff: page, the manifest, the run stamp, the rubric. The
#   script does not call the grader; the session does.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
probe=1
if [[ "${1:-}" == "--no-probe" ]]; then probe=0; shift; fi
[[ $# -eq 2 ]] || { echo "usage: reference-set.sh [--no-probe] <set-dir> <out-dir>" >&2; exit 2; }
python3 "$SCRIPT_DIR/reference_set.py" "$1" "$2"
page="$2/reference-set.html"
if [[ $probe -eq 1 ]]; then
  # Exit 1 = defects found: on a reference set they are the score, not a failure
  # (the hand baselines carry some). Exit 3/4 = the probe could not look: stop.
  rc=0
  probe_out="$(bash "$SCRIPT_DIR/render-probe.sh" --shots "$2" "$page")" || rc=$?
  printf '%s\n' "$probe_out"
  # the caller passes the SHOTS/SHOT lines it recorded so the grader can refuse stale tiles
  [[ $rc -le 1 ]] || exit "$rc"
fi
echo "page:   $page"
if [[ $probe -eq 1 ]]; then
  echo "manifest: $2/reference-set-shots.json"
  grep '^SHOTS run=' <<<"$probe_out" || true
fi
echo "rubric: $SCRIPT_DIR/../references/05-visual-review.md"
