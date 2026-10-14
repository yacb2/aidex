#!/usr/bin/env bash
# test-lifecycle.sh — smoke test for the backlog/plan lifecycle scripts in an
# isolated temp project (register → harvest → close → sweep → reconcile).
# No network, no real .context/ touched. Exits non-zero on first failed assertion.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PLAN_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../plan/scripts" && pwd -P)"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/backlog" "$TMP/.context/plans"
cd "$TMP"

echo "== register =="
NEW="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "lifecycle test item" --priority P2 2>/dev/null)"
ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$NEW")"
check "new item gets id BL-001" '[[ "$ID" == "BL-001" ]]'
check "commits field present and empty" 'grep -q "^commits: \"\"" "$NEW"'
# BL-065: Acceptance is plain "Done means:" bullets, no checkbox ceremony.
check "template uses plain 'Done means' bullets" 'grep -q "Done means" "$NEW"'
check "template has no acceptance checkbox" '! grep -q "^- \[ \]" "$NEW"'

echo "== harvest commit =="
bash "$SCRIPTS/harvest-commit.sh" --sha abc1234 --message "fix

Backlog: $ID" >/dev/null 2>&1
check "harvest records sha" 'grep -q "commits: \"abc1234\"" "$NEW"'
bash "$SCRIPTS/harvest-commit.sh" --sha abc1234 --message "Backlog: $ID" >/dev/null 2>&1
check "harvest idempotent (no dup)" '[[ "$(grep -c abc1234 "$NEW")" == "1" ]]'

echo "== start: type:bug routes into RED->GREEN (BL-134) =="
# The route is keyed on front-matter, never on phrasing: bugfix fired on
# 3 of 103 eligible bug items because backlog reached the work first.
BUG="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "a broken thing" --priority P1 --type bug 2>/dev/null)"
BUG_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$BUG")"
BUG_OUT="$(bash "$SCRIPTS/start-item.sh" "$BUG_ID" 2>&1 >/dev/null)"
check "start flips status to doing" 'grep -q "^status: doing$" "$BUG"'
check "bug item prints the RED->GREEN route" '[[ "$BUG_OUT" == *"RED->GREEN procedure now"* ]]'
check "route names the fail-first ordering" '[[ "$BUG_OUT" == *"written BEFORE the fix"* ]]'
check "start echoes the item path on stdout" \
  '[[ "$(bash "$SCRIPTS/start-item.sh" "$BUG_ID" 2>/dev/null)" == "$BUG" ]]'

TASKY="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "ordinary work" --priority P2 --type task 2>/dev/null)"
TASK_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$TASKY")"
TASK_OUT="$(bash "$SCRIPTS/start-item.sh" "$TASK_ID" 2>&1 >/dev/null)"
check "non-bug item stays silent about RED->GREEN" '[[ "$TASK_OUT" != *"RED->GREEN"* ]]'
check "non-bug item still opens" 'grep -q "^status: doing$" "$TASKY"'

# A deferred item is blocked, not startable — the error must name the fix.
DEFB="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "blocked bug" --priority P2 --type bug 2>/dev/null)"
DEFB_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$DEFB")"
bash "$SCRIPTS/defer-item.sh" defer "$DEFB_ID" --reason "waiting on vendor" >/dev/null 2>&1
DEFB_OUT="$(bash "$SCRIPTS/start-item.sh" "$DEFB_ID" 2>&1 >/dev/null || true)"
check "starting a deferred item points at reactivate" '[[ "$DEFB_OUT" == *"reactivate"* ]]'

echo "== close warns on a bug item with no proof (BL-134) =="
NOPROOF="$(bash "$SCRIPTS/close-item.sh" "$BUG_ID" 2>&1 >/dev/null)"
check "bug close with no proof warns" '[[ "$NOPROOF" == *"no RED->GREEN proof"* ]]'
PROVEN="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "proven bug" --priority P2 --type bug 2>/dev/null)"
PROVEN_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$PROVEN")"
printf -- '\nRED: AssertionError expected full IBAN / GREEN: vitest 730/730\n' >> "$PROVEN"
PROVEN_OUT="$(bash "$SCRIPTS/close-item.sh" "$PROVEN_ID" 2>&1 >/dev/null)"
check "bug close with RED/GREEN line does not warn" '[[ "$PROVEN_OUT" != *"no RED->GREEN proof"* ]]'
# proof_links written as a YAML block list — the shape the conventions document
# and the shape `audit`'s own items use. Reading only the same-line value
# made a correctly-proven item warn (found closing BL-229).
BLOCK="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "block-list proof bug" --priority P2 --type bug 2>/dev/null)"
BLOCK_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$BLOCK")"
python3 - "$BLOCK" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('commits: ""\n', 'commits: ""\nproof_links:\n  - ".context/proofs/x/run.txt"\n', 1)
open(p, "w").write(s)
EOF
BLOCK_OUT="$(bash "$SCRIPTS/close-item.sh" "$BLOCK_ID" 2>&1 >/dev/null)"
check "block-list proof_links counts as proof" '[[ "$BLOCK_OUT" != *"no RED->GREEN proof"* ]]'
# and an EMPTY block list is still no proof
EMPTYB="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "empty block proof bug" --priority P2 --type bug 2>/dev/null)"
EMPTYB_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$EMPTYB")"
python3 - "$EMPTYB" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('commits: ""\n', 'commits: ""\nproof_links:\n', 1)
open(p, "w").write(s)
EOF
EMPTYB_OUT="$(bash "$SCRIPTS/close-item.sh" "$EMPTYB_ID" 2>&1 >/dev/null)"
check "empty block list is still no proof" '[[ "$EMPTYB_OUT" == *"no RED->GREEN proof"* ]]'
TASK_CLOSE="$(bash "$SCRIPTS/close-item.sh" "$TASK_ID" 2>&1 >/dev/null)"
check "non-bug close never mentions the proof gate" '[[ "$TASK_CLOSE" != *"RED->GREEN"* ]]'

echo "== close =="
bash "$SCRIPTS/close-item.sh" "$ID" --commit def5678 >/dev/null 2>&1
check "item left active dir" '[[ ! -f "$NEW" ]]'
check "item now in _archive" '[[ -f ".context/backlog/_archive/$(basename "$NEW")" ]]'
check "index has Closed section" 'grep -q "## Closed" .context/backlog/00-index.md'
check "closed item appears with id" 'grep -q "BL-001" .context/backlog/00-index.md'

echo "== sweep =="
# A legacy done item lingering in the active root: registration archives a done item
# itself now (backlog-c25), so the fixture is an open item hand-edited to done.
LEGACY="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "legacy done" --priority P3 2>/dev/null)"
sed -i.bak 's/^status: open$/status: done/' "$LEGACY" && rm -f "$LEGACY.bak"
SWEEP_DRY="$(bash "$SCRIPTS/sweep.sh" 2>&1 || true)"
check "dry-run finds the done item" '[[ "$SWEEP_DRY" == *"would archive"* ]]'
bash "$SCRIPTS/sweep.sh" --apply >/dev/null 2>&1
check "sweep archived it" '[[ -f ".context/backlog/_archive/$(basename "$LEGACY")" ]]'
SWEEP_AGAIN="$(bash "$SCRIPTS/sweep.sh" 2>&1 || true)"
check "sweep idempotent" '[[ "$SWEEP_AGAIN" == *"clean"* ]]'

# BL-234's companion rule applied to the BATCH path. close-item.sh has called
# archive_companions since it was written; sweep.sh --apply did a bare `mv` and
# left every rendered .html behind in the active folder. Nothing caught it:
# validate.py's crossref_target_exists searches _archive/ too, so the stranded
# page's anchor still resolves and artifact-anchor-target-missing never fires.
# The user counted leftover pages by hand on 2026-08-24, -25 and -29.
COMP="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "has a page" --priority P3 2>/dev/null)"
sed -i.bak 's/^status: open$/status: done/' "$COMP" && rm -f "$COMP.bak"
printf '<meta name="artifact-anchor" content="backlog/%s">\n' "$(basename "$COMP")" \
  > ".context/backlog/$(basename "$COMP" .md)-report.html"
bash "$SCRIPTS/sweep.sh" --apply >/dev/null 2>&1
check "sweep --apply archives the item" '[[ -f ".context/backlog/_archive/$(basename "$COMP")" ]]'
check "sweep --apply takes the rendered companion with it" \
  '[[ -f ".context/backlog/_archive/$(basename "$COMP" .md)-report.html" ]]'
check "no companion is left stranded in the active folder" \
  '[[ ! -f ".context/backlog/$(basename "$COMP" .md)-report.html" ]]'

echo "== defer: id stability + provenance =="
# Regression (suite analysis 2026-07-02): next_backlog_id scanned active + _archive
# but never _deferred/, so deferring an item and registering a new one reused its id,
# breaking the D-09 stable-id invariant. harvest-commit had the same blind spot.
DEF="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "deferred item" --priority P2 2>/dev/null)"
DEF_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$DEF")"
bash "$SCRIPTS/defer-item.sh" defer "$DEF_ID" --reason "external blocker" >/dev/null 2>&1
check "defer moved item to _deferred" '[[ -f ".context/backlog/_deferred/$(basename "$DEF")" ]]'
AFTER="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "after defer" --priority P2 2>/dev/null)"
AFTER_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$AFTER")"
check "id not reused after defer (D-09)" '[[ -n "$AFTER_ID" && "$AFTER_ID" != "$DEF_ID" ]]'
bash "$SCRIPTS/harvest-commit.sh" --sha fedc999 --message "Backlog: $DEF_ID" >/dev/null 2>&1
check "harvest reaches _deferred items" 'grep -q "fedc999" ".context/backlog/_deferred/$(basename "$DEF")"'

echo "== origin_ref is a marker, not a path (BL-055) =="
# --request takes a path for convenience; what gets STORED must be the
# `request/<filename>` cross-ref marker (D-03). A stored path breaks as soon as
# the item is read from anywhere but the directory it was registered from.
mkdir -p ".context/requests"
printf -- '---\ntitle: "r"\nstatus: open\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n' \
  > ".context/requests/2026-01-01-client-ask.md"
REQ_ITEM="$(bash "$SCRIPTS/register-item.sh" --origin request \
  --request ".context/requests/2026-01-01-client-ask.md" \
  --title "from a request" --priority P2 2>/dev/null)"
check "origin_ref normalized to request/<filename>" \
  'grep -q "^origin_ref: request/2026-01-01-client-ask.md$" "$REQ_ITEM"'
check "origin_ref stores no path segments" '! grep -q "^origin_ref:.*\.context/" "$REQ_ITEM"'
MISS="$(bash "$SCRIPTS/register-item.sh" --origin request --request "/tmp/nope-not-here.md" \
  --title "dangling request ref" --priority P3 2>&1 >/dev/null || true)"
check "unresolvable request ref warns, does not fail" '[[ "$MISS" == *"resolves to no file"* ]]'

echo "== list robustness =="
# Regression: read_field piped values through xargs, which chokes on unbalanced
# quotes — any open title with an apostrophe crashed --list (set -e).
bash "$SCRIPTS/register-item.sh" --origin manual --title "Don't break the exporter" --priority P1 >/dev/null 2>&1
check "--list survives apostrophe titles" 'bash "$SCRIPTS/register-item.sh" --list >/dev/null 2>&1'

echo "== plan close + reconcile =="
mkdir -p ".context/plans/2026-01-01-test-plan"
printf -- '---\ntitle: "t"\nstatus: doing\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n' > ".context/plans/2026-01-01-test-plan/00-index.md"
bash "$PLAN_SCRIPTS/close-plan.sh" 2026-01-01-test-plan --commit aaa111 >/dev/null 2>&1
check "plan archived" '[[ -d ".context/plans/_archive/2026-01-01-test-plan" ]]'
# new open item escalated to the now-archived plan -> reconcile category A
ESC="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "escalated" --priority P2 2>/dev/null)"
perl -i -pe 's{^escalated_to: ""}{escalated_to: plan/2026-01-01-test-plan}' "$ESC"
check "reconcile flags close-candidate (exit 1)" '! bash "$SCRIPTS/reconcile.sh" >/dev/null 2>&1'
RECON="$(bash "$SCRIPTS/reconcile.sh" 2>&1 || true)"
check "reconcile names the candidate" '[[ "$RECON" == *"close it"* ]]'

echo "== migrate-priorities polarity =="
# BL-092: a bare invocation rewrote front-matter in place with no preview, the
# opposite polarity of sweep.sh and migrate-ids.sh beside it in the same table.
LEGACY=".context/backlog/2026-01-02-legacy-priority.md"
printf -- '---\ntitle: "legacy priority"\nid: BL-900\nstatus: open\ncreated: 2026-01-02\nupdated: 2026-01-02\npriority: High\n---\n\nbody\n' > "$LEGACY"
BEFORE="$(shasum "$LEGACY" | awk '{print $1}')"
bash "$SCRIPTS/migrate-priorities.sh" >/dev/null 2>&1 || true
AFTER="$(shasum "$LEGACY" | awk '{print $1}')"
check "bare invocation writes nothing (dry-run default)" '[[ "$BEFORE" == "$AFTER" ]]'
bash "$SCRIPTS/migrate-priorities.sh" --apply >/dev/null 2>&1 || true
check "--apply migrates the legacy value" 'grep -q "^priority: P1$" "$LEGACY"'
rm -f "$LEGACY"
# backlog-c05: trimming with xargs died on an apostrophe and set -e stopped the run halfway
printf -- '---\ntitle: "quoted priority"\nid: BL-901\nstatus: open\ncreated: 2026-01-02\nupdated: 2026-01-02\npriority: Medium (don'"'"'t wait)\n---\n\nbody\n' > "$LEGACY"
bash "$SCRIPTS/migrate-priorities.sh" --apply >/dev/null 2>&1 || true
check "--apply survives an apostrophe in a priority note" 'grep -q "^priority: P2$" "$LEGACY"'
rm -f "$LEGACY"
# a quoted legacy value: single quotes, and double quotes with trailing spaces, are one pair to strip
for q in "'High'" '"High"  '; do
  printf -- '---\ntitle: "quoted"\nid: BL-902\nstatus: open\ncreated: 2026-01-02\nupdated: 2026-01-02\npriority: %s\n---\n\nbody\n' "$q" > "$LEGACY"
  bash "$SCRIPTS/migrate-priorities.sh" --apply >/dev/null 2>&1 || true
  check "--apply reads priority $q as High -> P1" 'grep -q "^priority: P1$" "$LEGACY"'
  rm -f "$LEGACY"
done

echo "== closed-section windowing =="
# BL-058: the ## Closed section windows to the most recent 20 closures plus a
# count pointer, so the index tracks the active queue not lifetime throughput.
# Synthesize 25 archived fixtures (distinct updated dates drive the newest-first sort).
for i in $(seq -w 1 25); do
  printf -- '---\ntitle: "closed fixture %s"\nid: BL-9%s\nstatus: done\nupdated: 2026-02-%s\n---\n' "$i" "$i" "$i" \
    > ".context/backlog/_archive/2026-02-$i-closed-fixture-$i.md"
done
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
ARCHIVED_TOTAL="$(ls .context/backlog/_archive/*.md | wc -l | tr -d ' ')"
check "index windows closed section (>20 shows pointer)" 'grep -q "older closed items" .context/backlog/00-index.md'
CLOSED_LINES="$(sed -n '/## Closed/,$p' .context/backlog/00-index.md | grep -c "^- ")"
check "closed section capped at 20 detail lines" '[[ "$CLOSED_LINES" -eq 20 ]]'
EXPECTED_OLDER=$((ARCHIVED_TOTAL - 20))
check "pointer counts the remainder" 'grep -q "and $EXPECTED_OLDER older closed items" .context/backlog/00-index.md'

echo "== index carries the BL id (BL-127) =="
# The id is the key every conversation uses; before BL-127 it appeared only in the
# HTML dash. Two guards: it is emitted on active lines, and an item with no id
# still renders (the reader packs 6 tab-separated fields, and an empty middle field
# used to collapse under a whitespace IFS, shifting id into blocked_by).
rm -f .context/backlog/_archive/*.md
printf -- '---\ntitle: "identified item"\nid: BL-777\nstatus: open\ncreated: 2026-03-01\nupdated: 2026-03-01\npriority: P1\nestimate: S\nblocked_by: ""\n---\n\nbody\n' \
  > ".context/backlog/2026-03-01-identified-item.md"
printf -- '---\ntitle: "anonymous item"\nstatus: open\ncreated: 2026-03-02\nupdated: 2026-03-02\npriority: P1\nestimate: S\nblocked_by: ""\n---\n\nbody\n' \
  > ".context/backlog/2026-03-02-anonymous-item.md"
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
check "active line prefixes the id" 'grep -q "^- \*\*BL-777\*\* · \*\*\[identified item\]" .context/backlog/00-index.md'
check "empty blocked_by does not swallow the id" '! grep -q "blocked_by: \"BL-777\"" .context/backlog/00-index.md'
check "id-less item degrades to a plain line" 'grep -q "^- \*\*\[anonymous item\]" .context/backlog/00-index.md'
echo "== defer a doing item (BL-262) =="
DD="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "doing then deferred" --no-index 2>/dev/null)"; DD_ID="$(awk '/^---/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2}' "$DD")"
bash "$SCRIPTS/start-item.sh" "$DD_ID" >/dev/null 2>&1
bash "$SCRIPTS/defer-item.sh" defer "$DD_ID" --reason "cross-repo" >/dev/null 2>&1
DDF="$(ls .context/backlog/_deferred/*doing-then-deferred*.md 2>/dev/null | sed -n 1p)"
check "a deferred item is status: open, never doing" '[[ -n "$DDF" ]] && grep -q "^status: open$" "$DDF"'


# A malformed id (the hand-authored `BL-20260610` shape) still renders, and the
# nonconforming guard still fails the run — surfacing it must not silence it.
printf -- '---\ntitle: "malformed id item"\nid: BL-20260610\nstatus: open\ncreated: 2026-03-03\nupdated: 2026-03-03\npriority: P1\nestimate: S\nblocked_by: ""\n---\n\nbody\n' \
  > ".context/backlog/2026-03-03-malformed-id-item.md"
MALFORMED_OUT="$(bash "$SCRIPTS/register-item.sh" --reindex 2>&1)" && MALFORMED_RC=0 || MALFORMED_RC=$?
check "malformed id still renders on its line" 'grep -q "^- \*\*BL-20260610\*\* · \*\*\[malformed id item\]" .context/backlog/00-index.md'
check "nonconforming guard still warns" '[[ "$MALFORMED_OUT" == *"nonconforming id BL-20260610"* ]]'
check "nonconforming guard still fails --reindex, with the written-but-id-problem exit 4" '[[ "$MALFORMED_RC" -eq 4 ]]'

echo "== a duplicate id elsewhere must not abort a transition (backlog-c24) =="
# --reindex exits 4 AFTER writing the index when any id is duplicated. start/defer/sweep
# ran it bare under set -e, so the item was already rewritten but the banner, the path on
# stdout and the exit code were lost. 4 is "written, id guard failed", never "stale".
DUP="$TMP/dup"; mkdir -p "$DUP/.context/backlog" "$DUP/.context/plans"
cd "$DUP"
  B1="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "dup start bug" --priority P1 --type bug 2>/dev/null)"
  T1="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "dup defer task" --priority P2 2>/dev/null)"
  D1="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "dup done item" --priority P2 2>/dev/null)"
  sed -i.bak 's/^status: open/status: done/' "$D1" && rm -f "$D1.bak"
  X1="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "dup defer target" --priority P2 2>/dev/null)"
  cp "$T1" .context/backlog/2026-01-01-dup-copy.md   # same id as T1
  DUP_RC=0; DUP_OUT="$(bash "$SCRIPTS/start-item.sh" BL-001 2>&1)" || DUP_RC=$?
  check "start-item still exits 0 with a duplicate id elsewhere" '[[ $DUP_RC -eq 0 ]]'
  check "start-item still prints the bug route" '[[ "$DUP_OUT" == *"RED->GREEN procedure now"* ]]'
  # Re-starting a doing item rewrites the index to identical bytes: with a duplicate id
  # elsewhere the guard exits 4 (written), which is not a stale index (Q23a).
  DUP_RC=0; DUP_OUT="$(bash "$SCRIPTS/start-item.sh" BL-001 2>&1)" || DUP_RC=$?
  check "re-starting a doing item with a duplicate id elsewhere exits 0, never 'stale'" '[[ $DUP_RC -eq 0 && "$DUP_OUT" != *"stale"* && "$DUP_OUT" == *"id problem"* ]]'
  DEF_RC=0; DEF_OUT="$(bash "$SCRIPTS/defer-item.sh" defer "$X1" --reason "x" 2>/dev/null)" || DEF_RC=$?
  check "defer-item still exits 0 with a duplicate id elsewhere" '[[ $DEF_RC -eq 0 ]]'
  check "defer-item still prints the destination on stdout" '[[ "$DEF_OUT" == *"/_deferred/"* ]]'
  SW_RC=0; SW_OUT="$(bash "$SCRIPTS/sweep.sh" --apply 2>&1)" || SW_RC=$?
  check "sweep.sh --apply still exits 0 and reports the archive" '[[ $SW_RC -eq 0 && "$SW_OUT" == *"item(s) archived"* && "$SW_OUT" != *"stale"* ]]'
  D2="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "dup close target" --priority P2 2>/dev/null)"
  CL_RC=0; CL_OUT="$(bash "$SCRIPTS/close-item.sh" "$D2" --status dropped 2>/dev/null)" || CL_RC=$?
  check "close-item archives, prints the destination and exits 4 (index written, id guard failed) with a duplicate id elsewhere" '[[ $CL_RC -eq 4 && "$CL_OUT" == *"/_archive/"* && -f "$CL_OUT" ]]'
cd "$TMP"

echo "== an index that cannot be written is reported, never "rebuilt" (BL-798 through the callers) =="
STALE="$TMP/stale"; mkdir -p "$STALE/.context/backlog" "$STALE/.context/plans"
cd "$STALE"
SB="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "stale bug" --priority P1 --type bug 2>/dev/null)"
SD="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "stale defer" --priority P2 2>/dev/null)"
SX="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "stale done" --priority P2 2>/dev/null)"
sed -i.bak 's/^status: open/status: done/' "$SX" && rm -f "$SX.bak"
chmod 444 .context/backlog/00-index.md
S_RC=0; S_OUT="$(bash "$SCRIPTS/start-item.sh" "$SB" 2>&1)" || S_RC=$?
check "start-item: no 'index rebuilt', names the stale index, fails" '[[ "$S_OUT" != *"index rebuilt"* && "$S_OUT" == *"stale"* && $S_RC -ne 0 ]]'
check "start-item: the bug route and path are still printed" '[[ "$S_OUT" == *"RED->GREEN procedure now"* && "$S_OUT" == *"$SB"* ]]'
D_RC=0; D_OUT="$(bash "$SCRIPTS/defer-item.sh" defer "$SD" --reason x 2>&1)" || D_RC=$?
check "defer-item: no 'index rebuilt', names the stale index, fails" '[[ "$D_OUT" != *"index rebuilt"* && "$D_OUT" == *"stale"* && $D_RC -ne 0 ]]'
check "defer-item: the destination is still printed" '[[ "$D_OUT" == *"/_deferred/"* ]]'
W_RC=0; W_OUT="$(bash "$SCRIPTS/sweep.sh" --apply 2>&1)" || W_RC=$?
check "sweep.sh: no 'index rebuilt', names the stale index, fails" '[[ "$W_OUT" != *"index rebuilt"* && "$W_OUT" == *"stale"* && $W_RC -ne 0 ]]'
chmod 644 .context/backlog/00-index.md
cd "$TMP"

echo "== a slug resolves to its item (backlog-c36) =="
SLUGP="$TMP/slug"; mkdir -p "$SLUGP/.context/backlog" "$SLUGP/.context/plans"
cd "$SLUGP"
S1="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "fix the parser" --priority P2 --type bug --no-index 2>/dev/null)"
S2="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "fix the parser" --priority P2 --no-index 2>/dev/null)"   # same slug, other id
S3="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "second thing" --priority P2 --no-index 2>/dev/null)"
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
S_RC=0; bash "$SCRIPTS/start-item.sh" second-thing --no-index >/dev/null 2>&1 || S_RC=$?
check "start-item accepts the bare slug" '[[ $S_RC -eq 0 ]] && grep -q "^status: doing$" "$S3"'
S_RC=0; A_OUT="$(bash "$SCRIPTS/start-item.sh" fix-the-parser --no-index 2>&1)" || S_RC=$?
check "an ambiguous exact slug exits 2 naming 'ambiguous', both items unchanged" '[[ $S_RC -eq 2 && "$A_OUT" == *"ambiguous"* ]] && ! grep -q "^status: doing$" "$S1" "$S2"'
S_RC=0; bash "$SCRIPTS/start-item.sh" parser --no-index >/dev/null 2>&1 || S_RC=$?
check "a partial word is not a slug" '[[ $S_RC -eq 2 ]] && ! grep -q "^status: doing$" "$S1"'
C_RC=0; bash "$SCRIPTS/close-item.sh" second-thing --no-index >/dev/null 2>&1 || C_RC=$?
check "close-item accepts the bare slug" '[[ $C_RC -eq 0 && -f ".context/backlog/_archive/$(basename "$S3")" ]]'
IDX_SUM="$(cksum < .context/backlog/00-index.md)"
C_RC=0; bash "$SCRIPTS/close-item.sh" index --no-index >/dev/null 2>&1 || C_RC=$?
check "close-item never takes 00-index.md for a slug" '[[ $C_RC -ne 0 && -f .context/backlog/00-index.md && "$(cksum < .context/backlog/00-index.md)" == "$IDX_SUM" ]]'
# the index is not an item under any spelling: rejected by the basename guard, file untouched
for t in 00-index.md 00-index; do
  for sc in start-item.sh close-item.sh "defer-item.sh defer"; do
    G_RC=0; if [[ "$sc" == defer-item.sh* ]]; then bash "$SCRIPTS/defer-item.sh" defer "$t" --reason x --no-index >/dev/null 2>&1 || G_RC=$?
    else bash "$SCRIPTS/$sc" "$t" --no-index >/dev/null 2>&1 || G_RC=$?; fi
    check "$sc $t: rc 2, 00-index.md untouched and active" '[[ $G_RC -eq 2 && "$(cksum < .context/backlog/00-index.md)" == "$IDX_SUM" && ! -e .context/backlog/_deferred/00-index.md && ! -e .context/backlog/_archive/00-index.md ]]'
  done
done
DS="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "fix the parser two" --priority P2 --no-index 2>/dev/null)"
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1; IDX_SUM="$(cksum < .context/backlog/00-index.md)"
G_RC=0; bash "$SCRIPTS/defer-item.sh" defer index --reason x --no-index >/dev/null 2>&1 || G_RC=$?
check "defer-item: 'index' is not a slug" '[[ $G_RC -ne 0 && "$(cksum < .context/backlog/00-index.md)" == "$IDX_SUM" && ! -e .context/backlog/_deferred/00-index.md ]]'
G_RC=0; bash "$SCRIPTS/defer-item.sh" defer fix-the-parser-two --reason x --no-index >/dev/null 2>&1 || G_RC=$?
check "defer-item: the exact slug still defers" '[[ $G_RC -eq 0 && -f ".context/backlog/_deferred/$(basename "$DS")" ]]'
cd "$TMP"

echo
echo "lifecycle: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
