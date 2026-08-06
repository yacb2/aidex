#!/usr/bin/env bash
# test-migrate.sh — migrate-audit.sh --layout converts a LEGACY audits tree to
# canon (rebuild 2026-07-02): YYYYMMDD run names -> ISO, legacy status values ->
# base vocab, YYYYMMDD cell dates -> ISO, root boards -> audits/<methodology>/.
# Dry-run by default, --apply converts, second --apply is a no-op.
#
# Run with: bash skills/aidex-audit/tests/test-migrate.sh

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
EOF
echo "# Methodology" > "$A/00-methodology.md"
echo "# Changelog"   > "$A/00-changelog.md"
printf '# Index\n' > "$A/20260610-old-run/index.md"
printf '# Findings\n\n- B-1\n' > "$A/20260610-old-run/findings.md"

# --- dry-run: reports, mutates nothing ---
out="$(bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux 2>&1)"
printf '%s' "$out" | grep -q "20260610-old-run" || fail "dry-run should mention the legacy run rename"
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
  fail "legacy status words survive in status cells: $(grep -E 'B-[0-9]' "$INV" | head -2)"
fi
grep -q '2026-06-10' "$INV" || fail "YYYYMMDD cell dates not converted to ISO"
if grep -qE '\| 2026061[0-9] \|'; then :; fi
if grep -qE '20260610|20260611|20260612' "$INV"; then fail "legacy YYYYMMDD dates survive: $(grep -E '2026061' "$INV" | head -1)"; fi

# --- validator is clean (no violations) after migration ---
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 || fail "migrated tree should validate with no violations"

# --- idempotent second apply ---
before="$(find "$A" -type f | sort; grep -h '' "$INV")"
bash "$SCRIPTS/migrate-audit.sh" --layout --methodology ux --apply >/dev/null 2>&1 || fail "second --apply exited non-zero"
after="$(find "$A" -type f | sort; grep -h '' "$INV")"
[[ "$before" == "$after" ]] || fail "second --apply was not a no-op"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — legacy layout/status/date migration, validator-clean result, idempotent"
