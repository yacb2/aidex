#!/usr/bin/env bash
# test-check-overview.sh — exercises check-overview.sh against a temp .context
# fixture: a well-formed overview passes; each missing machine-consumed piece
# (worktree_up/down field, Procedure section, Usage log section, the
# Running-this-worktree and Never-run-here guides) fails; a dangling backlog
# reference fails; a ref that resolves via _archive/_deferred passes.
#
# The two guide cases assert the MESSAGE, not just the exit code: this checker
# has eleven ways to exit 1, so a status-only assertion passes on a failure that
# has nothing to do with the section it claims to cover.
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
# The Running-this-worktree table names ./test-e2e.sh. Deleting that heading
# merges the table into ## Procedure, whose scripts ARE checked -- so without
# this the negative case would fail with two gaps and the message assertion
# would be passing on a coincidence.
: > "$TMP/proj/test-e2e.sh"

DOC="$CTX/worktrees/00-index.md"

# Writes a well-formed overview, then applies an optional sed mutation ($1).
write_doc() {
  cat > "$DOC" <<'EOF'
---
title: "Worktree procedure — proj"
status: doing
created: 2026-07-01
updated: 2026-07-25
version: 2.0.0
worktree_up: "worktree.sh up <slug>"
worktree_down: "worktree.sh down <slug>"
---

# Worktree procedure — proj

## Topology

Single repo. Config lives in .context/worktrees/config.env.

## Participants & scope

Root repo only. Tracked under backlog/2026-07-01-active-item.md.

## Lifecycle & cleanup

Ephemeral. Also tracked under backlog/_archive/2026-06-01-archived-item.md
and backlog/_deferred/2026-06-15-deferred-item.md.

## Procedure

Create with worktree.sh new <slug> --branch <b>; verify with docker-snapshot.sh.

## Running this worktree

| I want to... | Command (from the worktree root) |
|---|---|
| bring the stack up | `worktree.sh up <slug>` — starts: db, backend |
| run the E2E suite | `./test-e2e.sh` |

Ports for this slot are in `<worktree>/.env`.

## Never run here

| Command | What it does to the MAIN tree |
|---|---|
| `nope.sh` | binds dev's port and kills whoever holds it |

## Usage log

- 2026-07-20 · slug `alpha` (Tier 2, slot 3) — historical entry, kept verbatim.

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

# --- missing '## Running this worktree' fails, and SAYS SO ---
write_doc '/^## Running this worktree$/d'
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "missing Running this worktree: should fail"
grep -q "missing '## Running this worktree'" <<<"$out" \
  || fail "missing Running this worktree: failed for some other reason -- $out"

# --- missing '## Never run here' fails, and SAYS SO ---
write_doc '/^## Never run here$/d'
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "missing Never run here: should fail"
grep -q "missing '## Never run here'" <<<"$out" \
  || fail "missing Never run here: failed for some other reason -- $out"

# --- an EMPTY worktree_up fails, because presence alone certified three
#     retired-mechanism docs as healthy ---
write_doc 's|^worktree_up: .*|worktree_up: ""|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "empty worktree_up: should fail (a field with no command runs nothing)"

# --- a tier SECTION fails; a tier mention in a usage-log ENTRY does not ---
write_doc 's|^## Topology$|## Tier decision|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "'## Tier decision' section: should fail (the mechanism is retired)"
write_doc ""
grep -q 'Tier 2, slot 3' "$DOC" || fail "fixture lost its historical tier mention — the next assertion proves nothing"
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "a usage-log entry naming a tier is HISTORY and must still pass"

# --- a Procedure naming a nonexistent script fails; the usage log may name one ---
write_doc 's|worktree.sh new <slug> --branch <b>|_scripts/worktree-up.sh <slug> <slot>|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "Procedure naming a nonexistent script: should fail"
write_doc 's|historical entry, kept verbatim.|torn down with _scripts/worktree-down.sh alpha.|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "a usage-log entry naming a removed script is history and must pass"

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
echo "OK — doc-shape check: good passes; missing/empty fields, missing guide sections, tier sections, dead Procedure scripts and dangling refs fail; history is left alone"
