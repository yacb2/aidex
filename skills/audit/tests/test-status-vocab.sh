#!/usr/bin/env bash
# test-status-vocab.sh — validator + row tooling on the CANON model (rebuild
# 2026-07-02): per-methodology layout, base status vocabulary, standalone runs,
# ISO dates in mark_row_escalated, legacy tolerated as warnings.
#
# Run with: bash skills/audit/tests/test-status-vocab.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"  # inventory lock files are kept, never removed
mkdir -p "$TMP/.context/audits/ux/2026-06-01-first-pass"
cd "$TMP"
A=".context/audits"
TODAY="$(date +%F)"

cat > "$A/ux/00-inventory.md" <<'EOF'
# UX Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token in URL | open | P1 | 2026-06-01 | — | — |
| F-2 | bug | search | SQLi in q param | done | P0 | 2026-06-01 | backlog/2026-06-01-fix-sqli | — |
| F-3 | gap | nav | Missing breadcrumbs | doing | P2 | 2026-06-01 | plan/2026-06-01-nav-fixes | — |
| F-4 | idea | perf | Prefetch dashboards | dropped | P3 | 2026-06-01 | — | out of scope this quarter |
| F-5 | bug | forms | Double submit | done | P1 | 2026-06-01 | — | verified: commit abc1234 |
EOF
echo "# UX Methodology" > "$A/ux/00-methodology.md"
echo "# Changelog" > "$A/ux/00-changelog.md"
printf -- '---\ntitle: "UX audit — first pass"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$A/ux/2026-06-01-first-pass/index.md"
printf '# Findings\n\n- **F-1** — token in URL\n' > "$A/ux/2026-06-01-first-pass/findings.md"

# Standalone one-shot run at the audits root (canon §Standalone) — never a violation.
mkdir -p "$A/2026-06-15-usage-retro"
printf -- '---\ntitle: "Usage retro"\nstatus: done\ncreated: 2026-06-15\nupdated: 2026-06-15\nmethodology: standalone\n---\n' > "$A/2026-06-15-usage-retro/index.md"

out="$(bash "$SCRIPTS/validate-audit.sh" --json "$A" 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] || fail "canon tree should validate clean (rc=$rc): $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
count() { printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)" 2>/dev/null; }
[[ "$(count "['findings_in_inventory']")" == "5" ]] || fail "expected 5 canon findings parsed, got $(count "['findings_in_inventory']")"
[[ "$(count "['stats']['open']")" == "1" ]]    || fail "open count: expected 1, got $(count "['stats']['open']")"
[[ "$(count "['stats']['doing']")" == "1" ]]   || fail "doing count: expected 1, got $(count "['stats']['doing']")"
[[ "$(count "['stats']['done']")" == "2" ]]    || fail "done count: expected 2, got $(count "['stats']['done']")"
[[ "$(count "['stats']['dropped']")" == "1" ]] || fail "dropped count: expected 1, got $(count "['stats']['dropped']")"

# A bare `done` with neither Escalated To nor Notes evidence is a violation.
mkdir -p "$A/security"
cat > "$A/security/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| S-1 | bug | api | Bare done no evidence | done | P1 | 2026-06-01 | — | — |
EOF
echo "# m" > "$A/security/00-methodology.md"; echo "# c" > "$A/security/00-changelog.md"
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 && fail "bare done without Escalated To/Notes should be a violation"
out2="$(bash "$SCRIPTS/validate-audit.sh" --json "$A" 2>/dev/null || true)"
printf '%s' "$out2" | grep >/dev/null "S-1" || fail "violation should name S-1"

# Legacy status vocabulary reads as a WARNING (mapped, not a crash / not a violation).
cat > "$A/security/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| S-1 | bug | api | Legacy triaged row | triaged | P1 | 2026-06-01 | — | — |
EOF
out3="$(bash "$SCRIPTS/validate-audit.sh" --json "$A" 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] || fail "legacy vocab must not be fatal (rc=$rc)"
printf '%s' "$out3" | grep >/dev/null -i "legacy status" || fail "expected a legacy-status warning mentioning migration"

# mark_row_escalated writes base vocab + ISO dates + the marker verbatim.
. "$SCRIPTS/_lib.sh"
mark_row_escalated "$A/ux/00-inventory.md" F-1 "backlog/$TODAY-fix-token"
row="$(grep '| F-1 ' "$A/ux/00-inventory.md")"
printf '%s' "$row" | grep >/dev/null "| done |" || fail "mark_row_escalated: status should be 'done', row: $row"
printf '%s' "$row" | grep >/dev/null "backlog/$TODAY-fix-token" || fail "mark_row_escalated: marker not written verbatim"
printf '%s' "$row" | grep >/dev/null "$TODAY" || fail "mark_row_escalated: ISO date missing"
if printf '%s' "$row" | grep >/dev/null -E '[0-9]{8}'; then fail "mark_row_escalated: legacy YYYYMMDD date written: $row"; fi
printf '%s' "$row" | grep >/dev/null "2026-06-01, $TODAY" || fail "mark_row_escalated: Audit Runs should append ISO date, row: $row"

# `fixed` and `wontfix` are aliases of done and dropped (Q6, audit-s28/s34): close-audit accepts
# them as resolved, so every other reader must parse them too. A finding closed as fixed used to
# pass close and then fail validation as an unparseable row.
set +e  # the earlier _lib.sh source turned errexit on; the checks below read exit codes
ALIAS="$TMP/alias"; mkdir -p "$ALIAS/.context/audits/ux/2026-06-01-run" && cd "$ALIAS"
AA=".context/audits"
cat > "$AA/ux/00-inventory.md" <<'EOF2'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token in URL | fixed | P1 | 2026-06-01-run | — | verified: commit abc1234 |
| F-2 | idea | perf | Prefetch | wontfix | P3 | 2026-06-01-run | — | out of scope |
| F-3 | bug | nav | Still open | open | P2 | 2026-06-01-run | — | — |
EOF2
echo "# m" > "$AA/ux/00-methodology.md"; echo "# c" > "$AA/ux/00-changelog.md"
printf -- '---\ntitle: "UX run"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$AA/ux/2026-06-01-run/index.md"
printf '# Findings\n\n- **F-1** a\n- **F-2** b\n- **F-3** c\n' > "$AA/ux/2026-06-01-run/findings.md"
outa="$(bash "$SCRIPTS/validate-audit.sh" --json "$AA" 2>/dev/null)"
cnt() { printf '%s' "$outa" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)" 2>/dev/null; }
[[ "$(cnt "['findings_in_inventory']")" == "3" ]] || fail "alias: fixed/wontfix rows must parse, got $(cnt "['findings_in_inventory']") findings"
[[ "$(cnt "['stats']['done']")" == "1" ]]    || fail "alias: fixed must count as done, got $(cnt "['stats']['done']")"
[[ "$(cnt "['stats']['dropped']")" == "1" ]] || fail "alias: wontfix must count as dropped, got $(cnt "['stats']['dropped']")"
[[ "$(cnt "['stats']['legacy_status_values']")" == "0" ]] || fail "alias: fixed/wontfix are aliases, not legacy values"
printf '%s' "$outa" | grep >/dev/null -i "unparseable" && fail "alias: a fixed/wontfix row was reported as unparseable"
# Escalation treats them like their targets: fixed = already done (rc 4), wontfix = dropped (rc 5)
. "$SCRIPTS/_lib.sh"; set +e  # _lib.sh turns errexit on; the checks below read exit codes
mark_row_escalated "$AA/ux/00-inventory.md" F-1 "backlog/$TODAY-x" >/dev/null 2>&1; rc=$?
[[ $rc -eq 4 ]] || fail "alias: mark_row_escalated on a fixed row should return 4 (already done), rc $rc"
mark_row_escalated "$AA/ux/00-inventory.md" F-2 "backlog/$TODAY-x" >/dev/null 2>&1; rc=$?
[[ $rc -eq 5 ]] || fail "alias: mark_row_escalated on a wontfix row should return 5 (dropped), rc $rc"
# wontfix keeps the dropped rule: a reason in Notes (a bare board, so no orphan reference also fails it)
mkdir -p "$TMP/alias2/$AA/ux" && cd "$TMP/alias2"
cat > "$AA/ux/00-inventory.md" <<'EOF2'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-2 | idea | perf | Prefetch | wontfix | P3 | 2026-06-01-run | — | — |
EOF2
echo "# m" > "$AA/ux/00-methodology.md"; echo "# c" > "$AA/ux/00-changelog.md"
outw="$(bash "$SCRIPTS/validate-audit.sh" --json "$AA" 2>/dev/null)"
[[ "$outw" == *audit-lifecycle-dropped-unreasoned* ]] || fail "alias: wontfix without a Notes reason should be a dropped-unreasoned violation"
# fixed keeps the done rule: an Escalated To marker or evidence in Notes
mkdir -p "$TMP/alias3/$AA/ux" && cd "$TMP/alias3"
cat > "$AA/ux/00-inventory.md" <<'EOF2'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | a | s | fixed | P1 | 2026-06-01-run | — | — |
EOF2
echo "# m" > "$AA/ux/00-methodology.md"; echo "# c" > "$AA/ux/00-changelog.md"
outf="$(bash "$SCRIPTS/validate-audit.sh" --json "$AA" 2>/dev/null)"
[[ "$outf" == *audit-lifecycle-done-unevidenced* ]] || fail "alias: fixed without evidence should be a done-unevidenced violation"
cd "$TMP"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon layout validation, base vocab counts, done-evidence rule, legacy warning, ISO escalation"
