#!/usr/bin/env bash
# test-migrate.sh — migrate-audit.sh --layout converts a LEGACY audits tree to
# canon (rebuild 2026-07-02): YYYYMMDD run names -> ISO, legacy status values ->
# base vocab, YYYYMMDD cell dates -> ISO, root boards -> audits/<methodology>/.
# Dry-run by default, --apply converts, second --apply is a no-op.
# Default mode (plans scan): '- [ ]' in a numbered file scores as a plan signal,
# '- [x]' alone does not, and a folder with no signals does not abort the scan.
#
# Run with: bash skills/audit/tests/test-migrate.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/audits/20260610-old-run"
cd "$TMP"
A=".context/audits"

cat > "$A/00-inventory.md" <<'EOF'
# Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| B-1 | bug | auth | Legacy escalated row | escalated | P1 | 20260610, 20260612 | backlog/2026-06-12-fix-b1 | — |
| B-2 | bug | ui | Legacy in-progress row | in-progress | P2 | 20260610 | plan/2026-06-12-ui-fixes | — |
| B-3 | gap | nav | Legacy triaged row | triaged | P3 | 20260610 | — | needs owner |
| B-4 | bug | api | Legacy closed row | closed | P1 | 20260610 | — | verified: abc123 |
| B-5 | bug | api | greps "a\|b" in the router | triaged | P2 | 20260610 | — | — |
EOF
echo "# Methodology" > "$A/00-methodology.md"
echo "# Changelog"   > "$A/00-changelog.md"
printf '# Index\n' > "$A/20260610-old-run/index.md"
printf '# Findings\n\n- B-1\n' > "$A/20260610-old-run/findings.md"

# --- dry-run: reports, mutates nothing ---
out="$(bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux 2>&1)"
printf '%s' "$out" | grep >/dev/null "20260610-old-run" || fail "dry-run should mention the legacy run rename"
[[ -f "$A/00-inventory.md" ]] || fail "dry-run must not move boards"
[[ -d "$A/20260610-old-run" ]] || fail "dry-run must not rename runs"

# --- apply ---
bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply >/dev/null 2>&1 || fail "--apply exited non-zero"
[[ -f "$A/ux/00-inventory.md" ]] || fail "boards not moved under audits/ux/"
[[ -d "$A/ux/2026-06-10-old-run" ]] || fail "run not renamed+moved to audits/ux/2026-06-10-old-run"
[[ ! -f "$A/00-inventory.md" ]] || fail "root boards left behind"
INV="$A/ux/00-inventory.md"
grep -q '| done |' "$INV" || fail "escalated/closed rows not mapped to done"
grep -q '| doing |' "$INV" || fail "in-progress row not mapped to doing"
grep -q '| open |' "$INV" || fail "triaged row not mapped to open"
if grep -qE 'escalated \||in-progress \||triaged \||closed \|' "$INV"; then
  fail "legacy status words survive in status cells: $(grep -E 'B-[0-9]' "$INV" | sed -n 1,2p)"
fi
# (audit-s34) a summary quoting a pipe (\|) is ONE cell; splitting on every | shifted the Status
# cell by one and left this row's `triaged` unconverted. The escape itself must survive.
B5="$(grep -E '^\| B-5 ' "$INV")"
[[ "$B5" == *"| open |"* ]] || fail "escaped-pipe row: triaged not mapped to open: $B5"
[[ "$B5" == *'greps "a\|b" in the router'* ]] || fail "escaped-pipe row: the \\| escape was not restored: $B5"
grep -q '2026-06-10' "$INV" || fail "YYYYMMDD cell dates not converted to ISO"
# (removed 2026-08-21) A `grep -qE '\| 2026061[0-9] \|'` sat here with NO FILE
# ARGUMENT and an empty body (`then :; fi`), so it asserted nothing and read
# STDIN — hanging the whole suite forever whenever stdin was not already at EOF.
# Observed: run-all.sh stuck at 24/83 with no output and no timeout. The check it
# was reaching for is the next line, which does it against "$INV".
if grep -qE '20260610|20260611|20260612' "$INV"; then fail "legacy YYYYMMDD dates survive: $(grep -E '2026061' "$INV" | sed -n 1p)"; fi

# --- validator is clean (no violations) after migration ---
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 || fail "migrated tree should validate with no violations"

# --- idempotent second apply ---
before="$(find "$A" -type f | sort; grep -h '' "$INV")"
bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply >/dev/null 2>&1 || fail "second --apply exited non-zero"
after="$(find "$A" -type f | sort; grep -h '' "$INV")"
[[ "$before" == "$after" ]] || fail "second --apply was not a no-op"

# --- default (plans scan): numbered files with '- [ ]' score as a plan signal ---
# BL-549: the pattern began with '-', so grep read it as an option (exit 2,
# stderr discarded) and the signal never applied. The folder name carries a
# second signal so the run does not die on an empty signals array (bash 3.2).
PFX="$TMP/plans-fixture"
mkdir -p "$PFX/.context/plans/implement-x"
printf -- '- [ ] task\n' > "$PFX/.context/plans/implement-x/01-x.md"
mkdir -p "$PFX/.context/plans/implement-done"
printf -- '- [x] task\n' > "$PFX/.context/plans/implement-done/01-x.md"
out="$(bash "$SCRIPTS/migrate-audit.sh" "$PFX" 2>&1)"
printf '%s' "$out" | grep >/dev/null -F "numbered files with checkboxes (plan signal)" \
  || fail "checkbox plan signal missing from plans scan: $(printf '%s' "$out" | grep -A1 -F implement-x | tr '\n' ' ')"
# Only '- [x]' (all done) is not a checkbox plan signal.
if printf '%s' "$out" | grep -A1 -F implement-done | grep >/dev/null -F "checkboxes"; then
  fail "'- [x]'-only numbered file scored as checkbox plan signal: $(printf '%s' "$out" | grep -A1 -F implement-done | tr '\n' ' ')"
fi

# --- plans scan: a folder that earns no signals must not abort the scan ---
# "${signals[*]}" on an empty array is unbound under set -u on bash 3.2.
PFX2="$TMP/plans-nosignal"
mkdir -p "$PFX2/.context/plans/p1" "$PFX2/.context/plans/security-review"
printf '# notes\n' > "$PFX2/.context/plans/p1/notes.md"
out="$(bash "$SCRIPTS/migrate-audit.sh" "$PFX2" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "plans scan with a no-signal folder exited $rc: $(printf '%s' "$out" | tail -n 1)"
printf '%s' "$out" | grep >/dev/null -F "security-review" || fail "folder with a signal not reported next to a no-signal folder"

# --- audit-c05: --methodology never moves a board or run onto an existing target ---
HEAD9='| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
'
# root 00-inventory.md AND INVENTORY.md: the first apply moves the modern one; the
# second must not move the legacy board over it (that would lose the moved board)
C5="$TMP/c05-both"; mkdir -p "$C5/.context/audits"
printf '%s| M-1 | bug | a | MODERN board | open | P1 | 2026-06-01 | — | — |\n' "$HEAD9" > "$C5/.context/audits/00-inventory.md"
printf '%s| L-1 | bug | a | LEGACY board | open | P1 | 2026-06-01 | — | — |\n' "$HEAD9" > "$C5/.context/audits/INVENTORY.md"
for try in 1 2; do bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply "$C5" >/dev/null 2>&1; done
grep -q 'MODERN board' "$C5/.context/audits/ux/00-inventory.md" 2>/dev/null \
  || fail "c05: the second --apply replaced the moved inventory: $(cat "$C5/.context/audits/ux/00-inventory.md" 2>&1 | tail -n 1)"
[[ -f "$C5/.context/audits/INVENTORY.md" ]] || fail "c05: the legacy board that could not move was deleted"
# an existing methodology inventory is not overwritten by a root board
C5="$TMP/c05-existing"; mkdir -p "$C5/.context/audits/ux"
printf '%s| E-1 | bug | a | EXISTING board | open | P1 | 2026-06-01 | — | — |\n' "$HEAD9" > "$C5/.context/audits/ux/00-inventory.md"
printf '%s| R-1 | bug | a | ROOT board | open | P1 | 2026-06-01 | — | — |\n' "$HEAD9" > "$C5/.context/audits/00-inventory.md"
bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply "$C5" >/dev/null 2>&1
grep -q 'EXISTING board' "$C5/.context/audits/ux/00-inventory.md" || fail "c05: an existing audits/ux/00-inventory.md was overwritten"
[[ -f "$C5/.context/audits/00-inventory.md" ]] || fail "c05: the root board was lost instead of left for a manual merge"
# a legacy run whose ISO twin exists is not nested inside it
C5="$TMP/c05-run"; mkdir -p "$C5/.context/audits/20260610-foo" "$C5/.context/audits/2026-06-10-foo"
bash "$SCRIPTS/migrate-audit.sh" --layout --apply "$C5" >/dev/null 2>&1
[[ ! -e "$C5/.context/audits/2026-06-10-foo/20260610-foo" ]] || fail "c05: 20260610-foo was nested inside its ISO twin"
[[ -d "$C5/.context/audits/20260610-foo" ]] || fail "c05: the legacy run that could not be renamed disappeared"

# round 2: a run reported "stays in place" under --methodology stays in place on the next apply
C5="$TMP/c05-run-meth"; mkdir -p "$C5/.context/audits/20260610-foo" "$C5/.context/audits/2026-06-10-foo"
printf '%s' "$HEAD9" > "$C5/.context/audits/00-inventory.md"
out1="$(bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply "$C5" 2>&1)"
bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply "$C5" >/dev/null 2>&1
[[ -d "$C5/.context/audits/20260610-foo" && ! -e "$C5/.context/audits/2026-06-10-foo" ]] \
  || fail "c05: second --methodology apply moved the run that stayed in place: $(ls "$C5/.context/audits" "$C5/.context/audits/ux")"
[[ "$out1" == *"stays in place"* ]] || fail "c05: first apply did not warn the run stays in place: $out1"
# round 2: a legacy board left behind beside a moved modern one is warned about on the first apply
C5="$TMP/c05-both-warn"; mkdir -p "$C5/.context/audits"
printf '%s' "$HEAD9" > "$C5/.context/audits/00-inventory.md"; printf '%s' "$HEAD9" > "$C5/.context/audits/INVENTORY.md"
out="$(bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply "$C5" 2>&1)"
[[ "$out" == *"INVENTORY.md stays in place"* ]] || fail "c05: first apply was silent about the INVENTORY.md left behind: $out"

# --- audit-c30: only a real calendar-shaped YYYYMMDD becomes an ISO date ---
C30="$TMP/c30"; mkdir -p "$C30/.context/audits/ux"
printf '%s| N-1 | bug | a | Summary | open | P1 | 20260610 | — | build 20991399 and 20260231x |\n' "$HEAD9" > "$C30/.context/audits/ux/00-inventory.md"
bash "$SCRIPTS/migrate-audit.sh" --layout --apply "$C30" >/dev/null 2>&1
grep -q 'build 20991399' "$C30/.context/audits/ux/00-inventory.md" || fail "c30: a non-date 20991399 was rewritten: $(grep N-1 "$C30/.context/audits/ux/00-inventory.md")"
grep -q '20260231x' "$C30/.context/audits/ux/00-inventory.md" || fail "c30: a word glued to digits (20260231x) was rewritten"
grep -q '| 2026-06-10 |' "$C30/.context/audits/ux/00-inventory.md" || fail "c30: a real YYYYMMDD cell date was not converted"

# --- audit-s16: the plans-scan advice names the migration guide at a path that exists ---
S16="$TMP/s16"; mkdir -p "$S16/.context/plans/2026-01-01-x"
out="$(bash "$SCRIPTS/migrate-audit.sh" "$S16" 2>&1)"
guide="$(printf '%s\n' "$out" | sed -n 's/^ *See \(.*05-migration-guide\.md\) for full details\.$/\1/p')"
[[ -n "$guide" && -f "$guide" ]] || fail "s16: advice does not name an existing migration guide: '$guide'"

# --- audit-s42: --layout --apply reports a failing reindex (duplicate id) and still succeeds ---
M42="$TMP/m42"; mkdir -p "$M42/.context/audits/ux"
printf '%s| N-1 | bug | a | S | open | P1 | 20260610 | — | n |\n| N-1 | bug | a | S | open | P1 | 20260610 | — | n |\n' "$HEAD9" > "$M42/.context/audits/ux/00-inventory.md"
out="$(cd "$M42" && bash "$SCRIPTS/migrate-audit.sh" --layout --apply "$M42" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "s42: a failed reindex must not fail the layout migration (rc=$rc): $out"
[[ "$out" == *"index not regenerated"*"duplicate finding id"* ]] || fail "s42: layout --apply swallowed the reindex failure: $out"

# --- round 3: the reindex follows the project argument, not the cwd ---
PA="$TMP/projA"; PB="$TMP/projB"; mkdir -p "$PA/.context/audits/ux" "$PB/.context/audits"
printf '%s| N-1 | bug | a | S | open | P1 | 20260610 | — | n |\n' "$HEAD9" > "$PA/.context/audits/ux/00-inventory.md"
(cd "$PB" && bash "$SCRIPTS/migrate-audit.sh" --layout --apply "$PA" >/dev/null 2>&1) || fail "r3: migrate from another project exited non-zero"
[[ -f "$PA/.context/audits/00-index.md" ]] || fail "r3: the migrated project's index was not regenerated"
[[ ! -e "$PB/.context/audits/00-index.md" ]] || fail "r3: the cwd project's index was written instead"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — legacy layout/status/date migration, validator-clean result, idempotent; plans scan checkbox signal, - [x] not scored, no-signal folder"
