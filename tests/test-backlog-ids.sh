#!/usr/bin/env bash
# test-backlog-ids.sh — BL-NNN id assignment and duplicate detection in
# skills/aidex-backlog/scripts/register-item.sh, against a fixture .context/.
#
# Regression: two entries could carry the same id and nothing noticed. Observed
# in echo_lab 2026-07-22 — BL-186 and BL-193 were each on two items, weeks apart,
# found only by reading the files. --reindex now fails on it.
#
# Scenarios:
#   (a) clean backlog             -> --reindex exit 0, no duplicate warning
#   (b) duplicate id              -> --reindex exit 1, names id and both files
#   (c) duplicate across _archive -> caught too (scan covers active+archive+deferred)
#   (d) next id clears the max    -> new entry gets highest+1, not a reused number
#   (e) registration survives     -> a pre-existing duplicate warns but still writes
#
# Run with: bash tests/test-backlog-ids.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/skills/aidex-backlog/scripts/register-item.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P="$TMP/project"
B="$P/.context/backlog"

# Write a minimal but schema-shaped entry.
make_item() { # <path> <id> <title>
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<EOF
---
title: "$3"
id: $2
status: open
created: 2026-01-01
updated: 2026-01-01
origin: manual
origin_ref:
priority: P2
estimate: M
blocked_by: ""
escalated_to: ""
commits: ""
---

# $3
EOF
}

make_fixture() {
  rm -rf "$P"
  mkdir -p "$B/_archive" "$B/_deferred"
  make_item "$B/2026-01-01-alpha.md" "BL-001" "Alpha"
  make_item "$B/2026-01-02-beta.md" "BL-002" "Beta"
  make_item "$B/_archive/2026-01-03-gamma.md" "BL-003" "Gamma"
}

run_reindex() { (cd "$P" && NO_COLOR=1 bash "$SCRIPT" --reindex 2>&1); }

# ---------- (a) clean backlog ----------
make_fixture
out="$(run_reindex)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "(a) clean backlog: expected exit 0, got $rc"
echo "$out" | grep -qi "duplicate id" && fail "(a) clean backlog: reported a duplicate that does not exist"
[[ -f "$B/00-index.md" ]] || fail "(a) clean backlog: index not generated"

# ---------- (b) duplicate id among active entries ----------
make_fixture
make_item "$B/2026-01-04-delta.md" "BL-002" "Delta"
out="$(run_reindex)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(b) duplicate id: expected exit 1, got $rc"
echo "$out" | grep -q "duplicate id BL-002" || fail "(b) duplicate id: did not name the id"
echo "$out" | grep -q "2026-01-02-beta.md" || fail "(b) duplicate id: did not name the first file"
echo "$out" | grep -q "2026-01-04-delta.md" || fail "(b) duplicate id: did not name the second file"
[[ -f "$B/00-index.md" ]] || fail "(b) duplicate id: index should still be written"

# ---------- (c) duplicate spanning the archive ----------
make_fixture
make_item "$B/2026-01-05-epsilon.md" "BL-003" "Epsilon"
out="$(run_reindex)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(c) archive duplicate: expected exit 1, got $rc"
echo "$out" | grep -q "duplicate id BL-003" || fail "(c) archive duplicate: did not name the id"

# ---------- (d) next id clears the highest assigned, wherever it lives ----------
make_fixture
make_item "$B/_deferred/2026-01-06-zeta.md" "BL-009" "Zeta"
new="$( (cd "$P" && NO_COLOR=1 bash "$SCRIPT" --origin manual --title "Eta" 2>/dev/null) )"
[[ -f "$new" ]] || fail "(d) next id: no entry written"
got="$(grep -m1 '^id:' "$new" | awk '{print $2}')"
[[ "$got" == "BL-010" ]] || fail "(d) next id: expected BL-010 (max is BL-009 in _deferred), got '$got'"

# ---------- (e) a pre-existing duplicate must not abort a registration ----------
make_fixture
make_item "$B/2026-01-04-delta.md" "BL-002" "Delta"
new="$( (cd "$P" && NO_COLOR=1 bash "$SCRIPT" --origin manual --title "Theta" 2>/dev/null) )"; rc=$?
[[ "$rc" -eq 0 ]] || fail "(e) registration survives: expected exit 0, got $rc"
[[ -f "$new" ]] || fail "(e) registration survives: entry not written despite pre-existing duplicate"
err_out="$( (cd "$P" && NO_COLOR=1 bash "$SCRIPT" --origin manual --title "Iota" 2>&1 >/dev/null) )"
echo "$err_out" | grep -q "duplicate id BL-002" || fail "(e) registration survives: duplicate not warned about"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — ids are unique-by-construction; duplicates from hand-authored entries fail --reindex and warn on register"
