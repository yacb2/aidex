#!/usr/bin/env bash
# test-status-vocab.sh — validator + row tooling on the CANON model (rebuild
# 2026-07-02): per-methodology layout, base status vocabulary, standalone runs,
# ISO dates in mark_row_escalated, legacy tolerated as warnings.
#
# Run with: bash skills/aidex-audit/tests/test-status-vocab.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/audits/ux/2026-06-01-first-pass"
cd "$TMP"
A=".context/audits"
TODAY="$(date +%F)"

cat > "$A/ux/00-inventory.md" <<'EOF'
# UX Inventory

| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token in URL | open | P1 | 2026-06-01 | 2026-06-01 | 2026-06-01 | — | — |
| F-2 | bug | search | SQLi in q param | done | P0 | 2026-06-01 | 2026-06-01 | 2026-06-01 | backlog/2026-06-01-fix-sqli | — |
| F-3 | gap | nav | Missing breadcrumbs | doing | P2 | 2026-06-01 | 2026-06-01 | 2026-06-01 | plan/2026-06-01-nav-fixes | — |
| F-4 | idea | perf | Prefetch dashboards | dropped | P3 | 2026-06-01 | 2026-06-01 | 2026-06-01 | — | out of scope this quarter |
| F-5 | bug | forms | Double submit | done | P1 | 2026-06-01 | 2026-06-01 | 2026-06-01 | — | verified: commit abc1234 |
EOF
echo "# UX Methodology" > "$A/ux/00-methodology.md"
echo "# Changelog" > "$A/ux/00-changelog.md"
printf -- '---\ntitle: "UX audit — first pass"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$A/ux/2026-06-01-first-pass/index.md"
printf '# Findings\n\n- **F-1** — token in URL\n' > "$A/ux/2026-06-01-first-pass/findings.md"

# Standalone one-shot run at the audits root (canon §Standalone) — never a violation.
mkdir -p "$A/2026-06-15-usage-retro"
printf -- '---\ntitle: "Usage retro"\nstatus: done\ncreated: 2026-06-15\nupdated: 2026-06-15\nmethodology: standalone\n---\n' > "$A/2026-06-15-usage-retro/index.md"

out="$(bash "$SCRIPTS/validate-audit.sh" --json "$A" 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] || fail "canon tree should validate clean (rc=$rc): $(printf '%s' "$out" | tr '\n' ' ' | head -c 300)"
count() { printf '%s' "$out" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d$1)" 2>/dev/null; }
[[ "$(count "['findings_in_inventory']")" == "5" ]] || fail "expected 5 canon findings parsed, got $(count "['findings_in_inventory']")"
[[ "$(count "['stats']['open']")" == "1" ]]    || fail "open count: expected 1, got $(count "['stats']['open']")"
[[ "$(count "['stats']['doing']")" == "1" ]]   || fail "doing count: expected 1, got $(count "['stats']['doing']")"
[[ "$(count "['stats']['done']")" == "2" ]]    || fail "done count: expected 2, got $(count "['stats']['done']")"
[[ "$(count "['stats']['dropped']")" == "1" ]] || fail "dropped count: expected 1, got $(count "['stats']['dropped']")"

# A bare `done` with neither Escalated To nor Notes evidence is a violation.
mkdir -p "$A/security"
cat > "$A/security/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| S-1 | bug | api | Bare done no evidence | done | P1 | 2026-06-01 | 2026-06-01 | 2026-06-01 | — | — |
EOF
echo "# m" > "$A/security/00-methodology.md"; echo "# c" > "$A/security/00-changelog.md"
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 && fail "bare done without Escalated To/Notes should be a violation"
out2="$(bash "$SCRIPTS/validate-audit.sh" --json "$A" 2>/dev/null || true)"
printf '%s' "$out2" | grep -q "S-1" || fail "violation should name S-1"

# Legacy status vocabulary reads as a WARNING (mapped, not a crash / not a violation).
cat > "$A/security/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| S-1 | bug | api | Legacy triaged row | triaged | P1 | 2026-06-01 | 2026-06-01 | 2026-06-01 | — | — |
EOF
out3="$(bash "$SCRIPTS/validate-audit.sh" --json "$A" 2>/dev/null)"; rc=$?
[[ $rc -eq 0 ]] || fail "legacy vocab must not be fatal (rc=$rc)"
printf '%s' "$out3" | grep -qi "legacy status" || fail "expected a legacy-status warning mentioning migration"

# mark_row_escalated writes base vocab + ISO dates + the marker verbatim.
. "$SCRIPTS/_lib.sh"
mark_row_escalated "$A/ux/00-inventory.md" F-1 "backlog/$TODAY-fix-token"
row="$(grep '| F-1 ' "$A/ux/00-inventory.md")"
printf '%s' "$row" | grep -q "| done |" || fail "mark_row_escalated: status should be 'done', row: $row"
printf '%s' "$row" | grep -q "backlog/$TODAY-fix-token" || fail "mark_row_escalated: marker not written verbatim"
printf '%s' "$row" | grep -q "$TODAY" || fail "mark_row_escalated: ISO date missing"
if printf '%s' "$row" | grep -qE '[0-9]{8}'; then fail "mark_row_escalated: legacy YYYYMMDD date written: $row"; fi
printf '%s' "$row" | grep -q "2026-06-01, $TODAY" || fail "mark_row_escalated: Audit Runs should append ISO date, row: $row"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon layout validation, base vocab counts, done-evidence rule, legacy warning, ISO escalation"
