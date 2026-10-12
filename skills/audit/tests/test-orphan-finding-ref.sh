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
#   5. A THREE-segment finding id on the board raises nothing. The `(-[A-Z0-9]+)?`
#      group takes at most one segment before the number, so `SEC-FE-CATALOG-01` never
#      matched from its own start — grep re-anchored after the first dash and reported
#      `FE-CATALOG-01`, an id that appears in no inventory because it does not exist.
#      Observed on a real security run: ~39 violations, every one of them a frontend
#      finding, every one a false positive. That is the shape that teaches a reader to
#      waive the rule.
#   6. `CWE-<n>` in prose raises nothing — a weakness-catalogue reference is a sibling
#      vocabulary like BL-/D-, not a finding id.
#   7. `<methodology>/<id>` resolves against that methodology's board only, even when
#      it sorts later (all boards are read first); absent there, it is an orphan
#      named in its qualified form, whatever other boards hold.
#   8. A bare id resolves against the citing run's own methodology first, else
#      against the ONE other methodology that holds it (find_inventory_for_id's
#      rule); held by two or more others it is reported and told to qualify.
#   9. A `<word>/` prefix that is not a methodology folder (an origin_ref path, a
#      proofs path) is not a qualifier: the id behind it reads as bare.
#
# Run: bash skills/audit/tests/test-orphan-finding-ref.sh
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
| PR-FE-CATALOG-01 | bug | frontend | A three-segment finding id | open | P2 | 2026-01-01-probe | — | — |
EOF
printf '# probe methodology\n' > "$M/00-methodology.md"
printf '# probe changelog\n'   > "$M/00-changelog.md"
printf -- '---\ntitle: "probe"\nstatus: done\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n\n# probe\n' > "$RUN/index.md"

# `|| true`: no orphans is the PASSING case, and grep exits 1 on no match, which
# `set -e` would turn into a silent abort mid-test.
orphans() { grep -o 'references [A-Z0-9-]* which is not in' "$TMP/out" 2>/dev/null | awk '{print $2}' | sort -u | tr '\n' ' ' || true; }
run() { "$VALIDATE" "$AUD" >"$TMP/out" 2>&1 || true; }

# ---- 1 + 3 + 4: a board finding plus sibling-tier ids in prose ----
cat > "$RUN/findings.md" <<'EOF'
# Findings

### PR-01 — the finding that is on the board
The recall claim is unmeasured (BL-166), and follow-up work is tracked as BL-167.
`.context/` stays English (D-04) regardless of the chat language.

### PR-FE-CATALOG-01 — a three-segment id, on the board
Maps to CWE-1236 upstream.
EOF
run
got="$(orphans)"
[[ -z "$got" ]] || err "(1,3,4,5,6) expected no orphan for a board finding, a three-segment board finding, sibling-tier ids or a CWE ref; got: $got"

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

# ---- 5, teeth: a three-segment id that is on NO board must still violate ----
cat > "$RUN/findings.md" <<'EOF'
# Findings

### PR-FE-MEDIA-06 — a three-segment finding that reached no inventory
EOF
run
got="$(orphans)"
[[ "$got" == *"PR-FE-MEDIA-06"* ]] || err "(5) an absent three-segment id must violate as its FULL id; got: '$got'"
[[ "$got" == *"FE-MEDIA-06"* && "$got" != *"PR-FE-MEDIA-06"* ]] && err "(5) reported a re-anchored suffix instead of the full id; got: '$got'"

# ---- 7, 8, 9: ids are scoped to a methodology (audit-conventions.md § ID conventions) ----
# Three methodologies. aaa holds AAA-01 and F-001, mmm holds F-001 (the global F-NNN
# default collides), zzz holds ZZZ-01. Every check also asserts the validator RAN:
# an absence of orphans is only evidence if the report was printed.
XA="$TMP/x/.context/audits"
for m in aaa mmm zzz; do
  mkdir -p "$XA/$m/2026-01-01-run"
  printf '# %s\n' "$m" > "$XA/$m/00-methodology.md"
  printf '# %s\n' "$m" > "$XA/$m/00-changelog.md"
  printf -- '---\ntitle: "%s"\nstatus: done\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\n' "$m" > "$XA/$m/2026-01-01-run/index.md"
done
inv_rows() { printf '| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |\n|---|---|---|---|---|---|---|---|---|\n'; for i in "$@"; do printf '| %s | gap | core | a finding | open | P2 | 2026-01-01-run | — | n |\n' "$i"; done; }
inv_rows AAA-01 F-001 > "$XA/aaa/00-inventory.md"
inv_rows F-001 > "$XA/mmm/00-inventory.md"
inv_rows ZZZ-01 > "$XA/zzz/00-inventory.md"
for m in aaa mmm zzz; do printf '# Findings\n' > "$XA/$m/2026-01-01-run/findings.md"; done
# xcheck <row> <findings.md body for the given methodology> <methodology>: runs the
# validator and leaves the orphan-ref lines in $xgot.
xcheck() {
  printf '# Findings\n\n%s\n' "$2" > "$XA/$3/2026-01-01-run/findings.md"
  "$VALIDATE" "$XA" >"$TMP/xout" 2>&1 || true
  printf '# Findings\n' > "$XA/$3/2026-01-01-run/findings.md"
  grep -q 'Audit validation' "$TMP/xout" || err "($1) the validator did not run: $(tail -3 "$TMP/xout")"
  xgot="$(grep 'audit-orphan-finding-ref' "$TMP/xout" || true)"
}

# 7: a qualified reference to a methodology LATER in the alphabet is not an orphan.
xcheck 7 "Re-tests zzz/ZZZ-01." aaa
[[ -z "$xgot" ]] || err "(7) zzz/ZZZ-01 cited from aaa/ is on the zzz board; got: '$xgot'"
# 7b: a qualified reference missing from the named board is an orphan, named qualified.
xcheck 7b "Re-tests zzz/ZZZ-99." aaa
[[ "$xgot" == *"zzz/ZZZ-99"* ]] || err "(7b) zzz/ZZZ-99 is on no board and must violate as zzz/ZZZ-99; got: '$xgot'"
# 7c: qualified means that board only — ZZZ-01 is on zzz, not on aaa.
xcheck 7c "Cites aaa/ZZZ-01." aaa
[[ "$xgot" == *"aaa/ZZZ-01"* ]] || err "(7c) aaa/ZZZ-01 must violate: ZZZ-01 is on the zzz board only; got: '$xgot'"

# 8: a bare id held by exactly one OTHER methodology resolves there (cross-citation).
xcheck 8 "Re-tests AAA-01." zzz
[[ -z "$xgot" ]] || err "(8) bare AAA-01 cited from zzz/ is held by aaa alone; got: '$xgot'"
# 8b: a bare id held by two other methodologies is ambiguous and must say how to qualify.
xcheck 8b "Re-tests F-001." zzz
[[ "$xgot" == *"F-001"* && "$xgot" == *"<methodology>/F-001"* ]] || err "(8b) bare F-001 from zzz/ is on aaa and mmm and must violate naming <methodology>/F-001; got: '$xgot'"
# 8c: the citing methodology's own board wins before any ambiguity check.
xcheck 8c "Re-tests F-001." aaa
[[ -z "$xgot" ]] || err "(8c) bare F-001 cited from aaa/ is on the aaa board itself; got: '$xgot'"

# 9: canon path text is not a qualifier: an origin_ref and a proofs path.
xcheck 9 "Escalated as audit/aaa/2026-01-01-run/AAA-01; proof in proofs/AAA-01/shot.png." aaa
[[ -z "$xgot" ]] || err "(9) origin_ref and proofs paths around AAA-01 (on the aaa board) are not orphans; got: '$xgot'"

if [[ $fail -eq 0 ]]; then echo "OK: sibling-tier ids (BL-/D-/CWE-) and multi-segment board findings are not orphans; a real missing finding id still is"; fi
exit $fail
