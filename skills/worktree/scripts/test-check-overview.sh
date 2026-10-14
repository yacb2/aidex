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
# Run with: bash skills/worktree/scripts/test-check-overview.sh

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

# --- front matter pointing at the RETIRED plugin-less path fails, with a hint
#     (BL-627: owner projects kept the retired aidex-worktree skill path for weeks) ---
# split so test-plugin-layout.sh's ban on a literal plugin-skill path does not see it
retired="$(printf '%s/%s' '~/.claude/skills' 'aidex-worktree')"
write_doc "s|^worktree_up: .*|worktree_up: \"bash $retired/scripts/worktree.sh up <slug>\"|"
out="$(HOME="$TMP/nohome" bash "$SCRIPT" "$DOC" 2>&1)" && fail "retired front-matter path: should fail"
grep -q "front-matter: 'worktree_up' names a script that does not exist" <<<"$out" \
  || fail "retired front-matter path: failed for some other reason -- $out"
grep -q 'CLAUDE_PLUGIN_ROOT}/skills/worktree/scripts/' <<<"$out" \
  || fail "retired front-matter path: missing the plugin-path hint -- $out"

# --- the retired path is caught in EVERY spelling, not only the `~` one ------
# The extractor cannot start a match at `/` and stops at `{`, so a $-prefixed or
# absolute path came out as the relative tail `skills/<retired>/scripts/...`,
# which the basename fallback then resolved against the shipped skill: "OK".
for spelling in '${CLAUDE_PLUGIN_ROOT}/skills' '$HOME/.claude/skills' "$TMP/nohome/.claude/skills"; do
  write_doc "s|^worktree_up: .*|worktree_up: \"bash $spelling/aidex-worktree/scripts/worktree.sh up <slug>\"|"
  out="$(HOME="$TMP/nohome" bash "$SCRIPT" "$DOC" 2>&1)" && fail "retired path '$spelling': should fail"
  grep -q "retired path" <<<"$out" || fail "retired path '$spelling': failed for some other reason -- $out"
done

# --- front matter is the LEADING block only ---------------------------------
# worktree-multi reads it with an awk that stops at the first closing `---`; the
# sed range here reopened on every later pair of rules, so a `worktree_down` that
# lived in a body block passed the check and then teardown refused the doc.
write_doc '/^worktree_down:/d'
printf '\n---\nworktree_down: "worktree.sh down <slug>"\n---\n' >> "$DOC"
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "worktree_down only in a body block: should fail"
grep -q "missing 'worktree_down'" <<<"$out" || fail "worktree_down in a body block: failed for some other reason -- $out"

# --- a Procedure naming a nonexistent script fails; the usage log may name one ---
write_doc 's|worktree.sh new <slug> --branch <b>|_scripts/worktree-up.sh <slug> <slot>|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 && fail "Procedure naming a nonexistent script: should fail"
write_doc 's|historical entry, kept verbatim.|torn down with _scripts/worktree-down.sh alpha.|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "a usage-log entry naming a removed script is history and must pass"

# --- script resolution: front matter and Procedure resolve a script the same way ---
# Both name a script relative to the project, or by bare basename to the shipped
# skill; a missing one is a gap at each site, with each site's own message.
mkdir -p "$TMP/proj/_scripts"; : > "$TMP/proj/_scripts/up.sh"
write_doc 's|^worktree_up: .*|worktree_up: "_scripts/up.sh <slug>"|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "front matter naming a project-relative script that exists: should pass"
write_doc 's|^worktree_up: .*|worktree_up: "_scripts/gone.sh <slug>"|'
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "front matter naming a missing project-relative script: should fail"
grep -q "front-matter: 'worktree_up' names a script that does not exist: _scripts/gone.sh" <<<"$out" \
  || fail "front matter naming a missing script: failed for some other reason -- $out"
write_doc 's|worktree.sh new <slug> --branch <b>|_scripts/up.sh <slug>|'
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "Procedure naming a project-relative script that exists: should pass"
write_doc 's|worktree.sh new <slug> --branch <b>|_scripts/gone.sh <slug>|'
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "Procedure naming a missing project-relative script: should fail"
grep -q "## Procedure names a script that does not exist: _scripts/gone.sh" <<<"$out" \
  || fail "Procedure naming a missing script: failed for some other reason -- $out"

# --- worktree_down quoting: either YAML quote wraps the value (the consumer unwraps both) ---
write_doc "s|^worktree_down: .*|worktree_down: 'worktree.sh down <slug>'|"
bash "$SCRIPT" "$DOC" >/dev/null 2>&1 || fail "single-quoted worktree_down: should pass"
write_doc "s|^worktree_down: .*|worktree_down: ''|"
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "empty single-quoted worktree_down: should fail"
grep -q "'worktree_down' is empty" <<<"$out" || fail "empty single-quoted worktree_down: failed for some other reason -- $out"

# --- an unbalanced quote is not a value: the consumer's eval would die on it ---
write_doc "s|^worktree_down: .*|worktree_down: \"worktree.sh down <slug>|"
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "worktree_down with an opening quote only: should fail"
grep -q "'worktree_down' has an unbalanced quote" <<<"$out" || fail "unclosed worktree_down quote: failed for some other reason -- $out"
write_doc "s|^worktree_down: .*|worktree_down: \"|"
out="$(bash "$SCRIPT" "$DOC" 2>&1)" && fail "worktree_down of a lone quote: should fail"
grep -q "'worktree_down' is empty" <<<"$out" || fail "lone-quote worktree_down: failed for some other reason -- $out"
# A value that opens with a quoted word and goes on unquoted is valid shell, not unbalanced.
write_doc "s|^worktree_down: .*|worktree_down: \"worktree.sh\" down <slug> --branch <branch>|"
out="$(bash "$SCRIPT" "$DOC" 2>&1)"
grep -q "unbalanced" <<<"$out" && fail "quoted first word then args: wrongly reported unbalanced -- $out"

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
