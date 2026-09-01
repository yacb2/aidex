#!/usr/bin/env bash
# sweep-kickoff.sh — the one interactive moment of a backlog sweep, made mechanical
# where it can be. Orchestration only: partition → cluster-order → work-list; it decides
# nothing a person or the run must decide, it lays those out.
#
# Usage:
#   sweep-kickoff.sh --title "<run name>" [--size XS,S] [--include BL-NNN ...]
#                    [--exclude BL-NNN ...] [--slug <kebab>] [--dry-run] [--json]
#
#   --size      estimates admitted (default XS,S) — `sweep-eligible.py --size`
#   --include   a REVIEW-tier item the run has READ and judged runnable (§1b: a signal says
#               where to look, not what a sentence means; the read is the kickoff's job)
#   --exclude   an ELIGIBLE item the kickoff pulls (a decision the regex could not see)
#   --dry-run   print the queue and the lists; write no work-list
#   --json      machine form of the same (for the consultation artifact)
#
# The route (sweep-execution-policy.md, stage 1):
#   1. sweep-eligible.py --size → ELIGIBLE / REVIEW / NEEDS-DECISION
#   2. > 20 eligible items: says so — fan out readers to triage (define-item.sh writes
#      the verdicts INTO the items: estimate, surface, verify, touches, depends)
#   3. worklist-new.sh --mode sweep --publish never, queue ordered BY CLUSTER:
#      items sharing a `touches:` token run adjacently; `depends:` edges order within and
#      across clusters; `merge:BL-NNN` marks a MERGE pair (one commit, two trailers)
#   4. the NEEDS-DECISION list is printed for ONE consultation artifact (the skill builds
#      the page — artifacts-local-first); AskUserQuestion is for parameters only
#   5. gate policy fixed once: publish never, destructive deny, merge asked (Q5)
#
# Exit 2 on a queue that cannot be ordered (a `depends:` cycle) or an empty queue.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WL_SCRIPTS="$(cd "$SCRIPT_DIR/../../aidex-conventions/scripts" && pwd -P)"

TITLE="" SIZE="XS,S" SLUG="" DRY=0 JSON=0
INCLUDE=() EXCLUDE=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   TITLE="$2"; shift 2 ;;
    --size)    SIZE="$2"; shift 2 ;;
    --include) INCLUDE+=("$2"); shift 2 ;;
    --exclude) EXCLUDE+=("$2"); shift 2 ;;
    --slug)    SLUG="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)         die "unknown option: $1" ;;
  esac
done
[[ -n "$TITLE" || $DRY -eq 1 || $JSON -eq 1 ]] || die "--title required (or --dry-run / --json)"

ROOT="$(find_project_root)"
[[ -d "$ROOT/.context/backlog" ]] || die "no backlog at $ROOT/.context/backlog"

PART="$(cd "$ROOT" && python3 "$SCRIPT_DIR/sweep-eligible.py" --size "$SIZE" --json)"

# Ordering is pure data work and lives in sweep-order.py (union-find over `touches:`,
# Kahn over `depends:`, MERGE pairs from `merge:BL-NNN`).
INC="$(IFS=,; echo "${INCLUDE[*]:-}")"; EXC="$(IFS=,; echo "${EXCLUDE[*]:-}")"
ORDER="$(printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --include "$INC" --exclude "$EXC")"
[[ $JSON -eq 1 ]] && { printf '%s\n' "$ORDER"; exit 0; }

N="$(printf '%s' "$ORDER" | python3 -c 'import json,sys; print(json.load(sys.stdin)["n_eligible"])')"
if [[ "$N" -eq 0 ]]; then
  echo "empty queue: nothing ELIGIBLE at --size $SIZE — the NEEDS-DECISION list:" >&2
  printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --format summary >&2
  exit 2
fi
printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --include "$INC" --exclude "$EXC" --format summary

[[ $DRY -eq 1 ]] && { echo; echo "dry-run: no work-list written"; exit 0; }
[[ -n "$TITLE" ]] || die "--title required to write the work-list"

# --- the work-list: mode sweep, publish never, destructive deny; merge is asked ------
REFS=()
while IFS=$'\t' read -r id title cluster merge; do
  [[ -n "$id" ]] || continue
  REFS+=(--ref "backlog:$id — $title   <!-- cluster: $cluster${merge:+ · MERGE} -->")
done < <(printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --include "$INC" --exclude "$EXC" --format refs)
# bash 3.2 (macOS) errors on `"${ARR[@]}"` when ARR is empty and `set -u` is on, so an
# omitted --slug killed the run AFTER the queue had printed and BEFORE the work-list was
# written. The `+` form expands to nothing instead of tripping the check.
SLUG_ARGS=(); [[ -n "$SLUG" ]] && SLUG_ARGS=(--slug "$SLUG")
WL="$(cd "$ROOT" && bash "$WL_SCRIPTS/worklist-new.sh" --title "$TITLE" --mode sweep --publish never ${SLUG_ARGS[@]+"${SLUG_ARGS[@]}"} ${REFS[@]+"${REFS[@]}"})"
# the original queue length is what the report measures emergent growth against (25 %),
# and the NEEDS-DECISION list is recorded here so the report can carry it "unchanged and
# unattempted" without a second partition at close-out
# — inserted BEFORE `## Deferred / emergent`, which must stay the LAST section because
# worklist-advance.sh --append writes to the end of the file; the size goes in the
# front-matter (validate-worklist.py ignores keys it does not know).
NEEDS="$(printf '%s' "$PART" | python3 -c '
import json, sys
for i in json.load(sys.stdin)["needs_decision"]:
    print("- %s — %s   <!-- reason: %s -->" % (i["id"], i["title"].replace("\n", " "), i["reason"]))')"
python3 - "$WL" "$N" "$NEEDS" <<'PY2'
import sys
path, n, needs = sys.argv[1], sys.argv[2], sys.argv[3]
t = open(path).read()
t = t.replace("\nupdated: ", "\nqueue-size-at-kickoff: %s\nupdated: " % n, 1)
block = "## Needs decision (kickoff)\n\n" + (needs + "\n" if needs else "_none_\n") + "\n"
t = t.replace("## Deferred / emergent", block + "## Deferred / emergent", 1)
open(path, "w").write(t)
PY2
echo
echo "work-list: $WL"
echo "gate policy: publish never · destructive deny · merge ASKED at close-out (never pre-authorized in a sweep)"
printf '%s\n' "$WL"
