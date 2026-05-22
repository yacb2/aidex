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

echo
echo "lifecycle: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
