#!/usr/bin/env bash
# test-memory-worklist.sh — the work-list generator and, above all, --verify-applied.
#
# --verify-applied is the sole verification for ~250 deletions and ~130 destination
# writes across three phases. A version that vacuously returns 0 would let all three
# pass green having done nothing, so the vacuity case is asserted here, not only the
# teeth. The corpus is synthetic: this repo is public and the real audit inputs carry
# client project names (ledger d5).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
GEN="$REPO_ROOT/skills/aidex/scripts/build-memory-worklist.py"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAKE_REPO="$TMP/repo"
RUN="$FAKE_REPO/_tmp/memory-audit-2099-01-01"
WL="$FAKE_REPO/.context/worklists/2099-01-01-memory-cleanup.md"
mkdir -p "$RUN" "$FAKE_REPO/.context/worklists"

export AIDEX_MEMORY_ROOT="$TMP/projects"
export AIDEX_BACKUP_ROOT="$TMP/backups"

mem() { mkdir -p "$AIDEX_MEMORY_ROOT/$1/memory"; printf -- '---\nname: x\nmetadata:\n  type: project\n---\n\n%s\n' "$3" > "$AIDEX_MEMORY_ROOT/$1/memory/$2"; }

gen() { python3 "$GEN" --run 2099-01-01 --repo "$FAKE_REPO" "$@"; }

cat > "$RUN/alpha.md" <<'EOF'
# -tmp-alpha  ·  project path: /tmp/alpha  ·  3 memories  ·  index 40w
## Verdicts
| file | type | words | verdict | destination / other file | reason |
|---|---|---|---|---|---|
| a_keep.md | project | 40 | KEEP | — | durable |
| a_dup.md | project | 40 | DELETE-DUP | CLAUDE.md | already there |
| a_move.md | project | 40 | MOVE-REFERENCE | .context/references/x/ | how it works |
## Index
DEAD: none
## Patterns
- nothing
EOF

# The two shapes that silently lost rows in the real run: a compound verdict the
# rubric forbids, and a header naming several directories at once.
cat > "$RUN/beta.md" <<'EOF'
# Small projects roll-up
Prose, no table.

# -tmp-beta  ·  project path: /tmp/beta  ·  2 memories  ·  index 20w
## Verdicts
| file | type | words | verdict | destination / other file | reason |
|---|---|---|---|---|---|
| b_ok.md | project | 20 | DELETE-CLOSED | — | shipped |
| b_compound.md | project | 20 | REWRITE + MOVE-BACKLOG | both | auditor gave two |
## Index
DEAD: none

# -tmp-gamma / -tmp-delta  ·  1 memory each  ·  index 10w
## Verdicts (apply to the surviving copy)
| file | type | words | verdict | destination / other file | reason |
|---|---|---|---|---|---|
| g_dup.md | project | 10 | DELETE-DUP | elsewhere | same file in two dirs |
## Patterns
- none

# Roll-up
| slug | memories | index | verdict |
|---|---|---|---|
| -tmp-alpha | 3 | 40w | REWRITE |
EOF

echo "== parse =="
OUT="$(gen 2>&1)"
check "parses the executable rows"      '[[ "$OUT" == *"4 executable rows"* ]]'
check "compound + multi-slug are unplaceable" '[[ "$OUT" == *"2 unplaceable"* ]]'
check "a compound verdict is never executed"  '! grep -q "b_compound.md | REWRITE" "$WL"'
check "compound row is reported instead" 'grep -q "b_compound.md.*REWRITE + MOVE-BACKLOG" "$WL"'
check "multi-slug row is reported"       'grep -q "g_dup.md.*ambiguous slug" "$WL"'
check "the Roll-up summary table is not a verdict source" '! grep -q "| \`-tmp-alpha\` | \`-tmp-alpha\`" "$WL"'
check "counts row totals"                'grep -q "| \*\*TOTAL\*\* | 1 | 0 | 1 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 4 |" "$WL"'

echo "== --check =="
gen --check >/dev/null 2>&1; check "--check is 0 on an unchanged file" '[[ $? -eq 0 ]]'
printf '\nhand edit\n' >> "$WL"
gen --check >/dev/null 2>&1; check "--check is 1 after a hand edit" '[[ $? -eq 1 ]]'
gen >/dev/null 2>&1

echo "== --verify-applied refuses without ratification =="
mem -tmp-alpha a_keep.md "keep"
mem -tmp-alpha a_dup.md "dup"
mem -tmp-alpha a_move.md "move"
mem -tmp-beta b_ok.md "closed"
OUT="$(gen --verify-applied 2>&1)"; RC=$?
check "no stamp: exit 2"       '[[ $RC -eq 2 ]]'
check "no stamp: says why"     '[[ "$OUT" == *"no \`ratified:\` stamp"* ]]'

echo "== ratification survives regeneration =="
gen --ratify 2099-01-01 >/dev/null
check "stamp is written"       'grep -q "^ratified: 2099-01-01" "$WL"'
gen --check >/dev/null 2>&1;   check "--check still 0 after ratify" '[[ $? -eq 0 ]]'

echo "== --verify-applied has teeth =="
OUT="$(gen --verify-applied 2>&1)"; RC=$?
check "nothing applied yet: exit 1" '[[ $RC -eq 1 ]]'
check "names the unapplied rows"    '[[ "$OUT" == *"a_dup.md"* && "$OUT" == *"still on disk"* ]]'

echo "== backup, then a demonstrated restore =="
OUT="$(gen --backup 2>&1)"
check "backup copies the non-KEEP files + indexes" '[[ "$OUT" == *"backup: "* ]]'
check "a KEEP file is not backed up"  '[[ ! -f "$AIDEX_BACKUP_ROOT/2099-01-01/-tmp-alpha/a_keep.md" ]]'
check "a DELETE file is backed up"    '[[ -f "$AIDEX_BACKUP_ROOT/2099-01-01/-tmp-alpha/a_dup.md" ]]'
OUT="$(gen --verify-backup 2>&1)"; RC=$?
check "restore is demonstrated, not assumed" '[[ $RC -eq 0 && "$OUT" == *"restore verified"* ]]'
printf 'corrupted\n' > "$AIDEX_BACKUP_ROOT/2099-01-01/-tmp-alpha/a_dup.md"
python3 - "$AIDEX_BACKUP_ROOT/2099-01-01/MANIFEST.tsv" <<'PY'
import sys
p=sys.argv[1]
rows=[l for l in open(p).read().splitlines() if l.strip()]
open(p,"w").write(rows[0]+"\n"+[r for r in rows[1:] if "a_dup.md" in r][0]+"\n")
PY
gen --verify-backup >/dev/null 2>&1; check "a corrupted backup fails the restore" '[[ $? -eq 1 ]]'
gen --backup >/dev/null 2>&1

echo "== all rows applied =="
rm -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_dup.md" \
      "$AIDEX_MEMORY_ROOT/-tmp-beta/memory/b_ok.md"
printf 'the fact, restated where it belongs\n' > "$TMP/early-dest.md"
gen --record-move="-tmp-alpha|a_move.md|$TMP/early-dest.md" >/dev/null 2>&1
OUT="$(gen --verify-applied 2>&1)"; RC=$?
check "all applied: exit 0" '[[ $RC -eq 0 ]]'
# A KEEP row that vanished is as wrong as a DELETE row that stayed.
rm -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_keep.md"
gen --verify-applied >/dev/null 2>&1; check "a deleted KEEP row fails too" '[[ $? -eq 1 ]]'
mem -tmp-alpha a_keep.md "keep"

echo "== --project scoping =="
gen --verify-applied --project=-tmp-beta >/dev/null 2>&1
check "scoped to an applied project: 0" '[[ $? -eq 0 ]]'
gen --verify-applied --project=-tmp-nope >/dev/null 2>&1
check "an unknown slug is an error, not a pass" '[[ $? -eq 2 ]]'

echo "== vacuity: zero parsed rows must never read as success =="
python3 - "$WL" <<'PY'
import sys, re
p = sys.argv[1]
t = open(p).read()
t = re.sub(r"## Files\n.*?(?=\n## )", "## Files\n\n(table removed)\n\n", t, flags=re.S)
open(p, "w").write(t)
PY
OUT="$(gen --verify-applied 2>&1)"; RC=$?
check "zero rows: exit 2"    '[[ $RC -eq 2 ]]'
check "zero rows: says vacuous" '[[ "$OUT" == *"vacuous"* ]]'

echo "== --apply-deletes: the refusals come before the unlink =="
# The vacuity case above gutted the work-list's Files table; regenerate it, or every
# assertion below would pass on a table with no rows in it.
gen --ratify 2099-01-01 >/dev/null
# Rebuild the fixture: the applied-state tests above deleted the sources.
mem -tmp-alpha a_dup.md "dup"
mem -tmp-alpha a_move.md "move"
mem -tmp-beta b_ok.md "closed"
gen --backup >/dev/null 2>&1

OUT="$(gen --apply-deletes 2>&1)"; RC=$?
check "unscoped delete is refused"  '[[ $RC -eq 2 && "$OUT" == *"requires --project"* ]]'
check "the unscoped refusal did not delete" '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_dup.md" ]]'

MANSAVE="$TMP/man.save"; cp "$AIDEX_BACKUP_ROOT/2099-01-01/MANIFEST.tsv" "$MANSAVE"
mv "$AIDEX_BACKUP_ROOT/2099-01-01/MANIFEST.tsv" "$TMP/hidden.tsv"
OUT="$(gen --apply-deletes --tier a 2>&1)"; RC=$?
check "no manifest: refused"  '[[ $RC -eq 2 && "$OUT" == *"no backup manifest"* ]]'
check "no manifest: nothing deleted" '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_dup.md" ]]'
mv "$TMP/hidden.tsv" "$AIDEX_BACKUP_ROOT/2099-01-01/MANIFEST.tsv"

# A memory edited since the backup was taken has no valid reversal path.
printf 'edited after the backup
' >> "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_dup.md"
OUT="$(gen --apply-deletes --project=-tmp-alpha 2>&1)"; RC=$?
check "changed-since-backup is refused, not deleted"       '[[ "$OUT" == *"changed since the backup"* && -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_dup.md" ]]'
check "a refusal is a non-zero exit" '[[ $RC -ne 0 ]]'
gen --backup >/dev/null 2>&1

echo "== --apply-deletes: what it does delete =="
OUT="$(gen --apply-deletes --project=-tmp-alpha 2>&1)"; RC=$?
check "deletes the DELETE row"        '[[ ! -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_dup.md" ]]'
check "leaves the MOVE row alone"     '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_move.md" ]]'
check "leaves the KEEP row alone"     '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_keep.md" ]]'
check "does not cross into another project" '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-beta/memory/b_ok.md" ]]'
check "reports the surviving count by enumeration" '[[ "$OUT" == *"files remain"* ]]'
check "clean delete exits 0"          '[[ $RC -eq 0 ]]'

echo "== --dry-run touches nothing =="
gen --backup >/dev/null 2>&1
OUT="$(gen --apply-deletes --project=-tmp-beta --dry-run 2>&1)"
check "dry run says would unlink"  '[[ "$OUT" == *"would unlink"* ]]'
check "dry run deleted nothing"    '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-beta/memory/b_ok.md" ]]'

echo "== MOVE rows: the destination is proved before the source is unlinked =="
# The bug this whole section exists for: MOVE-* is not in SURVIVES, so "source is
# gone" was the entire assertion — a MOVE whose destination was never written passed
# green, and MOVE is the majority of the work in Phases 6-8.
mem -tmp-alpha a_move.md "the fact"
gen --backup >/dev/null 2>&1
LED="$FAKE_REPO/.context/worklists/2099-01-01-memory-cleanup-applied.tsv"
DEST="$TMP/dest.md"

OUT="$(gen --record-move="-tmp-alpha|a_move.md|$DEST" 2>&1)"; RC=$?
check "a missing destination is refused" '[[ $RC -eq 2 && "$OUT" == *"does not exist or is empty"* ]]'
check "the source survives that refusal"  '[[ -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_move.md" ]]'
: > "$DEST"
gen --record-move="-tmp-alpha|a_move.md|$DEST" >/dev/null 2>&1
check "an EMPTY destination is refused too" '[[ $? -eq 2 && -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_move.md" ]]'

printf 'the fact, restated where it belongs
' > "$DEST"
OUT="$(gen --record-move="-tmp-alpha|a_dup.md|$DEST" 2>&1)"
check "a DELETE row is not a MOVE"     '[[ "$OUT" == *"not a MOVE"* ]]'
OUT="$(gen --record-move="-tmp-alpha|nosuch.md|$DEST" 2>&1)"
check "a row outside the work-list is refused" '[[ "$OUT" == *"not a row in the ratified"* ]]'

OUT="$(gen --record-move="-tmp-alpha|a_move.md|$DEST" 2>&1)"; RC=$?
check "a real move succeeds"           '[[ $RC -eq 0 ]]'
# Every memory slug starts with `-`. A positional slug is read by argparse as a flag,
# which is how the first draft of this interface failed on all 29 of its first calls.
OUT2="$(gen --record-move="-tmp-alpha|a_keep.md" 2>&1)"
check "a malformed --record-move is refused" '[[ "$OUT2" == *"REFUSE: --record-move needs"* ]]'
check "the source is unlinked after"   '[[ ! -f "$AIDEX_MEMORY_ROOT/-tmp-alpha/memory/a_move.md" ]]'
check "the ledger records the destination" 'grep -q "a_move.md.*MOVE-REFERENCE.*dest.md" "$LED"'

echo "== the gate now sees a MOVE with no destination =="
gen --verify-applied --project=-tmp-alpha >/dev/null 2>&1
check "a complete alpha verifies" '[[ $? -eq 0 ]]'
cp "$LED" "$TMP/led.save"
: > "$LED"
OUT="$(gen --verify-applied --project=-tmp-alpha 2>&1)"; RC=$?
check "source gone + no ledger entry fails" '[[ $RC -eq 1 && "$OUT" == *"no destination recorded"* ]]'
cp "$TMP/led.save" "$LED"
rm -f "$DEST"
OUT="$(gen --verify-applied --project=-tmp-alpha 2>&1)"; RC=$?
check "a ledger pointing at a deleted destination fails"       '[[ $RC -eq 1 && "$OUT" == *"destination missing or empty"* ]]'

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
