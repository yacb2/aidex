#!/usr/bin/env bash
# test-filename-id.sh — the backlog filename carries the stable id:
# `YYYY-MM-DD-bl-nnn-<slug>.md`. Covers both filename construction sites in
# register-item.sh (the main registration path and emit_backlog_stub, which
# --escalate-to uses on BOTH sides), plus the max-id computation that has to
# ignore nonconforming legacy ids for any of it to hold.
#
# Isolated temp projects, no network, no real .context/ touched.

set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TODAY="$(date +%Y-%m-%d)"

echo "== main registration path =="
mkdir -p "$TMP/src/.context/backlog"
cd "$TMP/src"
NEW="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "Widget grid drops selection" --priority P2 2>/dev/null)"
BASE="$(basename "$NEW")"
check "filename is <date>-bl-nnn-<slug>.md" '[[ "$BASE" == "$TODAY-bl-001-widget-grid-drops-selection.md" ]]'
check "front-matter id matches the filename segment" 'grep -q "^id: BL-001$" "$NEW"'

# The id makes the name unique, so a same-title same-day item must not need the
# old `-2` collision suffix.
SECOND="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "Widget grid drops selection" --priority P2 2>/dev/null)"
check "same title same day gets a distinct name from the id, not a -2 suffix" \
  '[[ "$(basename "$SECOND")" == "$TODAY-bl-002-widget-grid-drops-selection.md" ]]'

echo "== emit_backlog_stub via --escalate-to (both repos) =="
mkdir -p "$TMP/tgt/.context/backlog"
bash "$SCRIPTS/register-item.sh" --escalate-to "$TMP/tgt" \
  --title "Host the shared parser" --priority P2 --type improvement >/dev/null 2>&1
SRC_STUB="$(ls "$TMP/src/.context/backlog"/*host-the-shared-parser*.md 2>/dev/null | head -1)"
TGT_STUB="$(ls "$TMP/tgt/.context/backlog"/*host-the-shared-parser*.md 2>/dev/null | head -1)"
check "source stub uses the new shape" \
  '[[ -n "$SRC_STUB" && "$(basename "$SRC_STUB")" == "$TODAY-bl-003-host-the-shared-parser.md" ]]'
check "cross-repo counterpart uses the new shape too" \
  '[[ -n "$TGT_STUB" && "$(basename "$TGT_STUB")" == "$TODAY-bl-001-host-the-shared-parser.md" ]]'

echo "== next id ignores nonconforming legacy ids =="
mkdir -p "$TMP/legacy/.context/backlog/_archive"
cd "$TMP/legacy"
printf -- '---\ntitle: "old one"\nid: BL-20260569\nstatus: done\ncreated: 2026-07-03\nupdated: 2026-07-03\n---\n' \
  > ".context/backlog/_archive/2026-07-03-old-one.md"
printf -- '---\ntitle: "recent"\nid: BL-007\nstatus: open\ncreated: 2026-08-01\nupdated: 2026-08-01\n---\n' \
  > ".context/backlog/2026-08-01-recent.md"
LEG="$(bash "$SCRIPTS/register-item.sh" --origin manual --title "After legacy" --priority P3 2>/dev/null)"
check "next id is BL-008, not BL-20260570" 'grep -q "^id: BL-008$" "$LEG"'
check "and the filename carries it" '[[ "$(basename "$LEG")" == "$TODAY-bl-008-after-legacy.md" ]]'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
