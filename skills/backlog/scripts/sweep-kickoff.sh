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
#   --exclude   an ELIGIBLE item the kickoff pulls (a decision the regex could not see);
#               repeatable or a comma list, `BL-NNN:<reason>` per element. Recorded under
#               Needs decision (BL-482); an id in no partition list exits 2
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
#   5. gate policy fixed once: publish never, destructive deny, and the merge answer
#      the owner gave at Q5 — `--merge preauthorized` records a grant, the default
#      `ask` leaves the branch ready and asks (autonomy.md class 2)
#
# Exit 2 on a queue that cannot be ordered (a `depends:` cycle) or an empty queue.
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions/scripts" && pwd -P)/_lib.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WL_SCRIPTS="$(cd "$SCRIPT_DIR/../../conventions/scripts" && pwd -P)"

TITLE="" SIZE="XS,S" SLUG="" DRY=0 JSON=0 MERGE="ask"
INCLUDE=() EXCLUDE=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   TITLE="$2"; shift 2 ;;
    --size)    SIZE="$2"; shift 2 ;;
    --include) INCLUDE+=("$2"); shift 2 ;;
    --exclude) EXCLUDE+=("$2"); shift 2 ;;
    --slug)    SLUG="$2"; shift 2 ;;
    --merge)   MERGE="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    --json)    JSON=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *)         die "unknown option: $1" ;;
  esac
done
[[ "$MERGE" == "ask" || "$MERGE" == "preauthorized" ]] || die "--merge must be ask|preauthorized"
[[ -n "$TITLE" || $DRY -eq 1 || $JSON -eq 1 ]] || die "--title required (or --dry-run / --json)"

ROOT="$(find_project_root)"
[[ -d "$ROOT/.context/backlog" ]] || die "no backlog at $ROOT/.context/backlog"

PART="$(cd "$ROOT" && python3 "$SCRIPT_DIR/sweep-eligible.py" --size "$SIZE" --json)"
# A sweep left `doing` holds its unticked items out of every new queue as NEEDS-DECISION;
# say so first, or the owner is asked about items whose real fix is resuming or closing it.
[[ $JSON -eq 1 ]] || printf '%s' "$PART" | python3 -c '
import json, sys
wl = json.load(sys.stdin).get("open_worklists", {})
if wl:
    print("OPEN WORK-LISTS (%d) — status doing; resume or close each before trusting NEEDS-DECISION" % len(wl))
    for w, n in sorted(wl.items()):
        print("  %-60s %d unticked" % (w, n))
    print()'

# Ordering is pure data work and lives in sweep-order.py (union-find over `touches:`,
# Kahn over `depends:`, MERGE pairs from `merge:BL-NNN`).
# --exclude is a decision the regex could not see, so each one lands under Needs decision
# — dropping it made the report say "none recorded at kickoff" for a sweep that had
# pulled eight (BL-482). Parsed once here: line 1 is the id list for the ordering, the
# rest are the Needs-decision lines. A comma starts a new element only before `BL-<n>`,
# so a reason keeps its commas. An id no partition list knows is a typo: exit 2.
EXC_PARSED="$(printf '%s' "$PART" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
titles = {i["id"]: i.get("title", "") for k in ("eligible", "review", "needs_decision") for i in d.get(k, [])}
listed = {i["id"] for i in d["needs_decision"]}
ids, lines = [], []
for arg in sys.argv[1:]:
    for e in re.split(r",\s*(?=BL-\d+\b)", arg):
        bl, _, why = e.strip().rstrip(",").partition(":")
        bl = bl.strip()
        if not bl or bl in ids:
            continue
        if bl not in titles:
            sys.exit("sweep-kickoff: --exclude %s is in no partition list (not open, or outside --size)" % bl)
        ids.append(bl)
        if bl in listed:
            continue  # already listed with the reason the partition gave
        why = why.strip().replace("-->", "--&gt;")
        lines.append("- %s — %s   <!-- reason: pulled at kickoff (--exclude)%s -->"
                     % (bl, titles[bl].replace("\n", " "), ": " + why if why else ""))
print(",".join(ids))
print("\n".join(lines))
' ${EXCLUDE[@]+"${EXCLUDE[@]}"})" || exit 2
EXC="$(head -1 <<<"$EXC_PARSED")"; EXC_NEEDS="$(tail -n +2 <<<"$EXC_PARSED")"
INC="$(IFS=,; echo "${INCLUDE[*]:-}")"
ORDER="$(printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --include "$INC" --exclude "$EXC")"
[[ $JSON -eq 1 ]] && { printf '%s\n' "$ORDER"; exit 0; }

read -r N NB < <(printf '%s' "$ORDER" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["n_eligible"], d["n_blocked"])')
if [[ "$N" -eq 0 ]]; then
  if [[ "$NB" -gt 0 ]]; then
    echo "empty queue: nothing queueable at --size $SIZE — $NB eligible, all blocked by open or unknown depends — the NEEDS-DECISION list:" >&2
  else
    echo "empty queue: nothing ELIGIBLE at --size $SIZE — the NEEDS-DECISION list:" >&2
  fi
  printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --format summary >&2
  exit 2
fi
printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --include "$INC" --exclude "$EXC" --format summary

[[ $DRY -eq 1 ]] && { echo; echo "dry-run: no work-list written"; exit 0; }
[[ -n "$TITLE" ]] || die "--title required to write the work-list"

# --- the work-list: mode sweep, publish never, destructive deny; merge per Q5 -------
REFS=()
while IFS=$'\t' read -r id title cluster merge; do
  [[ -n "$id" ]] || continue
  REFS+=(--ref "backlog:$id — $title   <!-- cluster: $cluster${merge:+ · MERGE} -->")
done < <(printf '%s' "$PART" | python3 "$SCRIPT_DIR/sweep-order.py" "$ROOT/.context/backlog" --include "$INC" --exclude "$EXC" --format refs)
# bash 3.2 (macOS) errors on `"${ARR[@]}"` when ARR is empty and `set -u` is on, so an
# omitted --slug killed the run AFTER the queue had printed and BEFORE the work-list was
# written. The `+` form expands to nothing instead of tripping the check.
SLUG_ARGS=(); [[ -n "$SLUG" ]] && SLUG_ARGS=(--slug "$SLUG")
WL="$(cd "$ROOT" && bash "$WL_SCRIPTS/worklist-new.sh" --title "$TITLE" --mode sweep --publish never --merge "$MERGE" ${SLUG_ARGS[@]+"${SLUG_ARGS[@]}"} ${REFS[@]+"${REFS[@]}"})"
# the original queue length is what the report measures emergent growth against (25 %),
# and the NEEDS-DECISION list is recorded here so the report can carry it "unchanged and
# unattempted" without a second partition at close-out
# — inserted BEFORE `## Deferred / emergent`, which must stay the LAST section because
# worklist-advance.sh --append writes to the end of the file; the size goes in the
# front-matter (validate-worklist.py ignores keys it does not know).
NEEDS="$(printf '%s' "$ORDER" | python3 -c '
import json, sys
for i in json.load(sys.stdin)["needs_decision"]:
    print("- %s — %s   <!-- reason: %s -->" % (i["id"], i["title"].replace("\n", " "), i["reason"]))')"
[[ -n "$EXC_NEEDS" ]] && NEEDS="${NEEDS:+$NEEDS
}$EXC_NEEDS"
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
# BL-361: this line used to be a fixed refusal. autonomy.md makes integrating the
# branch class 2 — pre-authorizable at the initial phase — and the sweep's own reason
# for being stricter ("blast radius nobody reviewed as a unit") is answered by the
# whole-branch review the boundary gate already runs. The line now reports the answer
# Q5 actually got instead of contradicting it.
if [[ "$MERGE" == "preauthorized" ]]; then
  echo "gate policy: publish never · destructive deny · merge PRE-AUTHORIZED at kickoff (conditional on the boundary gate passing and the whole-branch review)"
else
  echo "gate policy: publish never · destructive deny · merge ASKED at close-out (no grant taken at kickoff)"
fi
printf '%s\n' "$WL"
