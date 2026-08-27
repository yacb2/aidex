#!/usr/bin/env bash
# test-triage.sh — the consolidated backlog health check, tested on failing inputs.
#
# Two things this must get right, and both are easy to get wrong:
#   1. It reports each of its four checks independently and exits non-zero on any.
#   2. It is READ-ONLY. The id check is the trap: the obvious implementation is
#      `register-item.sh --reindex`, which regenerates 00-index.md as a side effect. A
#      "read-only" report that rewrites a file is the "mutators fake success" pattern the
#      2026-07-25 audit named, so the byte-identity assertion below is the real contract.

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
TRIAGE="$SCRIPTS/triage.sh"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/backlog" "$TMP/.context/plans"
cd "$TMP"
# reconcile flags a missing plans roll-up, so the "clean" baseline needs one — otherwise
# the clean case is not clean and every assertion below measures the fixture, not the code.
bash "$SCRIPTS/../../aidex-plan/scripts/reindex-plans.sh" >/dev/null 2>&1 || true

item() {  # item <file> <id> <status> [title] — a DEFINED item (the contract is its own check below)
  printf -- '---\ntitle: "%s"\nid: %s\nstatus: %s\ncreated: 2026-01-01\nupdated: 2026-01-01\npriority: P2\ntype: task\nestimate: S\nsurface: internal\nverify: "a test"\ntouches: "src/x.py"\nblocked_by: ""\ncommits: "abc1234"\n---\n\n## Context\n\nWhy this exists, in prose.\n\n## Acceptance\n\n- the thing is done\n' \
    "${4:-item $2}" "$2" "$3" > ".context/backlog/$1"
}

echo "== clean backlog =="
item 2026-01-01-alpha.md BL-001 open
bash "$SCRIPTS/register-item.sh" --reindex >/dev/null 2>&1
OUT="$(bash "$TRIAGE" 2>&1)"; RC=$?
check "clean tree exits 0" '[[ $RC -eq 0 ]]'
check "clean tree says so" '[[ "$OUT" == *"clean"* ]]'
check "all four checks report ok" '[[ "$(grep -c "\[ok\]" <<<"$OUT")" -eq 4 ]]'

echo "== read-only: the index is not rewritten =="
# The whole point of --check-ids. Compare bytes, not mtime: a regeneration produces the
# same content most days, so mtime would pass while the file was in fact rewritten.
BEFORE="$(shasum .context/backlog/00-index.md | awk '{print $1}')"
BEFORE_MT="$(ls -l .context/backlog/00-index.md)"
bash "$TRIAGE" >/dev/null 2>&1
AFTER="$(shasum .context/backlog/00-index.md | awk '{print $1}')"
AFTER_MT="$(ls -l .context/backlog/00-index.md)"
check "index content unchanged" '[[ "$BEFORE" == "$AFTER" ]]'
check "index not even touched" '[[ "$BEFORE_MT" == "$AFTER_MT" ]]'

echo "== ids: a duplicate id is actionable =="
item 2026-01-02-beta.md BL-001 open "duplicate of alpha"
OUT="$(bash "$TRIAGE" 2>&1)"; RC=$?
check "duplicate id fires the ids check" '[[ "$OUT" == *"ids"*"duplicate"* ]]'
check "any finding exits 1" '[[ $RC -eq 1 ]]'
check "the report names a fix command" '[[ "$OUT" == *"fix:"* ]]'
check "it says nothing was changed" '[[ "$OUT" == *"Nothing was changed"* ]]'
rm -f .context/backlog/2026-01-02-beta.md

echo "== ids: a nonconforming id is actionable =="
item 2026-01-03-gamma.md BL-20260610 open "hand-authored id"
OUT="$(bash "$TRIAGE" 2>&1)"
check "nonconforming id fires the ids check" '[[ "$OUT" == *"nonconforming id BL-20260610"* ]]'
rm -f .context/backlog/2026-01-03-gamma.md

echo "== archive: a done item left in the active dir =="
item 2026-01-04-delta.md BL-002 done "closed but never archived"
OUT="$(bash "$TRIAGE" 2>&1)"; RC=$?
check "unarchived done item fires the archive check" '[[ "$OUT" == *"archive"*"_archive"* ]]'
check "and the fix is sweep --apply" '[[ "$OUT" == *"sweep.sh --apply"* ]]'
check "exits 1" '[[ $RC -eq 1 ]]'
check "the ids check still passes independently" '[[ "$OUT" == *"[ok]   ids"* ]]'

echo "== the report is per-check, not all-or-nothing =="
item 2026-01-05-epsilon.md BL-002 open "second BL-002"
OUT="$(bash "$TRIAGE" 2>&1)"
check "two failing checks are both listed" '[[ "$(grep -c "^  - " <<<"$OUT")" -eq 2 ]]'
check "the summary counts them" '[[ "$OUT" == *"2 of 4 checks"* ]]'

echo "== the definition contract is the fourth check =="
item 2026-01-06-zeta.md BL-003 open
sed -i.bak '/^verify:/d' .context/backlog/2026-01-06-zeta.md && rm -f .context/backlog/2026-01-06-zeta.md.bak
OUT="$(bash "$TRIAGE" 2>&1)"
check "an item below the contract fires the definition check" '[[ "$OUT" == *"[!]    definition"* ]]'
check "and the fix names define-item.sh" '[[ "$OUT" == *"define-item.sh"* ]]'
check "three of four" '[[ "$OUT" == *"3 of 4 checks"* ]]'

echo "== --quiet suppresses the per-check log, keeps the verdict =="
OUT="$(bash "$TRIAGE" --quiet 2>&1)"
check "--quiet drops the ok/warn lines" '[[ "$OUT" != *"[ok]"* ]]'
check "--quiet keeps the actionable summary" '[[ "$OUT" == *"checks found something actionable"* ]]'

echo
echo "triage: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
