#!/usr/bin/env bash
# test-check-overview.sh — exercises check-overview.sh against a temp .context
# fixture: a well-formed overview passes; each missing machine-consumed piece
# (worktree_up/down field, Procedure section, Usage log section) fails; a
# dangling backlog reference fails; a ref that resolves via _archive/_deferred
# passes.
#
# Run with: bash skills/aidex-worktree/scripts/test-check-overview.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/check-overview.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture: a .context/ tree with a backlog holding one active, one archived, and
# one deferred entry — so ref-resolution's positive path is really exercised.
CTX="$TMP/proj/.context"
mkdir -p "$CTX/worktrees" "$CTX/backlog/_archive" "$CTX/backlog/_deferred"
: > "$CTX/backlog/2026-07-01-active-item.md"
: > "$CTX/backlog/_archive/2026-06-01-archived-item.md"
: > "$CTX/backlog/_deferred/2026-06-15-deferred-item.md"

DOC="$CTX/worktrees/00-index.md"

# Writes a well-formed overview, then applies an optional sed mutation ($1).
write_doc() {
  cat > "$DOC" <<'EOF'
---
title: "Worktree procedure — proj"
status: doing
created: 2026-07-01
updated: 2026-07-01
version: 1.0.0
worktree_up: ""
worktree_down: ""
---

# Worktree procedure — proj

## Topology

Single repo.

## Participants & scope

Root repo only.

## Tier decision

Tier 1 unless it touches migrations/.

## Tier 2 infra strategy

Not yet available — see backlog/2026-07-01-active-item.md.

## Lifecycle & cleanup

Ephemeral. Also tracked under backlog/_archive/2026-06-01-archived-item.md
and backlog/_deferred/2026-06-15-deferred-item.md.

## Procedure

Tier 1 create: native EnterWorktree.

## Usage log

(none yet)

## Open questions

None.
EOF
  [[ -n "${1:-}" ]] && sed -i.bak "$1" "$DOC" && rm -f "$DOC.bak"
}

# --- good doc passes (including archived/deferred ref resolution) ---
write_doc ""
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "good doc: should pass"

# --- missing worktree_up field fails ---
write_doc '/^worktree_up:/d'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "missing worktree_up: should fail"

# --- missing worktree_down field fails ---
write_doc '/^worktree_down:/d'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "missing worktree_down: should fail"

# --- missing Procedure section fails ---
write_doc '/^## Procedure$/d'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "missing Procedure: should fail"

# --- missing Usage log section fails ---
write_doc '/^## Usage log$/d'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "missing Usage log: should fail"

# --- dangling backlog ref fails ---
write_doc 's|backlog/2026-07-01-active-item.md|backlog/2026-01-01-does-not-exist.md|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "dangling backlog ref: should fail"

# --- default-path invocation on a nonexistent doc fails cleanly ---
if bash "$SCRIPT" "$TMP/proj/.context/worktrees/nope.md" >/dev/null 2>&1; then
  fail "nonexistent doc: should fail cleanly"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — doc-shape check: good passes, each missing piece + dangling ref fails"
