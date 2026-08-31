#!/usr/bin/env bash
# test-memory-sweep.sh — the memory-hygiene checker, tested against inputs that violate it.
#
# The 2026-07-25 suite audit found 3 of 4 gate scripts returning SUCCESS on contract-violating
# input, because every test asserted the happy shape. So this one asserts the unhappy ones:
# each MEM-* rule gets a fixture that must trip it, plus a clean tree that must not.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SWEEP="$REPO_ROOT/skills/aidex/scripts/memory-sweep.py"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export AIDEX_MEMORY_ROOT="$TMP"

mem() { mkdir -p "$TMP/$1/memory"; printf '%s' "$3" > "$TMP/$1/memory/$2"; }
typed_body() { printf -- '---\nname: x\nmetadata:\n  type: %s\n---\n\n%s\n' "$1" "$2"; }
filler() { python3 -c "import sys; print(' '.join(['word']*int(sys.argv[1])))" "$1"; }

echo "== clean tree =="
mem clean-proj a.md "$(typed_body project "one durable fact")"
mem clean-proj MEMORY.md "- [a](a.md) — hook"
OUT="$(python3 "$SWEEP" 2>&1)"; RC=$?
check "clean tree exits 0" '[[ $RC -eq 0 ]]'
check "clean tree says so" '[[ "$OUT" == *"clean"* ]]'

echo "== MEM-LOG: a memory over the word budget =="
mem log-proj big.md "$(typed_body project "$(filler 900)")"
OUT="$(python3 "$SWEEP" 2>&1)"; RC=$?
check "oversize memory is reported" '[[ "$OUT" == *"MEM-LOG"* && "$OUT" == *"big.md"* ]]'
check "any finding exits 1" '[[ $RC -eq 1 ]]'
# The boundary matters: 800 is the budget, so exactly-800 must NOT trip it.
rm -rf "${TMP:?}/log-proj"
mem edge-proj edge.md "$(printf -- '---\nname: x\nmetadata:\n  type: project\n---\n%s\n' "$(filler 793)")"
EDGE_WORDS="$(wc -w < "$TMP/edge-proj/memory/edge.md" | tr -d ' ')"
OUT="$(python3 "$SWEEP" 2>&1)"
check "a memory exactly at the budget ($EDGE_WORDS w) is not flagged" '[[ "$EDGE_WORDS" -eq 800 && "$OUT" != *"MEM-LOG"* ]]'
rm -rf "${TMP:?}/edge-proj"

echo "== MEM-TYPE: no type: front-matter =="
mem type-proj untyped.md "$(printf -- '---\nname: x\n---\n\nfact\n')"
OUT="$(python3 "$SWEEP" 2>&1)"
check "untyped memory is reported" '[[ "$OUT" == *"MEM-TYPE"* && "$OUT" == *"untyped.md"* ]]'
rm -rf "${TMP:?}/type-proj"

echo "== MEM-INDEX: always-on index over budget =="
mem index-proj MEMORY.md "$(filler 1300)"
mem index-proj a.md "$(typed_body project fact)"
OUT="$(python3 "$SWEEP" 2>&1)"
check "oversize index is reported" '[[ "$OUT" == *"MEM-INDEX"* ]]'
# MEMORY.md is the index, never a memory — it must not also trip the per-file budget.
check "the index is not counted as a memory" '[[ "$OUT" != *"MEM-LOG"* ]]'
check "the index is not counted in the memory total" '[[ "$OUT" == *"2 memories"* ]]'
rm -rf "${TMP:?}/index-proj"

echo "== MEM-TMP: memory under a throwaway project path =="
mem -private-tmp-scratch a.md "$(typed_body project fact)"
OUT="$(python3 "$SWEEP" 2>&1)"
check "throwaway project dir is reported" '[[ "$OUT" == *"MEM-TMP"* ]]'
check "and the fix is a concrete command" '[[ "$OUT" == *"rm -rf"* ]]'
rm -rf "${TMP:?}/-private-tmp-scratch"

echo "== MEM-DUP: byte-identical memory directories =="
mem dup-a a.md "$(typed_body project "same bytes")"
mem dup-b a.md "$(typed_body project "same bytes")"
OUT="$(python3 "$SWEEP" 2>&1)"
check "identical dirs are reported once as a group" '[[ "$(grep -c "MEM-DUP" <<<"$OUT")" -eq 1 ]]'
check "the group names both projects" '[[ "$OUT" == *"dup-a"* && "$OUT" == *"dup-b"* ]]'
# Two dirs that merely share a filename are NOT duplicates.
printf '%s' "$(typed_body project "different bytes")" > "$TMP/dup-b/memory/a.md"
OUT="$(python3 "$SWEEP" 2>&1)"
check "different content is not a duplicate" '[[ "$OUT" != *"MEM-DUP"* ]]'
rm -rf "${TMP:?}/dup-a" "${TMP:?}/dup-b"

echo "== read-only: the sweep never mutates =="
mem ro-proj big.md "$(typed_body project "$(filler 900)")"
BEFORE="$(find "$TMP" -type f -exec shasum {} \; | shasum)"
python3 "$SWEEP" >/dev/null 2>&1
AFTER="$(find "$TMP" -type f -exec shasum {} \; | shasum)"
check "reporting findings changed nothing on disk" '[[ "$BEFORE" == "$AFTER" ]]'

echo "== budgets stay in lockstep with the rule =="
RULE="$REPO_ROOT/rules/memory-hygiene.md"
SCRIPT_MEM="$(sed -n 's/^MEMORY_WORD_BUDGET = \([0-9]*\)$/\1/p' "$SWEEP")"
SCRIPT_IDX="$(sed -n 's/^INDEX_WORD_BUDGET = \([0-9]*\)$/\1/p' "$SWEEP")"
check "the rule states the memory budget ($SCRIPT_MEM)" 'grep -q "\*\*$SCRIPT_MEM words" "$RULE"'
check "the rule states the index budget ($SCRIPT_IDX)" 'grep -q "under 1,200 words" "$RULE" && [[ "$SCRIPT_IDX" -eq 1200 ]]'
check "the rule names the sweep so it is reachable" 'grep -q "memory-sweep.py" "$RULE"'

echo "== --reindex: a deleted memory must not leave a live-looking index line =="
# A cleanup deletes memory FILES and nothing touches MEMORY.md, so every deletion leaves
# a dead line that reads exactly like a live fact, at full always-on cost, forever.
rm -rf "${TMP:?}"/*
mem ri-proj a.md "$(typed_body project "a durable fact")"
mem ri-proj b.md "$(typed_body project "another durable fact")"
printf -- '- [A](a.md) - hook\n- [B](b.md) - hook\n- [Gone](gone.md) - hook\n' > "$TMP/ri-proj/memory/MEMORY.md"
OUT="$(python3 "$SWEEP" --reindex --dry-run --project=ri-proj 2>&1)"
check "dry run reports the dead line" '[[ "$OUT" == *"would drop 1 dead line"* ]]'
check "dry run changes nothing"       'grep -q "gone.md" "$TMP/ri-proj/memory/MEMORY.md"'
OUT="$(python3 "$SWEEP" --reindex --project=ri-proj 2>&1)"
check "the dead line is gone"         '! grep -q "gone.md" "$TMP/ri-proj/memory/MEMORY.md"'
check "the live lines survive"        '[[ $(grep -c "^- \\[" "$TMP/ri-proj/memory/MEMORY.md") -eq 2 ]]'
# An unlinked memory is REPORTED, never deleted: the index is the cheap thing to rebuild.
printf -- '---\nname: c\nmetadata:\n  type: project\n---\n\nunlinked\n' > "$TMP/ri-proj/memory/c.md"
OUT="$(python3 "$SWEEP" --reindex --project=ri-proj 2>&1)"
check "an unlinked memory is reported" '[[ "$OUT" == *"1 unlinked: c.md"* ]]'
check "and is not deleted"             '[[ -f "$TMP/ri-proj/memory/c.md" ]]'

echo
echo "memory-sweep: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
