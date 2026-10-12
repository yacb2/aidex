#!/usr/bin/env bash
# test-reconcile.sh — reconcile.sh reads the escalated_to / commits front-matter the way the
# writers store it. Each cell is a drift the script silently dropped (rows backlog-c11/c30/c31).
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

item() {  # item <dir> <file> <id> <status> <escalated_to> <commits>
  printf -- '---\ntitle: "t"\nid: %s\nstatus: %s\ncreated: 2026-01-01\nupdated: 2026-01-01\nescalated_to: "%s"\ncommits: %s\n---\n' \
    "$3" "$4" "$5" "$6" > "$1/$2"
}
plan() {  # plan <dir> <file> <status> [commits]
  printf -- '---\ntitle: "p"\nstatus: %s\ncreated: 2026-01-01\nupdated: 2026-01-01\ncommits: "%s"\n---\n' "$3" "${4:-}" > "$1/$2"
}
recon() { ( cd "$1" && NO_COLOR=1 bash "$SCRIPTS/reconcile.sh" 2>&1 ); }

echo "reconcile.sh:"
P="$TMP/a"; mkdir -p "$P/.context/backlog" "$P/.context/plans"
plan "$P/.context/plans" 2026-01-01-foo.md done abc1234
item "$P/.context/backlog" 2026-01-02-x.md BL-001 open "plan/2026-01-01-foo.md" '""'
OUT="$(recon "$P")"
[[ "$OUT" == *"BL-001"*"close it"* ]] && ok "c11: escalated_to with the .md extension resolves to its plan" || bad "c11: $OUT"

P="$TMP/b"; mkdir -p "$P/.context/backlog" "$P/.context/plans/_archive"
plan "$P/.context/plans/_archive" 2026-01-01-x.md done abc1234
item "$P/.context/backlog" 2026-01-02-m.md BL-002 doing "plan/2026-01-01-x, other_ws/BL-5" '""'
OUT="$(recon "$P")"
[[ "$OUT" == *"BL-002"*"close it"* ]] && ok "c31: a comma list is split and its plan ref resolves" || bad "c31: $OUT"
item "$P/.context/backlog" 2026-01-02-m.md BL-002 doing "plan/2026-01-01-x, plan/2026-01-09-live" '""'
plan "$P/.context/plans" 2026-01-09-live.md doing
OUT="$(recon "$P")"
[[ "$OUT" != *"close it"* ]] && ok "c31: one live plan in the list keeps the item off the close list" || bad "c31 live plan: $OUT"

P="$TMP/c"; mkdir -p "$P/.context/backlog" "$P/.context/plans"
item "$P/.context/backlog" 2026-01-02-e.md BL-003 done "" '[]'
item "$P/.context/backlog" 2026-01-02-f.md BL-004 done "" '""'
OUT="$(recon "$P")"
[[ "$OUT" == *"backlog: BL-003 2026-01-02-e.md"* ]] && ok "c30: commits: [] is no provenance" || bad "c30 []: $OUT"
[[ "$OUT" == *"BL-004"* ]] && ok "c30 control: commits: \"\" is reported" || bad "c30 control: $OUT"

P="$TMP/d"; mkdir -p "$P/.context/plans"
plan "$P/.context/plans" 2026-01-01-p.md done ""
OUT="$(recon "$P")"
[[ "$OUT" == *"plan: 2026-01-01-p.md"* ]] && ok "c30: a done plan without commits is reported when there is no backlog dir" || bad "c30 no backlog: $OUT"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — reconcile: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
