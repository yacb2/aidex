#!/usr/bin/env bash
# A backlog id or an ADR id mentioned in prose is not an orphan finding reference.
#
# The orphan check scrapes findings.md with `grep -oE '\b[A-Z]+(-[A-Z0-9]+)?-[0-9]+\b'`
# and demands that every token it catches exist in some audit inventory. That pattern
# cannot tell a finding id from the id of a SIBLING TIER: aidex reserves `BL-<n>` for
# backlog items and `D-<n>` for ADRs, and a findings narrative cites them constantly —
# "that is unmeasured (BL-166)", "`.context/` stays English (D-04)". Those ids live in
# backlog/ and decisions/, never in an audit inventory, so every mention was reported as
# an orphan with no correct way to close it: you cannot add BL-166 to an audit board,
# because it is not an audit finding.
#
# Observed 2026-08-24: promoting the usage-retro run out of the audits root brought its
# findings.md under a methodology board for the first time and produced four such
# violations at once (BL-166, BL-167, BL-171, D-04) — noise that pushes a reader to waive
# the RULE, which would also silence the real orphans it exists to catch.
#
# Invariants:
#   1. A real finding id present in the inventory raises nothing.
#   2. A real finding id ABSENT from the inventory still violates — the teeth stay.
#   3. `BL-<n>` in prose raises nothing.
#   4. `D-<n>` in prose raises nothing.
#
# Run: bash skills/aidex-audit/tests/test-orphan-finding-ref.sh
set -euo pipefail

SKILL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VALIDATE="$SKILL/scripts/validate-audit.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

AUD="$TMP/.context/audits"
M="$AUD/probe"
RUN="$M/2026-01-01-probe"
mkdir -p "$RUN"

cat > "$M/00-inventory.md" <<'EOF'
# probe Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| PR-01 | bug | core | A real finding that is on the board | open | P2 | 2026-01-01-probe | — | — |
EOF
printf '# probe methodology\n' > "$M/00-methodology.md"
printf '# probe changelog\n'   > "$M/00-changelog.md"
printf -- '---\ntitle: "probe"\nstatus: done\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n\n# probe\n' > "$RUN/index.md"

# `|| true`: no orphans is the PASSING case, and grep exits 1 on no match, which
# `set -e` would turn into a silent abort mid-test.
orphans() { grep -o 'references [A-Z0-9-]* which is not in any inventory' "$TMP/out" 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ' || true; }
run() { "$VALIDATE" "$AUD" >"$TMP/out" 2>&1 || true; }

# ---- 1 + 3 + 4: a board finding plus sibling-tier ids in prose ----
cat > "$RUN/findings.md" <<'EOF'
# Findings

### PR-01 — the finding that is on the board
The recall claim is unmeasured (BL-166), and follow-up work is tracked as BL-167.
`.context/` stays English (D-04) regardless of the chat language.
EOF
run
got="$(orphans)"
[[ -z "$got" ]] || err "(1,3,4) expected no orphan for a board finding or for sibling-tier ids in prose; got: $got"

# ---- 2: the teeth — a finding id that is on no board ----
cat > "$RUN/findings.md" <<'EOF'
# Findings

### PR-01 — the finding that is on the board
### PR-99 — a finding that reached no inventory
EOF
run
got="$(orphans)"
[[ "$got" == *"PR-99"* ]] || err "(2) a finding id absent from every inventory must still violate; got: '$got'"
if [[ "$got" == *"PR-01"* ]]; then err "(2) PR-01 is on the board and must not be reported; got: '$got'"; fi

if [[ $fail -eq 0 ]]; then echo "OK: sibling-tier ids (BL-/D-) are not orphan findings; a real missing finding id still is"; fi
exit $fail
