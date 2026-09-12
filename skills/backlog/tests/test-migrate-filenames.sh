#!/usr/bin/env bash
# test-migrate-filenames.sh — migrate-filenames.py renames the active queue and
# rewrites every inbound reference shape in one pass, leaves _archive/_deferred
# alone, and refuses the items it cannot rename safely.
#
# Isolated temp project, no network, no real .context/ touched.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
MIG="$SCRIPTS/migrate-filenames.py"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
mkdir -p .context/backlog/_archive .context/backlog/_deferred .context/research .context/decisions

item() { # <dir> <file> <id> <title>
  printf -- '---\ntitle: "%s"\nid: %s\nstatus: open\ncreated: 2026-06-01\nupdated: 2026-06-01\n---\n\nbody\n' \
    "$4" "$3" > ".context/backlog/$1/$2"
}
item . 2026-06-01-grid-selection-lost.md BL-001 "Grid selection lost"
item . 2026-06-02-export-drops-rows.md   BL-002 "Export drops rows"
item . 2026-06-03-no-id-here.md          ""     "No id here"
sed -i '' '/^id: $/d' .context/backlog/2026-06-03-no-id-here.md
item . 2026-06-04-legacy-shaped.md       BL-20260604 "Legacy shaped"
item _archive  2026-05-01-old-closed.md   BL-900 "Old closed"
item _deferred 2026-05-02-blocked-one.md  BL-901 "Blocked one"

# every inbound reference shape we measured in the field
cat > .context/research/2026-06-10-notes.md <<'EOF'
---
title: "Notes"
status: open
created: 2026-06-10
updated: 2026-06-10
origin_ref: backlog/2026-06-01-grid-selection-lost.md
---
- markdown link: [grid](../backlog/2026-06-01-grid-selection-lost.md)
- extension-less: backlog/2026-06-02-export-drops-rows
- wiki link: [[2026-06-02-export-drops-rows]]
- bare prose mention of `2026-06-01-grid-selection-lost.md` inline
- archived, must NOT move: backlog/_archive/2026-05-01-old-closed.md
EOF
printf 'cross-ref-format-invalid | .context/backlog/2026-06-01-grid-selection-lost.md | - | reason\n' \
  > .context/.aidex-waivers

echo "== dry-run writes nothing =="
BEFORE="$(ls .context/backlog)"
python3 "$MIG" --root "$TMP" >/dev/null
check "dry-run left the queue untouched" '[[ "$(ls .context/backlog)" == "$BEFORE" ]]'

echo "== apply =="
python3 "$MIG" --root "$TMP" --apply > "$TMP/out.txt" 2>&1 || true
check "renamed the conforming items" \
  '[[ -f ".context/backlog/2026-06-01-bl-001-grid-selection-lost.md" && -f ".context/backlog/2026-06-02-bl-002-export-drops-rows.md" ]]'
check "left the id-less item alone" '[[ -f ".context/backlog/2026-06-03-no-id-here.md" ]]'
check "left the legacy-id item alone" '[[ -f ".context/backlog/2026-06-04-legacy-shaped.md" ]]'
check "never touched _archive" '[[ -f ".context/backlog/_archive/2026-05-01-old-closed.md" ]]'
check "never touched _deferred" '[[ -f ".context/backlog/_deferred/2026-05-02-blocked-one.md" ]]'
check "reported both skips with a reason" 'grep -q "not BL-NNN" "$TMP/out.txt"'

echo "== every reference shape followed the rename =="
R=".context/research/2026-06-10-notes.md"
check "front-matter cross-ref"  'grep -q "^origin_ref: backlog/2026-06-01-bl-001-grid-selection-lost.md$" "$R"'
check "markdown link"           'grep -q "(../backlog/2026-06-01-bl-001-grid-selection-lost.md)" "$R"'
check "extension-less ref"      'grep -q "backlog/2026-06-02-bl-002-export-drops-rows$" "$R"'
check "wiki link"               'grep -q "\[\[2026-06-02-bl-002-export-drops-rows\]\]" "$R"'
check "bare prose mention"      'grep -q "\`2026-06-01-bl-001-grid-selection-lost.md\`" "$R"'
check "archived ref untouched"  'grep -q "backlog/_archive/2026-05-01-old-closed.md" "$R"'
check "waiver path rewritten"   'grep -q "2026-06-01-bl-001-grid-selection-lost.md" .context/.aidex-waivers'
check "dangling count unchanged" 'grep -q "unchanged — OK" "$TMP/out.txt"'

echo "== backup is restorable =="
TAR="$(ls _tmp/backlog-rename-*.tar.gz | head -1)"
check "backup written to _tmp/" '[[ -n "$TAR" && -f "$TAR" ]]'
mkdir "$TMP/restore" && tar -xzf "$TAR" -C "$TMP/restore"
check "backup holds the pre-rename names" \
  '[[ -f "$TMP/restore/.context/backlog/2026-06-01-grid-selection-lost.md" ]]'

echo "== idempotent =="
python3 "$MIG" --root "$TMP" > "$TMP/again.txt" 2>&1
check "second run finds nothing to rename" 'grep -q "nothing to do" "$TMP/again.txt"'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
