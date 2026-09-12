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
reg() { local f; f="$(bash "$SCRIPTS/register-item.sh" --origin manual --no-index --verify "a targeted test" "$@" 2>/dev/null)"
  python3 - "$f" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read()
t=re.sub(r'(## Context\n)', r'\1\nWhy this matters, in prose.\n', t, count=1);open(p,'w').write(t)
PY
  bash "$SCRIPTS/define-item.sh" "$f" --touches "apps/misc.py" --no-index >/dev/null 2>&1; printf '%s\n' "$f"; }
idof() { awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$1"; }
row() { printf '| %s | %s | %s |\n' "$2" "$3" "$4" > "$TMP/row"
  awk -v r="$(cat "$TMP/row")" '{print} /^\|---\|---\|---\|$/ && !d {print r; d=1}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"; }
accept() { sed -i.bak 's/^- <!-- concrete, verifiable criterion -->$/- done means done/' "$1" && rm -f "$1.bak"; }

echo "sweep-report:"
A="$(reg --title "alpha" --estimate XS)"; AID="$(idof "$A")"; accept "$A"; row "$A" test "tests/a.py" "3 passed"; row "$A" owner "toast wording" "ok — owner 2026-08-27"
B="$(reg --title "bravo" --estimate S --surface ui)"; BID="$(idof "$B")"; accept "$B"; row "$B" smoke "/settings" "proofs/b.png"; row "$B" owner "badge colour" "fine — owner 2026-08-27"
C="$(reg --title "charlie" --estimate XS)"; CID="$(idof "$C")"; accept "$C"; row "$C" test "tests/c.py" "1 passed"; row "$C" owner "menu order" ""
N="$(reg --title "needs a decision" --estimate XS)"; NID="$(idof "$N")"
python3 - "$N" <<'PY'
import sys,re;p=sys.argv[1];t=open(p).read();t=re.sub(r'^touches:.*\n','',t,count=1,flags=re.M);open(p,'w').write(t)
PY
WL="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Report run" --slug report-run 2>/dev/null | tail -1)"
[[ -f "$WL" ]] && ok "kickoff wrote the work-list" || bad "no worklist"
bash "$SCRIPTS/close-item.sh" "$AID" --sweep --commit "$SHA1" --no-index >/dev/null 2>&1
bash "$CONV/worklist-advance.sh" "$WL" >/dev/null 2>&1        # ticks A (already closed), starts B
bash "$SCRIPTS/close-item.sh" "$BID" --sweep --commit "$SHA2" --no-index >/dev/null 2>&1
bash "$CONV/worklist-advance.sh" "$WL" >/dev/null 2>&1        # ticks B, starts C
bash "$SCRIPTS/close-item.sh" "$CID" --sweep --no-index >/dev/null 2>&1   # parks C (owner row open)
bash "$CONV/worklist-advance.sh" "$WL" >/dev/null 2>&1        # ticks C (parked counts as handled)
E="$(reg --title "emergent one")"; EID="$(idof "$E")"
bash "$CONV/worklist-advance.sh" "$WL" --append "backlog:$EID — emergent one" >/dev/null 2>&1
bash "$CONV/worklist-advance.sh" "$WL" --append "inline:loose end, carry to the next sweep" >/dev/null 2>&1
# a gate history with one re-run of the frontend leg
mkdir -p .context/proofs/sweep-gate
printf '[{"leg":"backend","exit":"0","count":"10","secs":"7"},{"leg":"frontend","exit":"1","count":"9","secs":"5"},{"verdict":"FAIL","legs":2,"failed":1,"pending":0,"at":"2026-08-27T10:00:00"}]\n' > .context/proofs/sweep-gate/gate-history.jsonl
printf '[{"leg":"frontend","exit":"0","count":"10","secs":"6"},{"verdict":"PASS","legs":1,"failed":0,"pending":0,"at":"2026-08-27T10:05:00"}]\n' >> .context/proofs/sweep-gate/gate-history.jsonl

OUT="$(bash "$SCRIPTS/sweep-report.sh" report-run 2>/dev/null)"; RC=$?
[[ $RC -eq 0 && -f "$OUT" && "$OUT" == "$P/.context/worklists/_archive/$(basename "$WL" .md)-report.md" ]] && ok "report is the work-list's companion: worklists/_archive/<worklist>-report.md" || bad "report: rc=$RC $OUT"
R="$(cat "$OUT")"
grep -q "^origin_ref: worklist/$(basename "$WL")$" "$OUT" && ok "anchored origin_ref: worklist/<file>" || bad "anchor: $(grep origin_ref "$OUT")"
for h in "## Metrics" "## Closed items" "## Awaiting owner" "## Owner rows" "## Needs decision" "## Deferrals and mid-flight skips" "## Boundary gate"; do
  grep -q "^$h" "$OUT" && ok "section renders: $h" || bad "missing section $h"
done
grep -q "### $AID — alpha" "$OUT" && grep -q "### $BID — bravo" "$OUT" && ok "both closed items listed" || bad "closed items"
grep -q "\`$SHA1\`" "$OUT" && grep -q "\`$SHA2\`" "$OUT" && ok "commits carried from commits:" || bad "commits"
grep -q "| test | tests/a.py | 3 passed |" "$OUT" && ok "verification rows carried verbatim" || bad "rows"
grep -q "| $CID — charlie | menu order | \*\*unanswered\*\* |" "$OUT" && grep -q "| $BID — bravo | badge colour | fine — owner 2026-08-27 |" "$OUT" \
  && ok "owner rows aggregated across items, answered and unanswered" || bad "owner rows: $(grep -A4 'Owner rows' "$OUT")"
grep -q "^- $CID — charlie: menu order" "$OUT" && ! grep -q "### $CID" "$OUT" && ok "the parked item is listed under Awaiting owner, not among the closed" || bad "parked: $(grep -A3 'Awaiting owner' "$OUT")"
grep -q "^- $NID — needs a decision   <!-- reason: underdefined: touches, Acceptance -->" "$OUT" && ok "NEEDS-DECISION recorded at kickoff, carried unchanged" || bad "needs decision: $(grep -A3 'Needs decision' "$OUT")"
grep -q "loose end, carry to the next sweep" "$OUT" && ok "deferrals listed" || bad "deferrals"
grep -q "| items queued at kickoff | 3 |" "$OUT" && grep -q "| items closed | 2 |" "$OUT" && ok "metrics: queued 3, closed 2 (the parked one is not closed)" || bad "metrics: $(grep -A6 '## Metrics' "$OUT")"
grep -q "| emergent items appended | 1  \*\*> 25 % of the original queue\*\* |" "$OUT" && ok "emergent growth 1/3 flagged past 25 %" || bad "growth: $(grep emergent "$OUT")"
grep -q "| commits (from \`commits:\`) | 2 |" "$OUT" && ok "commit count" || bad "commit count"
grep -q "| gate runs / legs re-run | 2 / 1 |" "$OUT" && ok "gate runs 2, frontend leg re-run once" || bad "gate: $(grep 'gate runs' "$OUT")"
grep -q "| time in boundary-gate suites | 18 s |" "$OUT" && ok "gate seconds summed (7+5+6)" || bad "gate secs: $(grep 'boundary-gate suites' "$OUT")"
grep -q "leg=frontend exit=1 count=9 secs=5" "$OUT" && grep -q "verdict \*\*PASS\*\*" "$OUT" && ok "gate rows verbatim, both runs" || bad "gate rows"
grep -q "$EID: not reached" "$OUT" && ok "the appended emergent item that was never worked is reported as not reached" || bad "emergent skip: $(grep "$EID" "$OUT")"
# the companion survives the work-list's own archive, next to it
bash "$CONV/worklist-close.sh" "$WL" --force >/dev/null 2>&1
[[ -f "$P/.context/worklists/_archive/$(basename "$WL")" && -f "$OUT" ]] && ok "work-list and its report sit together in worklists/_archive/ after close" || bad "companion after archive: $(ls "$P/.context/worklists/_archive/")"
# no owner rows anywhere → the recorded-skip line, never silence
C="$(reg --title "charlie")"; CID="$(idof "$C")"; accept "$C"; row "$C" test "t" "1 passed"
WL2="$(bash "$CONV/worklist-new.sh" --title "No owner" --mode sweep --ref "backlog:$CID — c")"
bash "$SCRIPTS/close-item.sh" "$CID" --sweep --no-index >/dev/null 2>&1
bash "$SCRIPTS/sweep-report.sh" "$WL2" --print 2>/dev/null | grep -q "^human-verification: skipped — no queued item carries an owner row" \
  && ok "no owner rows → human-verification: skipped line recorded" || bad "skip line missing"
bash "$SCRIPTS/sweep-report.sh" no-such-run >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "unknown worklist exits 2" || bad "unknown worklist"

# BL-253: `commits: "backend 25e07c2 frontend 5b4e89b"` names the repo beside each hash
# in a multi-repo workspace; the report counted the names as commits (5 for 3)
M="$(reg --title "multi repo" --estimate XS)"; MID="$(idof "$M")"; accept "$M"; row "$M" test "tests/m.py" "2 passed"
WL3="$(bash "$SCRIPTS/sweep-kickoff.sh" --title "Multi repo run" --slug multi-repo-run 2>/dev/null | tail -1)"
bash "$SCRIPTS/close-item.sh" "$MID" --sweep --no-index >/dev/null 2>&1
MF="$(ls .context/backlog/_archive/*bl-*multi-repo*.md | head -1)"
python3 - "$MF" "backend $SHA1 frontend $SHA2" <<'PY2'
import sys,re;p,v=sys.argv[1:3];t=open(p).read();t=re.sub(r'^commits:.*\n','',t,count=1,flags=re.M)
t=re.sub(r'^(status:.*\n)', lambda m: m.group(1)+'commits: "'+v+'"\n', t, count=1, flags=re.M);open(p,'w').write(t)
PY2
grep -q "^commits: \"backend" "$MF" || bad "fixture: commits not stamped"
R3="$(bash "$SCRIPTS/sweep-report.sh" multi-repo-run --print 2>/dev/null)"
grep -q "| commits (from \`commits:\`) | 2 |" <<<"$R3" && ok "repo names beside hashes are not counted as commits (2, not 4)" || bad "commit count: $(grep 'commits (from' <<<"$R3")"
grep -q "commits: \`$SHA1\`, \`$SHA2\`" <<<"$R3" && ok "only the hashes are listed per item" || bad "per-item commits: $(grep 'commits:' <<<"$R3" | head -2)"

# the companion report sorts before the work-list; a second render by slug must read the
# work-list, never its own previous report (2026-08-28)
bash "$SCRIPTS/sweep-report.sh" multi-repo-run >/dev/null 2>&1   # writes the companion to disk
mv "$WL3" .context/worklists/_archive/   # closed: both files now sit in _archive/, companion first
R4="$(bash "$SCRIPTS/sweep-report.sh" multi-repo-run --print 2>/dev/null)"
grep -q "^title: \"Sweep report — Multi repo run\"" <<<"$R4" && ! grep -q "Sweep report — Sweep report" <<<"$R4" \
  && ok "re-rendering by slug reads the work-list, not its own -report.md companion" || bad "self-render: $(grep '^title' <<<"$R4")"

# BL-261: a parked item keeps the resolving commit — it was lost until the owner closed by hand
K="$(reg --title "parked with commit" --estimate XS)"; KID="$(idof "$K")"; accept "$K"; row "$K" test "tests/k.py" "1 passed"; row "$K" owner "wording" ""
bash "$SCRIPTS/close-item.sh" "$KID" --sweep --commit "$SHA1" --no-index >/dev/null 2>&1
grep -q "^awaiting: owner$" "$K" && grep -q "^commits: \"$SHA1\"$" "$K" && ok "parked item carries awaiting: owner AND commits: <sha>" || bad "parked commits: $(grep -E '^(awaiting|commits)' "$K")"

# BL-345: the report is also a PAGE. Close-out used to hand over an .md and the
# reader asked for the artifact every time; the wrap is now part of writing it.
MD="$(bash "$SCRIPTS/sweep-report.sh" report-run 2>"$TMP/rep.err")"
ERR="$(cat "$TMP/rep.err")"
[[ "$MD" == *.md && -s "$MD" ]] && ok "stdout is still exactly one path, the markdown canon" || bad "stdout: $MD"
PAGE="$(sed -n 's/^page: //p' <<<"$ERR" | head -1)"
if [[ -s "$PAGE" && "$PAGE" == "${MD%.md}.html" ]]; then
  ok "a .html page is written beside the report and named on stderr"
else
  bad "no .html companion beside the report: [$ERR]"
fi
# Non-empty input, at the page: a queued item's id must be IN the page, so a wrap
# of an empty or half-rendered report cannot pass this as green.
if [[ -s "$PAGE" ]] && grep -q "$AID" "$PAGE"; then
  ok "the page carries a queued item's id ($AID) — it saw real input"
else
  bad "the page does not carry $AID"
fi
CHK="$SCRIPTS/../../aidex-artifact/scripts/check-artifact.sh"
if [[ -s "$PAGE" ]]; then
  bash "$CHK" "$PAGE" > "$TMP/chk.out" 2>&1
  [[ $? -eq 0 ]] && ok "the page passes check-artifact.sh" || bad "check-artifact.sh on the page: $(cat "$TMP/chk.out")"
fi
# --print stays a preview: it writes nothing at all, page included.
# Guarded on a NON-EMPTY path first. With the wrap regressed, PAGE is the empty
# string, `rm -f ""` succeeds and `[[ ! -e "" ]]` is true — so this cell used to
# report ok in exactly the regime it exists to catch.
rm -f "$PAGE"
bash "$SCRIPTS/sweep-report.sh" report-run --print >/dev/null 2>&1
if [[ -z "$PAGE" ]]; then
  bad "--print: no page path to assert against (the wrap never named one), so this cell would pass vacuously"
elif [[ ! -e "$PAGE" ]]; then
  ok "--print writes no page"
else
  bad "--print wrote $PAGE"
fi

# BL-382: the page is what the owner reads and it carries the owner rows and the
# needs-decision list, so it belongs in the profile's `language:` — but ~95 % of
# its body is `.context/` quotation, so no script can write it there. With a
# non-en profile the script keeps the English page as the fallback, writes the
# translation SOURCE (generator prose already localized) under _tmp/, never
# .context/ (D-04), and names the stage-6 step on stderr. Wrapping that source
# over the page is the step, and it passes the lang gate.
printf -- '- language: es\n' > .context/artifact-style.md
MD2="$(bash "$SCRIPTS/sweep-report.sh" report-run 2>"$TMP/rep2.err")"
PAGE2="$(sed -n 's/^page: //p' "$TMP/rep2.err" | head -1)"
SRC2="$P/_tmp/sweep-report/$(basename "${MD2%.md}").es.md"
grep -q '^## Owner rows — what only the owner can judge' "$MD2" && ok "language: es — the .md keeps its English headings (D-04)" || bad "the .md drifted from English: $(grep '^## ' "$MD2" | head -3)"
[[ -s "$PAGE2" ]] && grep -q '<html[^>]*lang="en"' "$PAGE2" && ok "language: es — the English page is still written as the fallback" || bad "fallback page: $(grep -o '<html[^>]*>' "$PAGE2" 2>/dev/null) [$(cat "$TMP/rep2.err")]"
if [[ -s "$SRC2" ]] && grep -q '^## Filas del owner' "$SRC2" && grep -q "$AID" "$SRC2" && ! grep -rq 'Filas del owner' .context/; then
  ok "language: es — the translation source is under _tmp/ with the generator's prose in es, and nothing es lands in .context/"
else
  bad "translation source: $(ls "$SRC2" 2>&1) $(grep -c 'Filas del owner' "$SRC2" 2>/dev/null)"
fi
grep -q "^translate: .*$SRC2 .*--lang es .*--out $PAGE2" "$TMP/rep2.err" && ok "language: es — stderr names the stage-6 step: source, --lang es, the same page" || bad "no translate line: $(cat "$TMP/rep2.err")"
T2="$(sed -n 's/^title: *"\{0,1\}\(.*[^"]\)"\{0,1\} *$/\1/p' "$SRC2" | head -1)"
if bash "$SCRIPTS/../../aidex-artifact/scripts/wrap-report.sh" --title "$T2" --lang es --in "$SRC2" --out "$PAGE2" >"$TMP/wrap2.out" 2>&1 && grep -q '<html[^>]*lang="es"' "$PAGE2" && grep -q 'Filas del owner' "$PAGE2"; then
  ok "language: es — wrapping the source over the page yields lang=\"es\" and passes the contract (lang gate included)"
else
  bad "wrap of the es source: $(cat "$TMP/wrap2.out")"
fi
rm -f .context/artifact-style.md
bash "$SCRIPTS/sweep-report.sh" report-run >/dev/null 2>"$TMP/rep4.err"
if ! grep -q '^translate:' "$TMP/rep4.err" && grep -q '<html[^>]*lang="en"' "$PAGE2"; then
  ok "no profile — no translate line, the page is the English record as before"
else
  bad "no profile: $(grep -c '^translate:' "$TMP/rep4.err") translate line(s), $(grep -o '<html[^>]*>' "$PAGE2")"
fi
rm -f "$PAGE2"

# A non-.md --out has no page: the wrap converts a .md INPUT only, so wrapping the
# report at `<out>.html` would carry the raw markdown as page content and fail the
# contract. The report still gets written; the page is declined out loud.
TXT="$TMP/report-run.txt"
bash "$SCRIPTS/sweep-report.sh" report-run --out "$TXT" 2>"$TMP/txt.err" >/dev/null
if [[ -s "$TXT" && ! -e "$TXT.html" && ! -e "${TXT%.md}.html" ]] && grep -q "not a .md path" "$TMP/txt.err"; then
  ok "a non-.md --out writes the report and declines the page, with a note"
else
  bad "non-.md --out: report=$(wc -c <"$TXT" 2>/dev/null) page=$(ls "$TXT.html" 2>/dev/null) err=$(cat "$TMP/txt.err")"
fi

echo; [[ $FAIL -eq 0 ]] && { echo "OK — sweep report: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
