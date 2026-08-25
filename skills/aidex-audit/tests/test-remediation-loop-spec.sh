#!/usr/bin/env bash
# test-remediation-loop-spec.sh — the run-level audit -> remediation handoff (BL-219).
#
# What is pinned, in order of what would silently break:
#   1. The GATE reads the INVENTORY, not a checklist inside the spec. Ticking a
#      box in the spec must NOT turn the gate green; moving the row must.
#   2. Emit leaves rows `doing` + a loop marker — never `done`, which would make
#      the gate green at t=0 and the write-back vacuous.
#   3. The spec needs no hand-editing: engine decided (in the enum), gate is a
#      command, no operator TODO left behind.
#   4. Priority grouping, every unresolved id carried, resolved ones excluded.
#   5. The emitted tree validates clean under BOTH validators (validate-audit.sh
#      and validate.py --type loops) — aidex-loop has no validator of its own.
#
# Run with: bash skills/aidex-audit/tests/test-remediation-loop-spec.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
CONV="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-conventions" && pwd -P)"
LOOPCONV="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../aidex-loop" && pwd -P)"
EMIT="$SCRIPTS/remediation-loop-spec.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/audits/security/2026-06-21-3mo-retro" "$TMP/.context/loops"
cd "$TMP"
A=".context/audits"
INV="$A/security/00-inventory.md"

cat > "$INV" <<'EOF'
<!--
EXAMPLE ROWS (must never be picked up):

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| EX-01-1 | bug | auth | Example row | open | P0 | 2026-06-21 | — | — |
-->

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| SEC-1 | bug | auth | Session token in URL query string | open | P0 | 2026-06-21 | — | — |
| SEC-2 | bug | api | Missing rate limit on login | open | P1 | 2026-06-21 | — | — |
| SEC-3 | gap | api | No CSRF token on form posts | open | P2 | 2026-06-21 | — | — |
| SEC-4 | bug | auth | Already fixed last cycle | done | P1 | 2026-06-21 | — | Closed: abc1234 — fixed |
| SEC-5 | risk | infra | Belongs to another run | open | P0 | 2026-05-02 | — | — |
EOF
echo "# m" > "$A/security/00-methodology.md"; echo "# c" > "$A/security/00-changelog.md"
printf -- '---\ntitle: "3mo retro"\nstatus: doing\ncreated: 2026-06-21\nupdated: 2026-06-21\nmethodology: security\n---\n' \
  > "$A/security/2026-06-21-3mo-retro/index.md"
printf '# Findings\n\n- **SEC-1** token\n- **SEC-2** rate limit\n- **SEC-3** csrf\n' \
  > "$A/security/2026-06-21-3mo-retro/findings.md"

# ---------- emit ----------
bash "$EMIT" 2026-06-21-3mo-retro >/dev/null 2>&1 || fail "emit exited non-zero"
SPEC="$(ls .context/loops/*.md 2>/dev/null | grep -v STATE | head -1)"
[[ -n "$SPEC" ]] || { echo "FATAL: no loop-spec emitted"; exit 1; }

# ---------- 1. emit marks rows doing + marker, never done ----------
for id in SEC-1 SEC-2 SEC-3; do
  row="$(grep "^| $id " "$INV")"
  printf '%s' "$row" | grep -q '| doing |' || fail "$id should be doing after emit, row: $row"
  printf '%s' "$row" | grep -qE '\| loop/[0-9]{4}-[0-9]{2}-[0-9]{2}-remediate-[a-z0-9-]+ \|' \
    || fail "$id should carry a loop/<filename> marker, row: $row"
done
grep -q '^| SEC-4 .*| done |' "$INV" || fail "SEC-4 (already done) must be untouched"
grep -q '^| SEC-5 .*| open |' "$INV" || fail "SEC-5 (other run) must be untouched"
grep -q '| EX-01-1 |.*| open |' "$INV" || fail "the commented EXAMPLE row must be untouched"

# ---------- 2. gate is inventory-anchored (the safety property) ----------
bash "$EMIT" 2026-06-21-3mo-retro --check >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "gate must be RED while findings are unresolved"

# RED probe (appearance mutation): tick every checklist box in the SPEC. The
# spec still reads as a finished remediation; only the write-back is missing.
cp "$SPEC" "$TMP/spec.bak"
sed -i.bak 's/^- \[ \] \*\*SEC/- [x] **SEC/' "$SPEC" && rm -f "$SPEC.bak"
grep -q '^- \[x\] \*\*SEC-1\*\*' "$SPEC" || fail "probe setup: checklist boxes not ticked"
bash "$EMIT" 2026-06-21-3mo-retro --check >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "RED probe: a ticked in-spec checklist turned the gate GREEN — completion is detached from the finding"
cp "$TMP/spec.bak" "$SPEC"

# GREEN: the same gate flips only when the rows move.
sed -i.bak -E 's/^(\| SEC-[123] .*)\| doing \|/\1| done |/' "$INV" && rm -f "$INV.bak"
bash "$EMIT" 2026-06-21-3mo-retro --check >/dev/null 2>&1
[[ $? -eq 0 ]] || fail "gate must be GREEN once every row of the run is resolved"
# restore the emitted state for the remaining cells
sed -i.bak -E 's/^(\| SEC-[123] .*)\| done \|/\1| doing |/' "$INV" && rm -f "$INV.bak"

# ---------- 3. no hand-editing needed ----------
grep -q '^engine: goal' "$SPEC" || fail "engine must be decided, got: $(grep '^engine:' "$SPEC")"
grep -q '^engine: undecided' "$SPEC" && fail "engine left undecided"
ENUM="$(grep -m1 '^engine:' "$LOOPCONV/references/02-loop-spec-conventions.md" | sed 's/.*#//' | tr -d ' ' | tr '|' '\n')"
printf '%s\n' "$ENUM" | grep -qx 'goal' || fail "chosen engine 'goal' is not in the loop-spec enum"
grep -qi 'TODO (operator)' "$SPEC" && fail "spec carries an operator TODO — it needs hand-editing"
grep -q '____' "$SPEC" && fail "spec carries unfilled ____ blanks — it needs hand-editing"
grep -q 'remediate 2026-06-21-3mo-retro --check' "$SPEC" || fail "spec's gate does not name the check command"
grep -q '^origin_ref: audit/security/2026-06-21-3mo-retro$' "$SPEC" \
  || fail "origin_ref back-link missing/wrong: $(grep '^origin_ref' "$SPEC" || echo '(none)')"
# the origin_ref must RESOLVE (the 1fb202c family of defect)
REF="$(grep -m1 '^origin_ref: ' "$SPEC" | sed 's/^origin_ref: audit\///')"
[[ -d "$A/$REF" ]] || fail "origin_ref does not resolve to a run folder: $A/$REF"

# ---------- 4. work-list: every unresolved id, priority-ordered, nothing else ----------
for id in SEC-1 SEC-2 SEC-3; do
  grep -q "\*\*$id\*\*" "$SPEC" || fail "$id missing from the work-list"
done
grep -q '\*\*SEC-4\*\*' "$SPEC" && fail "SEC-4 is done — must not be in the work-list"
grep -q '\*\*SEC-5\*\*' "$SPEC" && fail "SEC-5 belongs to another run — must not be in the work-list"
grep -q '\*\*EX-01-1\*\*' "$SPEC" && fail "commented EXAMPLE row leaked into the work-list"
ORDER="$(grep -nE '^### (P0|P1|P2)$' "$SPEC" | cut -d: -f2 | tr '\n' ' ')"
[[ "$ORDER" == "### P0 ### P1 ### P2 " ]] || fail "severity bands out of order: $ORDER"
grep -q "$INV" "$SPEC" || fail "State file section does not name the inventory"

# ---------- 5. both validators accept the emitted tree ----------
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 || fail "emitted tree fails validate-audit.sh"
V_OUT="$(python3 "$CONV/scripts/validate.py" .context --type loops --json 2>&1)"
V_CODE=$?
printf '%s' "$V_OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(1 if d.get("violations") else 0)' 2>/dev/null \
  || fail "emitted loop-spec fails validate.py --type loops: $V_OUT"
[[ "$V_CODE" -eq 0 ]] || fail "validate.py --type loops exited $V_CODE: $V_OUT"

# ---------- 6. refusals ----------
bash "$EMIT" no-such-run >/dev/null 2>&1
[[ $? -ne 0 ]] || fail "unknown run should exit non-zero"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — inventory-anchored gate, doing+marker at emit, no hand-editing, priority-grouped, both validators clean"
