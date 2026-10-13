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
TAR="$(ls _tmp/backlog-rename-*.tar.gz | sed -n 1p)"
check "backup written to _tmp/" '[[ -n "$TAR" && -f "$TAR" ]]'
mkdir "$TMP/restore" && tar -xzf "$TAR" -C "$TMP/restore"
check "backup holds the pre-rename names" \
  '[[ -f "$TMP/restore/.context/backlog/2026-06-01-grid-selection-lost.md" ]]'

echo "== idempotent =="
python3 "$MIG" --root "$TMP" > "$TMP/again.txt" 2>&1
check "second run finds nothing to rename" 'grep -q "nothing to do" "$TMP/again.txt"'

# fresh project per case: <name> -> $TMP/<name>, cwd inside it
fresh() { rm -rf "$TMP/$1"; mkdir -p "$TMP/$1/.context/backlog/_archive" "$TMP/$1/.context/research"; cd "$TMP/$1"; }

echo "== c04: a name without a YYYY-MM-DD- prefix is skipped, never mangled =="
fresh c04
item . fix-login.md BL-010 "Fix login"
item . 2026-06-01-ok.md BL-011 "Ok"
python3 "$MIG" --root "$TMP/c04" --apply > "$TMP/c04.txt" 2>&1 || true
check "undated file kept its name" '[[ -f .context/backlog/fix-login.md ]]'
check "no extension-less mangled file" '[[ -z "$(find .context/backlog -maxdepth 1 -type f -not -name "*.md")" ]]'
check "skip reason names the date prefix" 'grep -q "YYYY-MM-DD" "$TMP/c04.txt"'
check "dated sibling still renamed" '[[ -f .context/backlog/2026-06-01-bl-011-ok.md ]]'

echo "== c21: a stem that prefixes another item's stem does not corrupt it =="
fresh c21
item . 2026-01-01-auth.md BL-020 "Auth"
item . 2026-01-01-auth-tokens.md BL-20260101 "Auth tokens (legacy id, stays)"
printf 'see 2026-01-01-auth-tokens.md and 2026-01-01-auth.md and [[2026-01-01-auth]] and backlog/2026-01-01-auth-report.html\n' > .context/research/2026-06-10-n.md
python3 "$MIG" --root "$TMP/c21" --apply > "$TMP/c21.txt" 2>&1 || true
N=.context/research/2026-06-10-n.md
check "longer stem reference untouched" 'grep -q "2026-01-01-auth-tokens.md" "$N" && ! grep -q "bl-020-auth-tokens" "$N"'
check "html sibling ref untouched" 'grep -q "backlog/2026-01-01-auth-report.html" "$N"'
check "exact stem reference rewritten" 'grep -q "2026-01-01-bl-020-auth.md and \[\[2026-01-01-bl-020-auth\]\]" "$N"'

echo "== c34: a failing git log aborts instead of disabling the commit-citation guard =="
fresh c34
item . 2026-06-01-cited.md BL-030 "Cited"
mkdir .git "$TMP/fakebin"
printf '#!/bin/sh\nexit 128\n' > "$TMP/fakebin/git"; chmod +x "$TMP/fakebin/git"
rc=0; PATH="$TMP/fakebin:$PATH" python3 "$MIG" --root "$TMP/c34" --apply > "$TMP/c34.txt" 2>&1 || rc=$?
check "exits nonzero" '[[ $rc -ne 0 ]]'
check "item not renamed" '[[ -f .context/backlog/2026-06-01-cited.md ]]'
check "message names the failed git log" 'grep -q "git log failed" "$TMP/c34.txt"'
check "nothing reported renamed" '! grep -Eq "^renamed [0-9]+ file" "$TMP/c34.txt"'

echo "== c34: a broken direct-child code repo (depth 1) aborts too =="
fresh c34c
item . 2026-06-01-cited.md BL-032 "Cited"
G="git -c user.name=t -c user.email=t@t"
git init -q . && $G commit -q --allow-empty -m root
mkdir backend && git init -q backend && $G -C backend commit -q --allow-empty -m "fix per 2026-06-01-cited"
echo 0123456789012345678901234567890123456789 > "backend/.git/refs/heads/$(git -C backend symbolic-ref --short HEAD)"
rc=0; python3 "$MIG" --root "$TMP/c34c" --apply > "$TMP/c34c.txt" 2>&1 || rc=$?
check "child repo failure: exits nonzero" '[[ $rc -ne 0 ]]'
check "child repo failure: cited item not renamed" '[[ -f .context/backlog/2026-06-01-cited.md ]]'

echo "== c34: a failing NESTED repo (vendored checkout) warns and continues =="
fresh c34n
item . 2026-06-01-clean.md BL-031 "Clean"
mkdir -p _archive/vendor/x/.git "$TMP/fakebin2"
# fails only for the vendored path; the root has no .git of its own here
printf '#!/bin/sh\ncase "$2" in *vendor*) exit 128;; esac\nexit 0\n' > "$TMP/fakebin2/git"; chmod +x "$TMP/fakebin2/git"
rc=0; PATH="$TMP/fakebin2:$PATH" python3 "$MIG" --root "$TMP/c34n" --apply > "$TMP/c34n.txt" 2>&1 || rc=$?
check "nested failure: item renamed" '[[ -f .context/backlog/2026-06-01-bl-031-clean.md ]]'
check "nested failure: warning names the nested repo" 'grep -q "warning: git log failed in .*vendor" "$TMP/c34n.txt"'

echo "== c03: a BL-1000+ id is conforming =="
fresh c03
item . 2026-06-01-big.md BL-1000 "Big"
python3 "$MIG" --root "$TMP/c03" --apply > "$TMP/c03.txt" 2>&1 || true
check "BL-1000 item renamed" '[[ -f .context/backlog/2026-06-01-bl-1000-big.md ]]'


printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
