#!/usr/bin/env bash
# test-renumber-ids.sh — renumber-ids.py makes the open queue conforming without
# disturbing _archive/_deferred, and rewrites citations of the codes it replaced
# without over-matching a longer code that shares a prefix.
#
# Isolated temp project, no network, no real .context/ touched.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REN="$SCRIPTS/renumber-ids.py"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .context/backlog/_archive .context/backlog/_deferred .context/plans

mk() { # <dir> <file> <id-line> <title>
  { printf -- '---\ntitle: "%s"\n' "$4"
    [[ -n "$3" ]] && printf 'id: %s\n' "$3"
    printf 'status: open\ncreated: 2026-06-01\nupdated: 2026-06-01\n---\n\nbody\n'
  } > ".context/backlog/$1/$2"
}
mk . 2026-06-01-alpha.md  BL-005          "Alpha"          # already fine, untouched
mk . 2026-06-02-bravo.md  BL-20260705     "Bravo"          # legacy, prefix of the next
mk . 2026-06-03-charlie.md BL-20260705-3  "Charlie"        # legacy, shares that prefix
mk . 2026-06-04-delta.md  ""              "Delta"          # no id at all
mk _archive  2026-05-01-old.md     BL-20260500 "Old archived"
mk _deferred 2026-05-02-blocked.md BL-20260501 "Blocked"

cat > .context/plans/2026-06-10-work.md <<'EOF'
---
title: "Work"
status: open
created: 2026-06-10
updated: 2026-06-10
---
- covers BL-20260705 and separately BL-20260705-3
- archived code must survive: BL-20260500
- deferred code must survive: BL-20260501
- not a code: BL-207050
EOF

echo "== dry-run writes nothing =="
SUM_BEFORE="$(cat .context/backlog/*.md .context/plans/*.md | shasum | awk '{print $1}')"
python3 "$REN" --root "$TMP" >/dev/null
check "dry-run changed nothing" \
  '[[ "$(cat .context/backlog/*.md .context/plans/*.md | shasum | awk "{print \$1}")" == "$SUM_BEFORE" ]]'

echo "== apply =="
python3 "$REN" --root "$TMP" --apply > "$TMP/out.txt" 2>&1

check "conforming item kept its id"  'grep -q "^id: BL-005$" .context/backlog/2026-06-01-alpha.md'
check "new ids allocated above the highest conforming (BL-005)" \
  '! grep -qE "^id: BL-00[0-5]$" .context/backlog/2026-06-02-bravo.md .context/backlog/2026-06-03-charlie.md .context/backlog/2026-06-04-delta.md'
check "legacy id replaced in bravo"  'grep -qE "^id: BL-0(06|07|08)$" .context/backlog/2026-06-02-bravo.md'
check "legacy id replaced in charlie" 'grep -qE "^id: BL-0(06|07|08)$" .context/backlog/2026-06-03-charlie.md'
check "id backfilled into delta"     'grep -qE "^id: BL-0(06|07|08)$" .context/backlog/2026-06-04-delta.md'
check "delta's id sits right after title" \
  '[[ "$(sed -n "3p" .context/backlog/2026-06-04-delta.md)" =~ ^id:\ BL-0 ]]'
check "all three new ids are distinct" \
  '[[ "$(grep -h "^id: BL-" .context/backlog/*.md | sort -u | wc -l | tr -d " ")" == "4" ]]'

echo "== _archive and _deferred untouched =="
check "archived legacy id survives" 'grep -q "^id: BL-20260500$" .context/backlog/_archive/2026-05-01-old.md'
check "deferred legacy id survives" 'grep -q "^id: BL-20260501$" .context/backlog/_deferred/2026-05-02-blocked.md'

echo "== citations =="
P=".context/plans/2026-06-10-work.md"
check "no replaced code lingers"      '! grep -qE "BL-20260705(-3)?\b" "$P"'
# Scoped to the one line that carried both codes: a project-wide `BL-[0-9]{3}` count
# would also match the first three digits of BL-20260500 and mis-report.
check "prefix code not over-matched — the -3 form got its own distinct id" \
  '[[ "$(grep "^- covers" "$P" | grep -oE "BL-[0-9]{3}" | sort -u | wc -l | tr -d " ")" == "2" ]]'
check "archived code left alone"      'grep -q "BL-20260500" "$P"'
check "deferred code left alone"      'grep -q "BL-20260501" "$P"'
check "unrelated near-miss untouched" 'grep -q "BL-207050" "$P"'

echo "== idempotent =="
python3 "$REN" --root "$TMP" > "$TMP/again.txt" 2>&1
check "second run finds nothing to do" 'grep -q "nothing to do" "$TMP/again.txt"'

echo "== backup restores =="
TAR="$(ls _tmp/renumber-ids-*.tar.gz | head -1)"
mkdir "$TMP/restore" && tar -xzf "$TAR" -C "$TMP/restore"
check "backup holds the pre-renumber ids" \
  'grep -q "^id: BL-20260705$" "$TMP/restore/.context/backlog/2026-06-02-bravo.md"'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
