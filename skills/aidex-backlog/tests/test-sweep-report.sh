#!/usr/bin/env bash
# test-sweep-report.sh — the report is generated from disk, every section renders, the
# owner rows are aggregated, growth is flagged past 25 %, and the anchor validates.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
CONV="$(cd "$SCRIPTS/../../aidex-conventions/scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/.context/backlog" "$P/bin"; cd "$P"
git init -q . 2>/dev/null; git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "c1" 2>/dev/null
SHA1="$(git rev-parse --short HEAD)"; git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "c2"; SHA2="$(git rev-parse --short HEAD)"
reg() { bash "$SCRIPTS/register-item.sh" --origin manual --no-index "$@" 2>/dev/null; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
row() { printf '| %s | %s | %s |\n' "$2" "$3" "$4" > "$TMP/row"
  awk -v r="$(cat "$TMP/row")" '{print} /^\|---\|---\|---\|$/ && !d {print r; d=1}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
accept() { sed -i.bak 's/^- <!-- concrete, verifiable criterion -->$/- done means done/' "$1" && rm -f "$1.bak"; }

echo "sweep-report:"
A="$(reg --title "alpha" --estimate XS)"; AID="$(idof "$A")"; accept "$A"; row "$A" test "tests/a.py" "3 passed"; row "$A" owner "toast wording" ""
B="$(reg --title "bravo" --estimate S --surface ui)"; BID="$(idof "$B")"; accept "$B"; row "$B" smoke "/settings" "proofs/b.png"; row "$B" owner "badge colour" "fine — owner 2026-08-27"
N="$(reg --title "needs a decision" --estimate XS)"; NID="$(idof "$N")"
WL="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Report run" --slug report-run 2>/dev/null | tail -1)"
[[ -f "$WL" ]] && ok "kickoff wrote the work-list" || bad "no worklist"
bash "$SCRIPTS/close-item.sh" "$AID" --sweep --commit "$SHA1" --no-index >/dev/null 2>&1
bash "$CONV/worklist-advance.sh" "$WL" >/dev/null 2>&1        # ticks A (already closed), starts B
bash "$SCRIPTS/close-item.sh" "$BID" --sweep --commit "$SHA2" --no-index >/dev/null 2>&1
E="$(reg --title "emergent one")"; EID="$(idof "$E")"
bash "$CONV/worklist-advance.sh" "$WL" --append "backlog:$EID — emergent one" >/dev/null 2>&1
bash "$CONV/worklist-advance.sh" "$WL" --append "inline:loose end, carry to the next sweep" >/dev/null 2>&1
# a gate history with one re-run of the frontend leg
mkdir -p _tmp/sweep-gate
printf '[{"leg":"backend","exit":"0","count":"10","secs":"7"},{"leg":"frontend","exit":"1","count":"9","secs":"5"},{"verdict":"FAIL","legs":2,"failed":1,"pending":0,"at":"2026-08-27T10:00:00"}]\n' > _tmp/sweep-gate/gate-history.jsonl
printf '[{"leg":"frontend","exit":"0","count":"10","secs":"6"},{"verdict":"PASS","legs":1,"failed":0,"pending":0,"at":"2026-08-27T10:05:00"}]\n' >> _tmp/sweep-gate/gate-history.jsonl

OUT="$(bash "$SCRIPTS/sweep-report.sh" report-run 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && -f "$OUT" && "$OUT" == "$P/.context/research/"*"-report-run-sweep-report.md" ]] && ok "report written under research/ with the run slug" || bad "report: rc=$RC $OUT"
R="$(cat "$OUT")"
grep -q "^origin_ref: worklist/$(basename "$WL")$" "$OUT" && ok "anchored origin_ref: worklist/<file>" || bad "anchor: $(grep origin_ref "$OUT")"
for h in "## Metrics" "## Closed items" "## Owner rows" "## Needs decision" "## Deferrals and mid-flight skips" "## Boundary gate"; do
  grep -q "^$h" "$OUT" && ok "section renders: $h" || bad "missing section $h"
done
grep -q "### $AID — alpha" "$OUT" && grep -q "### $BID — bravo" "$OUT" && ok "both closed items listed" || bad "closed items"
grep -q "\`$SHA1\`" "$OUT" && grep -q "\`$SHA2\`" "$OUT" && ok "commits carried from commits:" || bad "commits"
grep -q "| test | tests/a.py | 3 passed |" "$OUT" && ok "verification rows carried verbatim" || bad "rows"
grep -q "| $AID — alpha | toast wording | \*\*unanswered\*\* |" "$OUT" && grep -q "| $BID — bravo | badge colour | fine — owner 2026-08-27 |" "$OUT" \
  && ok "owner rows aggregated across items, answered and unanswered" || bad "owner rows: $(grep -A4 'Owner rows' "$OUT")"
grep -q "^- $NID — needs a decision   <!-- reason: no Acceptance -->" "$OUT" && ok "NEEDS-DECISION recorded at kickoff, carried unchanged" || bad "needs decision: $(grep -A3 'Needs decision' "$OUT")"
grep -q "loose end, carry to the next sweep" "$OUT" && ok "deferrals listed" || bad "deferrals"
grep -q "| items queued at kickoff | 2 |" "$OUT" && grep -q "| items closed | 2 |" "$OUT" && ok "metrics: queued 2, closed 2" || bad "metrics: $(grep -A6 '## Metrics' "$OUT")"
grep -q "| emergent items appended | 1  \*\*> 25 % of the original queue\*\* |" "$OUT" && ok "emergent growth 1/2 flagged past 25 %" || bad "growth: $(grep emergent "$OUT")"
grep -q "| commits (from \`commits:\`) | 2 |" "$OUT" && ok "commit count" || bad "commit count"
grep -q "| gate runs / legs re-run | 2 / 1 |" "$OUT" && ok "gate runs 2, frontend leg re-run once" || bad "gate: $(grep 'gate runs' "$OUT")"
grep -q "| time in boundary-gate suites | 18 s |" "$OUT" && ok "gate seconds summed (7+5+6)" || bad "gate secs: $(grep 'boundary-gate suites' "$OUT")"
grep -q "leg=frontend exit=1 count=9 secs=5" "$OUT" && grep -q "verdict \*\*PASS\*\*" "$OUT" && ok "gate rows verbatim, both runs" || bad "gate rows"
grep -q "$EID: not reached" "$OUT" && ok "the appended emergent item that was never worked is reported as not reached" || bad "emergent skip: $(grep "$EID" "$OUT")"
# anchor validates (research is walked by validate.py; worklist/ resolves in the active folder)
python3 "$CONV/validate.py" --type research 2>&1 | grep -q "cross-ref-target-missing" && bad "anchor flagged by validate.py" || ok "anchor validates against the active work-list"
bash "$CONV/worklist-close.sh" "$WL" --force >/dev/null 2>&1
python3 "$CONV/validate.py" --type research 2>&1 | grep -q "cross-ref-target-missing" && bad "anchor broke after archive" || ok "anchor still validates after the work-list archives"
# no owner rows anywhere → the recorded-skip line, never silence
C="$(reg --title "charlie")"; CID="$(idof "$C")"; accept "$C"; row "$C" test "t" "1 passed"
WL2="$(bash "$CONV/worklist-new.sh" --title "No owner" --mode sweep --ref "backlog:$CID — c")"
bash "$SCRIPTS/close-item.sh" "$CID" --sweep --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-report.sh" "$WL2" --print 2>/dev/null | grep -q "^human-verification: skipped — no queued item carries an owner row" \
  && ok "no owner rows → human-verification: skipped line recorded" || bad "skip line missing"
bash "$SCRIPTS/sweep-report.sh" no-such-run >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "unknown worklist exits 2" || bad "unknown worklist"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — sweep report: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
