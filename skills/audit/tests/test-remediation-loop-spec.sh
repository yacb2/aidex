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
#      and validate.py --type loops) — loop has no validator of its own.
#
# Run with: bash skills/audit/tests/test-remediation-loop-spec.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
CONV="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../conventions" && pwd -P)"
LOOPCONV="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../loop" && pwd -P)"
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
SPEC="$(ls .context/loops/*.md 2>/dev/null | grep -v STATE | sed -n 1p)"
[[ -n "$SPEC" ]] || { echo "FATAL: no loop-spec emitted"; exit 1; }

# ---------- 1. emit marks rows doing + marker, never done ----------
for id in SEC-1 SEC-2 SEC-3; do
  row="$(grep "^| $id " "$INV")"
  printf '%s' "$row" | grep >/dev/null '| doing |' || fail "$id should be doing after emit, row: $row"
  printf '%s' "$row" | grep >/dev/null -E '\| loop/[0-9]{4}-[0-9]{2}-[0-9]{2}-remediate-[a-z0-9-]+ \|' \
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
printf '%s\n' "$ENUM" | grep >/dev/null -x 'goal' || fail "chosen engine 'goal' is not in the loop-spec enum"
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

# ---------- 6. the LEGACY 11-column board (First Seen / Last Updated) ----------
# Not hypothetical: .context/audits/ecosystem/00-inventory.md in this repo is
# this shape. A fixed cell index on it reads Escalated To where Audit Runs
# lives, and every finding then looks out of scope — silently.
mkdir -p "$A/perf/2026-07-04-legacy-board"
cat > "$A/perf/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| PERF-1 | bug | api | N+1 query on the list endpoint | open | P1 | 2026-05-01 | 2026-06-02 | 2026-07-04 | — | — |
| PERF-2 | gap | web | No bundle-size budget | done | P3 | 2026-05-01 | 2026-06-02 | 2026-07-04 | — | Closed: def5678 — added |
EOF
echo "# m" > "$A/perf/00-methodology.md"; echo "# c" > "$A/perf/00-changelog.md"
printf -- '---\ntitle: "legacy board"\nstatus: doing\ncreated: 2026-07-04\nupdated: 2026-07-04\nmethodology: perf\n---\n' \
  > "$A/perf/2026-07-04-legacy-board/index.md"
printf '# Findings\n\n- **PERF-1** n+1\n' > "$A/perf/2026-07-04-legacy-board/findings.md"

bash "$EMIT" 2026-07-04-legacy-board >/dev/null 2>&1 || fail "emit on a legacy 11-column board exited non-zero"
LSPEC="$(ls .context/loops/*legacy-board*.md 2>/dev/null | sed -n 1p)"
[[ -n "$LSPEC" ]] || fail "no loop-spec emitted for the legacy board"
if [[ -n "$LSPEC" ]]; then
  grep -q '\*\*PERF-1\*\*' "$LSPEC" || fail "legacy board: PERF-1 missing from the work-list (Audit Runs cell read from the wrong column?)"
  grep -q '\*\*PERF-2\*\*' "$LSPEC" && fail "legacy board: PERF-2 is done — must not be listed"
fi
lrow="$(grep '^| PERF-1 ' "$A/perf/00-inventory.md")"
printf '%s' "$lrow" | grep >/dev/null '| doing |' || fail "legacy board: PERF-1 should be doing, row: $lrow"
printf '%s' "$lrow" | grep >/dev/null -E '\| loop/[0-9]{4}-[0-9]{2}-[0-9]{2}-remediate-[a-z0-9-]+ \|' \
  || fail "legacy board: marker written to the wrong column, row: $lrow"
printf '%s' "$lrow" | grep >/dev/null -E '\| 2026-05-01 \| 2026-06-02 \| 2026-07-04 \|' \
  || fail "legacy board: the First Seen / Last Updated / Audit Runs cells were disturbed, row: $lrow"
bash "$EMIT" 2026-07-04-legacy-board --check >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "legacy board: gate should be RED while PERF-1 is unresolved"

# ---------- 6b. a Summary quoting a pipe (\|) is one cell ----------
# Split on a raw "|", the escape shifts Status/Severity one cell right: the row
# is read as status 'b" in the router', silently dropped from gate, work-list
# and marking, and its held marker is never seen on re-emit.
mkdir -p "$A/pipes/2026-07-10-pipes"
cat > "$A/pipes/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| PIPE-1 | bug | api | greps "a\|b" in the router | open | P0 | 2026-07-10 | — | — |
| PIPE-2 | bug | mod\|x | module pipe | open | P1 | 2026-07-10 | — | — |
| PIPE-3 | bug | api | notes pipe | open | P2 | 2026-07-10 | — | see a\|b |
| PIPE-4 | bug | api | done "a\|b" | done | P1 | 2026-07-10 | — | Closed: abc1234 — a\|b |
EOF
echo "# m" > "$A/pipes/00-methodology.md"; echo "# c" > "$A/pipes/00-changelog.md"
printf -- '---\ntitle: "pipes"\nstatus: doing\ncreated: 2026-07-10\nupdated: 2026-07-10\nmethodology: pipes\n---\n' \
  > "$A/pipes/2026-07-10-pipes/index.md"
bash "$EMIT" 2026-07-10-pipes --check >/dev/null 2>&1
[[ $? -eq 1 ]] || fail "escaped pipe: gate should be RED while PIPE-1 is open"
bash "$EMIT" 2026-07-10-pipes >/dev/null 2>&1 || fail "escaped pipe: emit exited non-zero"
PSPEC="$(ls .context/loops/*remediate-pipes*.md 2>/dev/null | sed -n 1p)"
grep -qF '**PIPE-1** (api) — greps "a\|b" in the router' "${PSPEC:-/dev/null}" \
  || fail "escaped pipe: PIPE-1 missing from the work-list or its summary altered"
prow="$(grep '^| PIPE-1 ' "$A/pipes/00-inventory.md")"
[[ "$prow" =~ ^'| PIPE-1 | bug | api | greps "a\|b" in the router | doing | P0 | 2026-07-10 | loop/'[0-9-]+'-remediate-pipes | — |'$ ]] \
  || fail "escaped pipe: row should be doing + marker with Summary and Severity intact, row: $prow"
grep -qF '**PIPE-2** (mod\|x) — module pipe' "${PSPEC:-/dev/null}" \
  || fail "escaped pipe: PIPE-2 Module cell not restored in the work-list"
grep -q $'\037' "${PSPEC:-/dev/null}" && fail "escaped pipe: a raw US placeholder leaked into the loop-spec"
prow3="$(grep '^| PIPE-3 ' "$A/pipes/00-inventory.md")"
[[ "$prow3" =~ ^'| PIPE-3 | bug | api | notes pipe | doing | P2 | 2026-07-10 | loop/'[0-9-]+'-remediate-pipes | see a\|b |'$ ]] \
  || fail "escaped pipe: Notes-only \\| row should be doing + marker with Notes intact, row: $prow3"
[[ "$(grep '^| PIPE-4 ' "$A/pipes/00-inventory.md")" == '| PIPE-4 | bug | api | done "a\|b" | done | P1 | 2026-07-10 | — | Closed: abc1234 — a\|b |' ]] \
  || fail "escaped pipe: the done PIPE-4 row was not left byte-identical"
PRE_OUT="$(bash "$EMIT" 2026-07-10-pipes 2>&1)"
printf '%s' "$PRE_OUT" | grep >/dev/null 'already held by loop/' \
  || fail "escaped pipe: re-emit not refused by the held-marker check, got: $PRE_OUT"

# ---------- 6c. a run owns whole Audit Runs tokens, never a substring ----------
# `2026-07-10-ux` is a prefix of `2026-07-10-ux-mobile`, and its date is a
# substring of every same-day slug: a substring test let the run gate on, list,
# mark and be refused by the other run's rows. A bare-date token still names
# every run of that date (legacy rows; cells 1-6b rely on it).
mkdir -p "$A/ux/2026-07-10-ux" "$A/ux/2026-07-10-ux-mobile"
cat > "$A/ux/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-1 | bug | web | desktop finding | done | P1 | 2026-06-01-old, 2026-07-10-ux | — | — |
| UX-2 | bug | web | mobile finding | open | P1 | 2026-07-10-ux-mobile | — | — |
| UX-3 | bug | web | held by mobile | doing | P2 | 2026-07-10-ux-mobile | loop/2026-07-11-remediate-ux-mobile | — |
EOF
echo "# m" > "$A/ux/00-methodology.md"; echo "# c" > "$A/ux/00-changelog.md"
for r in ux ux-mobile; do
  printf -- '---\ntitle: "%s"\nstatus: doing\ncreated: 2026-07-10\nupdated: 2026-07-10\nmethodology: ux\n---\n' "$r" \
    > "$A/ux/2026-07-10-$r/index.md"
done
UX2='| UX-2 | bug | web | mobile finding | open | P1 | 2026-07-10-ux-mobile | — | — |'
UX3='| UX-3 | bug | web | held by mobile | doing | P2 | 2026-07-10-ux-mobile | loop/2026-07-11-remediate-ux-mobile | — |'
bash "$EMIT" 2026-07-10-ux --check >/dev/null 2>&1
[[ $? -eq 0 ]] || fail "whole token: gate RED on 2026-07-10-ux with its only row done — another run's row was claimed"
sed -i.bak 's/^| UX-1 \(.*\)| done |/| UX-1 \1| open |/' "$A/ux/00-inventory.md" && rm -f "$A/ux/00-inventory.md.bak"
UX_OUT="$(bash "$EMIT" 2026-07-10-ux 2>&1)" || fail "whole token: emit for 2026-07-10-ux exited non-zero"
printf '%s' "$UX_OUT" | grep >/dev/null 'already held by loop/' \
  && fail "whole token: emit refused by 2026-07-10-ux-mobile's held marker, got: $UX_OUT"
USPEC="$(ls .context/loops/*-remediate-ux.md 2>/dev/null | sed -n 1p)"
grep -q '\*\*UX-1\*\*' "${USPEC:-/dev/null}" || fail "whole token: UX-1 (multi-token Audit Runs cell) missing from the work-list"
grep -q '\*\*UX-2\*\*' "${USPEC:-/dev/null}" && fail "whole token: UX-2 belongs to 2026-07-10-ux-mobile — must not be in the work-list"
grep '^| UX-1 ' "$A/ux/00-inventory.md" | grep >/dev/null -E '\| doing \| P1 \| 2026-06-01-old, 2026-07-10-ux \| loop/[0-9-]+-remediate-ux \|' \
  || fail "whole token: UX-1 should be doing + marker, row: $(grep '^| UX-1 ' "$A/ux/00-inventory.md")"
[[ "$(grep '^| UX-2 ' "$A/ux/00-inventory.md")" == "$UX2" ]] \
  || fail "whole token: 2026-07-10-ux-mobile's UX-2 row was rewritten: $(grep '^| UX-2 ' "$A/ux/00-inventory.md")"
[[ "$(grep '^| UX-3 ' "$A/ux/00-inventory.md")" == "$UX3" ]] \
  || fail "whole token: 2026-07-10-ux-mobile's UX-3 row was rewritten: $(grep '^| UX-3 ' "$A/ux/00-inventory.md")"

# ---------- 7. refusals ----------
# Re-emit while a live spec still holds the rows: the marker only fills an EMPTY
# cell, so a second spec would list rows that point at the first one.
RE_OUT="$(bash "$EMIT" 2026-06-21-3mo-retro 2>&1)"
[[ $? -ne 0 ]] || fail "re-emit should refuse while a live remediation spec holds the rows"
# The refusal must be the MARKER check, not an incidental same-day filename
# collision -- that one disappears tomorrow and takes the guard with it.
printf '%s' "$RE_OUT" | grep >/dev/null 'already held by loop/' \
  || fail "re-emit refused for the wrong reason (expected the held-marker check), got: $RE_OUT"
[[ "$(ls .context/loops/*3mo-retro*.md 2>/dev/null | wc -l | tr -d ' ')" == "1" ]] \
  || fail "a refused re-emit must not leave a second spec behind"
bash "$EMIT" no-such-run >/dev/null 2>&1
[[ $? -ne 0 ]] || fail "unknown run should exit non-zero"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — inventory-anchored gate, doing+marker at emit, no hand-editing, priority-grouped, both validators clean"
