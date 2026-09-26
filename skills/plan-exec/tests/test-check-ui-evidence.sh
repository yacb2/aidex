#!/usr/bin/env bash
# The UI evidence gate holds a UI phase to a STRICT line grammar for the three parts of
# "verified", names the part and quotes the expected line when anything else is written,
# and leaves every non-UI plan alone whatever its log looks like.
#
# Layer: the script's own CLI over fixture plan files — the decision is the exit code and
# the line naming the part, and nothing below the CLI can observe it.
#
# The tables are mostly NEAR-MISSES: every spelling two review rounds used to get a
# failing, pending or self-reviewed record past a free-text parser is a row here that
# must fail. A grammar is only strict if what it does not match is shown to fail.
# The last block runs the script over the workspace's real plans: a non-UI plan must
# never be refused (round 2 found 25 of 44 real plans exiting 2).
#
# Run with: bash skills/plan-exec/tests/test-check-ui-evidence.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
CHECK="$ROOT/skills/plan-exec/scripts/check-ui-evidence.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SURFACE='- ui-surface: phase 3 · .context/artifacts/gallery-review.html · owner: approved'
GATE='- ui-gate: phase 3 · no-snapshot-update · passed=44 failed=0'
PREDS='- ui-predicates: phase 3 · reviewer: review-diff-opus · PASS'
S='- ui-surface: phase 3 · r/g.html · owner:'    # + a verdict
G='- ui-gate: phase 3 · no-snapshot-update ·'    # + the counts
P='- ui-predicates: phase 3 · reviewer:'         # + who · verdict
K='- ui-evidence: phase 3 · skipped'             # + the reason

# plan <file> <UI marker line|''> <log lines...>
LOGH='## Execution log'
plan() {
  local f="$TMP/$1" ui="$2"; shift 2
  { printf -- '---\ntitle: fixture\n---\n\n# Fixture plan\n\n'
    [ -n "$ui" ] && printf '%s\n\n1. Level 2 — new screen on the list pattern.\n\n' "$ui"
    printf '%s\n\n' "$LOGH"
    local l; for l in "$@"; do printf '%s\n' "$l"; done
  } > "$f"
  printf '%s' "$f"
}
UI='## UI contract'
n=0; slot() { n=$((n+1)); printf 'f%03d.md' "$n"; }

fail=0
# row <name> <exit> <must name, or ''> <must NOT name: 'a|b' or ''> -- <args...>
row() {
  local name="$1" want="$2" needle="$3" nots="$4"; shift 5
  local out rc x
  out="$(bash "$CHECK" "$@" 2>&1)"; rc=$?
  if [ "$rc" -ne "$want" ]; then
    printf 'FAIL: %s — exit %s, expected %s: %s\n' "$name" "$rc" "$want" "$out"; fail=1; return
  fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; then
    printf 'FAIL: %s — output does not name "%s": %s\n' "$name" "$needle" "$out"; fail=1; return
  fi
  if [ -n "$nots" ]; then
    local IFS='|'
    for x in $nots; do
      if grep -qF -- "$x" <<<"$out"; then
        printf 'FAIL: %s — output names "%s", which is not missing: %s\n' "$name" "$x" "$out"; fail=1; return
      fi
    done
  fi
  printf 'ok: %s\n' "$name"
}
NOT1='part 2|part 3'; NOT2='part 1|part 3'; NOT3='part 1|part 2'
# bad<part> <name> <line> — the other two parts valid, this line in place of the part
bad1() { row "part 1 fails: $1" 1 "part 1" "$NOT1" -- "$(plan "$(slot)" "$UI" "$2" "$GATE" "$PREDS")" 3; }
bad2() { row "part 2 fails: $1" 1 "part 2" "$NOT2" -- "$(plan "$(slot)" "$UI" "$SURFACE" "$2" "$PREDS")" 3; }
bad3() { row "part 3 fails: $1" 1 "part 3" "$NOT3" -- "$(plan "$(slot)" "$UI" "$SURFACE" "$GATE" "$2")" 3; }
good() { local name="$1"; shift; row "passes: $name" 0 "" "" -- "$(plan "$(slot)" "$UI" "$@")" 3; }

# ================= the grammar: what passes =================
good "all three parts" "$SURFACE" "$GATE" "$PREDS"
good "no bullet" "${SURFACE#- }" "${GATE#- }" "${PREDS#- }"
good "owner: approved 12/12" "$S approved 12/12" "$GATE" "$PREDS"
good "owner: 9/10" "$S 9/10" "$GATE" "$PREDS"
good "owner: 10/10" "$S 10/10" "$GATE" "$PREDS"
good "meta=6/6" "$SURFACE" "$G passed=44 failed=0 meta=6/6" "$PREDS"
good "a later valid line supersedes an earlier bad one (part 1)" "$S rejected" "$GATE" "$PREDS" "$SURFACE"
good "a later valid line supersedes an earlier bad one (part 2)" "$SURFACE" "$G passed=41 failed=3" "$GATE" "$PREDS"
good "a later valid line supersedes an earlier bad one (part 3)" "$SURFACE" "$GATE" "$P opus · FAIL" "$PREDS"
good "a line for phase 3b does not shadow phase 3" "- ui-surface: phase 3b · r.html · owner: rejected" "$SURFACE" "$GATE" "$PREDS"
good "a failing line for phase 3.1 does not touch phase 3" "$SURFACE" "$GATE" "$PREDS" '- ui-gate: phase 3.1 · no-snapshot-update · passed=1 failed=3'
good "a label quoted mid-line is not a record" "$SURFACE" "$GATE" "$PREDS" \
  "- note: the ui-gate: phase 3 · no-snapshot-update · passed=44 failed=3 line was a rerun"
good "a heading inside a code fence does not end the log" '```' '## not a heading' '```' "$SURFACE" "$GATE" "$PREDS"

# ================= part 1: near-misses =================
bad1 "no ui-surface line" "- phase 3 green"
bad1 "no page path" '- ui-surface: phase 3 · owner: approved'
bad1 "an .html inside the owner field" '- ui-surface: phase 3 · owner: see notes.html'
bad1 "the template placeholder path" '- ui-surface: phase 3 · <page>.html · owner: approved'
bad1 "no owner field" '- ui-surface: phase 3 · review/gallery.html'
bad1 "path after the owner" '- ui-surface: phase 3 · owner: approved · r/g.html'
bad1 "capitalised label" '- UI-surface: phase 3 · r/g.html · owner: approved'
bad1 "capitalised phase" '- ui-surface: Phase 3 · r/g.html · owner: approved'
bad1 "comma for the separator" '- ui-surface: phase 3,  r/g.html · owner: approved'
bad1 "a later bad line supersedes an earlier valid one" "$SURFACE"$'\n'"$S rejected 4/12 rows"
for v in '' 'pending' 'pending review' 'TBD.' 'tbd' 'awaiting' 'rejected' 'rejected 4/12 rows' 'approved 4/12 rows' \
         'score 6/10' 'score 10/10' 'accepted' 'OK, ship it' 'ok' 'Approved' 'approved.' 'approved 12/12 rows' \
         '19/10' '8/10' '0/10' '9.5/10' 'approved 0/0' 'approved 12/4' 'approved 9/10' 'approved? no' \
         'approved except rows 3, 5 and 7' 'accepted risk: layout broken' 'no. 9/10 of the page is fine' \
         'not yet — 9/10 is the bar' 'ok? no' 'ok-ish, rows 3-5 broken' 'okay-ish' 'oko' \
         'pending (was 9/10 before the change)' 'rejected: 9/10 rows fine, row 7 broken' 'tbd, target 9/10'; do
  bad1 "owner: '$v'" "$S $v"
done

# ================= part 2: near-misses =================
bad2 "no ui-gate line" "- phase 3 green"
bad2 "no no-snapshot-update claim" '- ui-gate: phase 3 · passed=44 failed=0'
bad2 "the claim negated in prose" '- ui-gate: phase 3 · did not confirm no-snapshot-update · passed=44 failed=0'
bad2 "snapshots updated, then the claim" '- ui-gate: phase 3 · snapshots updated, then no-snapshot-update · passed=44 failed=0'
bad2 "no counts" '- ui-gate: phase 3 · no-snapshot-update'
bad2 "a later bad line supersedes an earlier valid one" "$GATE"$'\n'"$G passed=41 failed=3"
for c in 'passed=0 failed=0' 'passed=44 failed=1' 'passed=44 failed=03' 'passed=044 failed=0' 'failed=0 passed=44' \
         'passed=44  failed=0' 'passed=44,failed=0' 'passed=44 failed=0 flaky=1' 'passed=44 failed=0 skipped=2' \
         'passed=44 failed=0 meta=5/6' 'passed=44 failed=0 meta=5 / 6' 'passed=44 failed=0 meta=0/0' \
         'passed=44 failed=0 meta=6/6 meta=5/6' 'passed=44 failed=0 meta=6' 'passed=44 failed=0 -u' \
         'passed=44 failed=0 --update-snapshots' 'passed=44 failed=0 --updateSnapshot' 'passed=44 failed=0 --snapshot-update' \
         'passed=44 failed=0 (snapshots updated)' 'passed=44 failed=0 (--ui mode)' 'passed=44 failed=0.' \
         '44 passed' '44 passed (light-desktop, dark-desktop)' '44 passed after --update-snapshots' \
         'npx playwright test -u · 44 passed' '44 passed --update-snapshots=all' '3 failed, 41 passed' '43 passed, 1 flaky' \
         '44 passed, 1 error' 'TODO' 'green' '44 passed, 0 failed, 2 skipped (1.2m)' '44 passed · meta: 6/6' \
         '44 passed · meta: 5/6' '0 passed' '10 passed · 1 failed' '10 passed ... 1 failed' '1 passed (of 44; 43 skipped)' \
         '41 passed | 3 failed' '44 passed, 1 broken' '44 passed, 1 failed test' '44 passed, 1 timed out' '44 passed, 2 errored' \
         '44 passed, 2 failures' '44 passed, 3 did not run' '44 passed, 3 tests failed' '44 passed · 3 failed in a previous run' \
         '44 passed · failed: 3' '44 passed · meta 5/6' '44 passed · meta: 5/6 · meta: 6/6' '44 passed · meta: 5 / 6' \
         '44 passed, meta-suite 3 of 6 red' '44 passed (npx playwright test --updateSnapshot)' '44 passed (pytest --snapshot-update)' \
         '44 passed (ran (-u) first)' '44 passed tests/-u/x' 'passed 44, failed 3' 'passed: 0'; do
  bad2 "closing '$c'" "$G $c"
done

# ================= part 3: near-misses =================
bad3 "no ui-predicates line" "- phase 3 green"
bad3 "a later bad line supersedes an earlier valid one" "$PREDS"$'\n'"$P opus · FAIL"
for v in 'someone' 'opus' 'opus · FAIL, 2 vacuous predicates' 'tbd · tbd' 'opus · tbd' 'tbd · PASS' 'TBD · PASS' \
         'FAIL · PASS' 'me · PASS' 'nobody · PASS' 'none · PASS' 'self · PASS' 'Self · PASS' '- · PASS' ' · PASS' \
         'opus · PASS · FAIL' 'opus · PASS (round 1); DO NOT SHIP (round 2)' 'opus · PASS-through, not reviewed' \
         'opus · SHIP WITH FIXES' 'opus · clean-up needed, 2 vacuous' 'opus · pass? no' 'opus · ship-blocker found' \
         'opus · SHIP' 'opus · clean, 0 findings' 'opus · pass' 'opus · PASS.' 'opus · PASS, 0 vacuous predicates' \
         'review diff opus · PASS'; do
  bad3 "reviewer: '$v'" "$P $v"
done

# ================= skips =================
row "skip: a reason passes" 0 "skipped" "" -- \
  "$(plan "$(slot)" "$UI" "$K — backend-only phase, no screen rendered")" 3
row "skip: the Step 3b skeleton line passes" 0 "skipped" "" -- \
  "$(plan "$(slot)" "$UI" "$K — skeleton only, owner review pending in phase 4")" 3
row "skip: evidence for phase 3.1 does not block a phase-3 skip" 0 "skipped" "" -- \
  "$(plan "$(slot)" "$UI" "$K — backend only, no screen" '- ui-gate: phase 3.1 · no-snapshot-update · passed=1 failed=3')" 3
for r in '' ' — tbd' ' - .' ':' ' — backend only' ' — TODO later please' ' — n/a for this phase' ' — no no no' \
         ' — see above please' ': pending owner review later' '—no screen rendered here' ' —  ' ' — pending owner review later'; do
  row "skip fails: reason '${r}'" 1 "skip" "" -- "$(plan "$(slot)" "$UI" "$K$r")" 3
done
row "skip fails: 'Skipped' capitalised" 1 "" "" -- \
  "$(plan "$(slot)" "$UI" '- ui-evidence: phase 3 · Skipped — no screen rendered here')" 3
row "skip fails: next to evidence for the same phase" 1 "skip" "" -- \
  "$(plan "$(slot)" "$UI" "$K — backend-only phase, no screen" "$G passed=41 failed=3")" 3

# ================= which plan is UI: the SECTION, never a mention =================
# A marker is (a) a heading whose text has "ui contract" within its first four words, or
# (b) a line that starts, after an optional list marker, with a bold span beginning
# "UI contract". Everything else that merely names it is not a marker.
for h in '## UI contract' '**UI contract:**' '## UI Contract (level 2)' '## UI contract — level 2' '### UI contract' \
         '## 3. UI contract' '##UI contract' '## UI-contract' '## 3.1 UI contract' '## 3.1. UI contract' '## 3) UI contract' \
         '## A. UI contract' '## The UI contract' '## Section 4: UI contract' '## UI–contract' '#### UI  contract' \
         '## UIcontract' '- **UI contract:** level 2' '1. **UI contract**' '> ## UI contract' '**UI contract** is not needed here' \
         '# UI Contract 9/10 Implementation Plan' '__UI contract__' '- __UI contract:__ level 1'; do
  row "UI: '$h'" 1 "part 1" "" -- "$(plan "$(slot)" "$h" '- phase 3 green')" 3
done
for m in '- Screen mockups / wireframes (routed to `feat/ui-contract-skill`, which works from the' \
         '- Follow-up plan input: `research/2026-09-25-ui-contract-feature-state.md` (owner confirmed 2026-09-25: the follow-up targets ui-contract).' \
         '## Routing to `feat/ui-contract-skill`' '`feat/ui-contract-skill`' \
         '**Goal:** The ui-contract chain (`/ui-contract` -> gallery-builder -> gate -> verify-ui ->' \
         '**Next:** then the ui-contract follow-up plan' '* UI contract: level 1' 'Level: see the __UI contract__ below' \
         '- **[UI contract to 9/10 — merge the harness](2026-09-26-ui-contract-9-of-10/00-index.md)** — open' \
         '## See [UI contract](ui.md)' '## Notes on the follow-up for the UI contract' 'The UI contract is level 2.'; do
  row "non-UI: a mention, not the section: '$m'" 0 "not a UI plan" "" -- "$(plan "$(slot)" "$m" '- phase 3 green')" 3
done
row "non-UI: nothing recorded" 0 "not a UI plan" "" -- "$(plan "$(slot)" '' '- phase 3 green')" 3
row "non-UI: prose naming the ui-contract skill" 0 "not a UI plan" "" -- \
  "$(plan "$(slot)" 'No screen changes, so /ui-contract owes nothing here.' '- phase 3 green')" 3
row "non-UI: the words between two bold spans are in neither" 0 "not a UI plan" "" -- \
  "$(plan "$(slot)" '**Goal:** the ui-contract chain runs once, **then** it is measured.' '- phase 3 green')" 3
printf '# Plan\n\nSome text.\n' > "$TMP/nolog-nonui.md"
row "non-UI: no Execution log at all" 0 "not a UI plan" "" -- "$TMP/nolog-nonui.md" 3
LOGH='## Execution log — 2026-08-21'
row "non-UI: a dated log heading" 0 "not a UI plan" "" -- "$(plan "$(slot)" '' '- phase 3 green')" 3
row "UI: a dated log heading is still the log" 0 "" "" -- "$(plan "$(slot)" "$UI" "$SURFACE" "$GATE" "$PREDS")" 3
LOGH='## Execution log'

# ================= malformed input is refused, never passed =================
: > "$TMP/empty.md"
row "refused: empty file" 2 "refused" "" -- "$TMP/empty.md" 3
row "refused: missing file" 2 "refused" "" -- "$TMP/nope.md" 3
row "refused: missing phase argument" 2 "usage" "" -- "$(plan "$(slot)" "$UI" "$SURFACE" "$GATE" "$PREDS")"
printf '# Plan\n\n## UI contract\n\n1. Level 1\n' > "$TMP/nolog.md"
row "refused: UI plan with no Execution log" 2 "no '## Execution log'" "" -- "$TMP/nolog.md" 3
row "refused: UI plan with an empty Execution log" 2 "empty" "" -- "$(plan "$(slot)" "$UI")" 3
row "refused: UI evidence only inside a code fence" 2 "empty" "" -- "$(plan "$(slot)" "$UI" '```' "$SURFACE" "$GATE" "$PREDS" '```')" 3
printf '# Phase 3\n\n[← Back to Index](00-index.md)\n\n## Execution log\n\n- phase 3 green\n' > "$TMP/phase.md"
row "refused: a phase file (it links back to its 00-index.md)" 2 "00-index.md" "" -- "$TMP/phase.md" 3

# ================= visual bugfix: the caller classified the bug as visual =================
vis() { local f="$TMP/$(slot)"; printf '%s\n' '# Human verification' '' "$@" > "$f"; printf '%s' "$f"; }
VS="${SURFACE/phase 3 · /}"; VG="${GATE/phase 3 · /}"; VP="${PREDS/phase 3 · /}"
row "visual: all three parts" 0 "" "" -- --visual "$(vis "$VS" "$VG" "$VP")"
row "visual: the last surface line wins" 0 "" "" -- --visual "$(vis '- ui-surface: r.html · owner: rejected' "$VS" "$VG" "$VP")"
row "visual: a label quoted in prose is not a record" 1 "part 1" "$NOT1" -- \
  --visual "$(vis 'The old log said ui-surface: r.html · owner: approved but that was wrong' "$VG" "$VP")"
row "visual: failing gate" 1 "part 2" "$NOT2" -- --visual "$(vis "$VS" '- ui-gate: no-snapshot-update · passed=42 failed=2' "$VP")"
row "visual: skip for a missing harness" 0 "skipped" "" -- --visual "$(vis '- ui-evidence: skipped — no gallery harness in this project')"
for r in 'it was a tiny spacing fix' 'nothing changed in the harness' 'no gallery harnesses were touched' 'no-gallery harness here'; do
  row "visual: skip fails: '$r'" 1 "skip" "" -- --visual "$(vis "- ui-evidence: skipped — $r")"
done
: > "$TMP/vis-empty.md"
row "visual: refused on an empty proof file" 2 "refused" "" -- --visual "$TMP/vis-empty.md"

# ================= the real plans: exactly the UI ones are UI =================
# Every real plan is run. The UI set is written here by hand, from reading each plan's
# headings and bold lead-ins — not from the script — and every other plan must exit 0
# whatever its log looks like (round 2 found 25 of 44 refused). A new UI plan in the
# workspace fails this until it is added below: the list is the claim, kept honest.
# Skipped where the workspace is absent (the public repo ships without it).
EXPECTED_UI='2026-09-26-ui-contract-9-of-10/00-index.md
_archive/2026-09-21-ui-contract-skill-and-agents.md'
PLANS="${UI_EVIDENCE_PLANS_DIR:-$ROOT/../.context/plans}"
if [ -d "$PLANS" ]; then
  swept=0; ui_found=""
  for f in "$PLANS"/*.md "$PLANS"/*/00-index.md "$PLANS"/_archive/*.md "$PLANS"/_archive/*/00-index.md; do
    [ -f "$f" ] || continue
    swept=$((swept+1)); rel="${f#"$PLANS"/}"
    out="$(bash "$CHECK" "$f" 1 2>&1)"; rc=$?
    if grep -qF 'not a UI plan' <<<"$out"; then
      [ "$rc" -eq 0 ] || { printf 'FAIL: real non-UI plan exits %s: %s: %s\n' "$rc" "$rel" "$out"; fail=1; }
    elif [ "$rc" -eq 0 ] || [ "$rc" -eq 1 ] || grep -qF 'Execution log' <<<"$out"; then
      ui_found="$ui_found$rel"$'\n'
    else
      printf 'FAIL: real plan refused for another reason: %s: %s\n' "$rel" "$out"; fail=1
    fi
  done
  got="$(printf '%s' "$ui_found" | sed '/^$/d' | sort)"; want="$(printf '%s\n' "$EXPECTED_UI" | sort)"
  if [ "$got" != "$want" ]; then
    printf 'FAIL: real UI plans differ — expected:\n%s\ngot:\n%s\n' "$want" "$got"; fail=1
  fi
  printf 'sweep: real plans — %s plans under %s; UI: %s\n' "$swept" "$PLANS" "$(tr '\n' ' ' <<<"$got")"
else
  echo "SKIP: real-plan sweep — no $PLANS"
fi

[ "$fail" -eq 0 ] && echo "OK — UI evidence gate: every row holds"
exit "$fail"
