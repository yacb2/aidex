#!/usr/bin/env bash
# test-lifecycle.sh — smoke test for the backlog/plan lifecycle scripts in an
# isolated temp project (register → harvest → close → sweep → reconcile).
# No network, no real .context/ touched. Exits non-zero on first failed assertion.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PLAN_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-plan/scripts" && pwd -P)"
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

echo "== close =="
bash "$SCRIPTS/close-item.sh" "$ID" --commit def5678 >/dev/null 2>&1
check "item left active dir" '[[ ! -f "$NEW" ]]'
check "item now in _archive" '[[ -f ".context/backlog/_archive/$(basename "$NEW")" ]]'
check "index has Closed section" 'grep -q "## Closed" .context/backlog/00-index.md'
check "closed item appears with id" 'grep -q "BL-001" .context/backlog/00-index.md'

echo "== sweep =="
LEGACY="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "legacy done" --priority P3 --status done 2>/dev/null)"
SWEEP_DRY="$(bash "$SCRIPTS/sweep.sh" 2>&1 || true)"
check "dry-run finds the done item" '[[ "$SWEEP_DRY" == *"would archive"* ]]'
bash "$SCRIPTS/sweep.sh" --apply >/dev/null 2>&1
check "sweep archived it" '[[ -f ".context/backlog/_archive/$(basename "$LEGACY")" ]]'
SWEEP_AGAIN="$(bash "$SCRIPTS/sweep.sh" 2>&1 || true)"
check "sweep idempotent" '[[ "$SWEEP_AGAIN" == *"clean"* ]]'

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

# A malformed id (the hand-authored `BL-20260610` shape) still renders, and the
# nonconforming guard still fails the run — surfacing it must not silence it.
printf -- '---\ntitle: "malformed id item"\nid: BL-20260610\nstatus: open\ncreated: 2026-03-03\nupdated: 2026-03-03\npriority: P1\nestimate: S\nblocked_by: ""\n---\n\nbody\n' \
  > ".context/backlog/2026-03-03-malformed-id-item.md"
MALFORMED_OUT="$(bash "$SCRIPTS/register-item.sh" --reindex 2>&1)" && MALFORMED_RC=0 || MALFORMED_RC=$?
check "malformed id still renders on its line" 'grep -q "^- \*\*BL-20260610\*\* · \*\*\[malformed id item\]" .context/backlog/00-index.md'
check "nonconforming guard still warns" '[[ "$MALFORMED_OUT" == *"nonconforming id BL-20260610"* ]]'
check "nonconforming guard still fails --reindex" '[[ "$MALFORMED_RC" -eq 1 ]]'

echo
echo "lifecycle: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
