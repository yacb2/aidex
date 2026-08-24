#!/usr/bin/env bash
# test-archive-sweep.sh — BL-215: one archive pass across plans, audits, requests, backlog.
#
# A fixture per tier, because the archivable UNIT is a different shape in each one: a flat
# .md in backlog/ and requests/, either a file or a whole modular folder in plans/, and a
# dated RUN folder under audits/<methodology>/ that archives to audits/_archive/ rather
# than into its methodology folder. A pass tested on one tier proves nothing about the
# other three, which is precisely how D-10 came to be applied to the backlog and skipped
# everywhere else.
#
# Lives in aidex-conventions/scripts/ with a hyphen: run-all.sh globs
# `skills/aidex-conventions/scripts/test-*.sh` explicitly, which is the one hyphenated
# exception it makes. Verified discovered, not assumed.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/archive-sweep.py"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

fm() { printf -- '---\ntitle: "x"\nstatus: %s\ncreated: 2026-01-01\nupdated: 2026-01-01\n%s---\n\nbody\n' "$1" "${2:-}"; }

build() {
  local root="$1" ctx="$1/.context"
  mkdir -p "$ctx"/{plans/_archive,audits/_archive,requests/_archive,backlog/_archive}
  # backlog: one terminal, one active
  fm done    > "$ctx/backlog/2026-01-01-bl-001-finished.md"
  fm open    > "$ctx/backlog/2026-01-02-bl-002-live.md"
  # requests: one dropped
  fm dropped > "$ctx/requests/2026-01-03-abandoned.md"
  # plans: a single-file terminal one AND a modular folder whose status is in 00-index.md
  fm superseded > "$ctx/plans/2026-01-04-old-plan.md"
  mkdir -p "$ctx/plans/2026-01-05-modular-plan"
  fm done  > "$ctx/plans/2026-01-05-modular-plan/00-index.md"
  fm open  > "$ctx/plans/2026-01-05-modular-plan/01-phase.md"
  mkdir -p "$ctx/plans/2026-01-06-live-plan"
  fm doing > "$ctx/plans/2026-01-06-live-plan/00-index.md"
  # audits: a done run and a live run under a methodology
  mkdir -p "$ctx/audits/ux/2026-01-07-closed-run" "$ctx/audits/ux/2026-01-08-open-run"
  fm done > "$ctx/audits/ux/2026-01-07-closed-run/index.md"
  fm open > "$ctx/audits/ux/2026-01-08-open-run/index.md"
  fm done > "$ctx/audits/ux/00-inventory.md"   # a BOARD, not a run — must never move
}

# --- dry run: every tier reported, nothing touched --------------------------------
WS="$(mktemp -d)"; trap 'rm -rf "$WS"' EXIT
build "$WS"
OUT="$(python3 "$SCRIPT" "$WS/.context" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] || fail "plain dry run must exit 0 whatever it finds, got $RC"

for expect in "backlog/2026-01-01-bl-001-finished.md" "requests/2026-01-03-abandoned.md" \
              "plans/2026-01-04-old-plan.md" "plans/2026-01-05-modular-plan" \
              "audits/ux/2026-01-07-closed-run"; do
  grep -q "$expect" <<<"$OUT" || fail "terminal artifact not reported: $expect"
done
pass "one instance from each of the four tiers is reported, including a modular plan folder"

for never in "bl-002-live" "2026-01-06-live-plan" "2026-01-08-open-run" "00-inventory"; do
  grep -q "$never" <<<"$OUT" && fail "an active artifact or a board was reported: $never"
done
pass "active artifacts and the audit BOARD files are left alone"

grep -q 'audits/_archive/2026-01-07-closed-run' <<<"$OUT" \
  || fail "an audit run must archive to audits/_archive/, not into its methodology folder: $OUT"
pass "each tier's own D-10 destination is respected"

[[ -f "$WS/.context/backlog/2026-01-01-bl-001-finished.md" ]] \
  || fail "the dry run MOVED something — default must never mutate"
pass "the default run is a dry run: nothing moved"

# --- --check exits 1 so a caller can gate ------------------------------------------
python3 "$SCRIPT" "$WS/.context" --check >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "--check must exit 1 when something would move"
[[ -f "$WS/.context/backlog/2026-01-01-bl-001-finished.md" ]] \
  || fail "--check moved something; it is a dry run"
python3 "$SCRIPT" "$WS/.context" --check --apply >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "--check with --apply must be refused as contradictory"
pass "--check gates at exit 1 without moving; --check --apply is refused"

# --- --apply moves exactly the terminal set ----------------------------------------
OUT_A="$(python3 "$SCRIPT" "$WS/.context" --apply 2>&1)"; RC_A=$?
[[ $RC_A -eq 0 ]] || fail "--apply expected exit 0, got $RC_A"
for moved in "backlog/_archive/2026-01-01-bl-001-finished.md" \
             "requests/_archive/2026-01-03-abandoned.md" \
             "plans/_archive/2026-01-04-old-plan.md" \
             "plans/_archive/2026-01-05-modular-plan/00-index.md" \
             "audits/_archive/2026-01-07-closed-run/index.md"; do
  [[ -e "$WS/.context/$moved" ]] || fail "--apply did not archive: $moved"
done
[[ -e "$WS/.context/backlog/2026-01-02-bl-002-live.md" ]] || fail "--apply moved a live item"
[[ -e "$WS/.context/audits/ux/2026-01-08-open-run/index.md" ]] || fail "--apply moved a live audit run"
[[ -e "$WS/.context/audits/ux/00-inventory.md" ]] || fail "--apply moved an audit board"
grep -q 'indexes are NOT regenerated' <<<"$OUT_A" \
  || fail "--apply does not say the indexes still need their own reindexers"
pass "--apply archives exactly the terminal set and says indexes are not regenerated"

# A second run is a no-op: the pass has to be idempotent to be schedulable.
OUT_2="$(python3 "$SCRIPT" "$WS/.context" 2>&1)"
grep -q 'every tier is clean' <<<"$OUT_2" || fail "a second run is not a no-op: $OUT_2"
pass "idempotent: the second run reports clean"

# --- status drift: open, but every cited commit has landed -------------------------
GW="$(mktemp -d)"
build "$GW"
( cd "$GW" && /usr/bin/git init -q . && /usr/bin/git -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m "landed" ) >/dev/null 2>&1
SHA="$(/usr/bin/git -C "$GW" rev-parse --short HEAD)"
fm open "commits: \"$SHA\"
"        > "$GW/.context/backlog/2026-01-09-bl-003-drifted.md"
fm open "commits: \"deadbee\"
"        > "$GW/.context/backlog/2026-01-10-bl-004-unlanded.md"
OUT_D="$(python3 "$SCRIPT" "$GW/.context" 2>&1)"
grep -q 'status-drift' <<<"$OUT_D" || fail "status drift was not reported at all: $OUT_D"
grep -q 'bl-003-drifted' <<<"$OUT_D" || fail "an open item whose commit landed was not reported"
grep -q 'bl-004-unlanded' <<<"$OUT_D" && fail "an item citing a commit that does NOT exist was reported as drift"
# Drift must never be auto-resolved: deciding an item is finished is a judgement about the
# work, not about git.
python3 "$SCRIPT" "$GW/.context" --apply >/dev/null 2>&1
[[ -f "$GW/.context/backlog/2026-01-09-bl-003-drifted.md" ]] \
  || fail "--apply archived a status-drift item; only the terminal set may move"
pass "status drift is reported on landed commits only, and --apply never resolves it"
rm -rf "$GW"

# --- no git above .context/: report the other half, say so, never crash ------------
NG="$(mktemp -d)"; build "$NG"
OUT_NG="$(python3 "$SCRIPT" "$NG/.context" 2>&1)"; RC_NG=$?
[[ $RC_NG -eq 0 ]] || fail "a context with no git repo must still work, got $RC_NG"
grep -q 'status drift was not checked' <<<"$OUT_NG" \
  || fail "with no git repo it must SAY drift was not checked, not imply there is none"
grep -q 'bl-001-finished' <<<"$OUT_NG" || fail "the unarchived half must still be reported"
pass "with no git repo it reports the unarchived half and says drift was not checked"
rm -rf "$NG"

# --- a missing .context/ is an error, not a clean report --------------------------
python3 "$SCRIPT" "$WS/nope" >/dev/null 2>&1
[[ $? -eq 2 ]] || fail "a missing .context/ must exit 2, not read as clean"
pass "a missing .context/ exits 2"

if [[ $FAILURES -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$FAILURES"
  exit 1
fi
printf '\nOK — archive-sweep: 4 tiers, boards spared, --check, --apply, idempotence, drift, no-git\n'
