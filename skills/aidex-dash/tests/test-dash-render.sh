#!/usr/bin/env bash
# test-dash-render.sh — the four dash renderers against a built temp `.context`
# fixture (house pattern, same assert style as test-coverage-matrix.sh): each
# renderer writes its sibling HTML with a GENERATED first line and the expected
# key values; re-running is idempotent (one GENERATED line, no duplicate
# sections); a hand-edit is overwritten; an unknown target and a missing source
# both exit 2 with a plain-text ERROR (never a traceback).
#
# Run with: bash skills/aidex-dash/tests/test-dash-render.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RENDER="$TESTS_DIR/../scripts/dash/render.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

WS="$(mktemp -d)"
trap 'rm -rf "$WS"' EXIT
CTX="$WS/.context"

# --- build the fixture ------------------------------------------------------
mkdir -p "$CTX/backlog/_archive" \
         "$CTX/plans/testplan" \
         "$CTX/audits/testaudit" \
         "$CTX/audits/test-coverage"

cat > "$CTX/backlog/2026-07-05-alpha.md" <<'EOF'
---
title: "Alpha backlog item"
id: BL-001
status: doing
priority: P1
type: bug
estimate: M
origin_ref: ""
---
# Alpha
EOF
cat > "$CTX/backlog/2026-07-05-beta.md" <<'EOF'
---
title: "Beta backlog item"
id: BL-002
status: open
priority: P2
estimate: S
origin_ref: ""
---
# Beta
EOF
cat > "$CTX/backlog/2026-07-05-gamma.md" <<'EOF'
---
title: "Gamma backlog item"
id: BL-003
status: done
priority: P3
estimate: L
origin_ref: ""
---
# Gamma
EOF
cat > "$CTX/backlog/_archive/2026-06-01-old.md" <<'EOF'
---
title: "Old archived item"
id: BL-000
status: done
priority: P2
estimate: S
---
# Old
EOF

cat > "$CTX/plans/testplan/00-index.md" <<'EOF'
---
title: "Test plan"
status: open
---
# Test plan

## Phases Overview

| Phase | File | Description | Tasks |
|---|---|---|---|
| 1 | [01-alpha.md](01-alpha.md) | Alpha phase | 3 |
| 2 | [02-beta.md](02-beta.md) | Beta phase | 2 |
EOF
cat > "$CTX/plans/testplan/01-alpha.md" <<'EOF'
# Phase 1
- [x] Task 1.1
- [x] Task 1.2
- [ ] Task 1.3
EOF
cat > "$CTX/plans/testplan/02-beta.md" <<'EOF'
# Phase 2
- [ ] Task 2.1
- [ ] Task 2.2
EOF

cat > "$CTX/audits/testaudit/00-inventory.md" <<'EOF'
---
title: "Audit Inventory"
status: active
---
# Inventory

| ID | Type | Module | Summary | Status | Severity |
|---|---|---|---|---|---|
| FIND-01 | bug | auth | Session token is not rotated on privilege change. | open | P1 |
| FIND-02 | gap | billing | No E2E coverage for the refund path. | done | P2 |
EOF

cat > "$CTX/audits/test-coverage/coverage-matrix.json" <<'EOF'
{
  "schema": "coverage-matrix/1",
  "generated": "2026-07-05T00:00:00",
  "modules": [
    {"id": "billing", "src_files": 596, "unit_files": 40, "unit_tests": 1181, "e2e_files": 61, "e2e_tests": 1296, "notes": "—"},
    {"id": "banking", "src_files": 226, "unit_files": 12, "unit_tests": 271, "e2e_files": 0, "e2e_tests": 0, "notes": "no E2E"}
  ],
  "totals": {"src_files": 822, "unit_files": 52, "unit_tests": 1452, "e2e_files": 61, "e2e_tests": 1296},
  "unmapped_test_files": ["backend/apps/x/tests/test_y.py"]
}
EOF

run() { python3 "$RENDER" "$WS" "$@"; }

# --- backlog ----------------------------------------------------------------
BL_HTML="$CTX/backlog/00-index.html"
run backlog >/dev/null || fail "backlog render exited non-zero"
[[ -f "$BL_HTML" ]] || fail "backlog: sibling 00-index.html not written"
head -1 "$BL_HTML" | grep -q '^<!-- GENERATED' || fail "backlog: first line missing GENERATED"
grep -q 'BL-001' "$BL_HTML" || fail "backlog: item id BL-001 missing"
grep -q 'P1 HIGH' "$BL_HTML" || fail "backlog: priority bar label missing"
grep -q '<th data-k="2" data-t="s">Type' "$BL_HTML" || fail "backlog: Type column header missing"
grep -q '>bug<' "$BL_HTML" || fail "backlog: type chip 'bug' missing"

# --- plans rollup -----------------------------------------------------------
PL_HTML="$CTX/plans/00-index.html"
run plans >/dev/null || fail "plans rollup render exited non-zero"
[[ -f "$PL_HTML" ]] || fail "plans: rollup 00-index.html not written"
head -1 "$PL_HTML" | grep -q '^<!-- GENERATED' || fail "plans rollup: first line missing GENERATED"
grep -q 'Test plan' "$PL_HTML" || fail "plans rollup: plan title missing"

# --- plan progress (multi-file) ---------------------------------------------
PP_HTML="$CTX/plans/testplan/00-index.html"
run plans testplan >/dev/null || fail "plan progress render exited non-zero"
[[ -f "$PP_HTML" ]] || fail "plans: testplan progress 00-index.html not written"
head -1 "$PP_HTML" | grep -q '^<!-- GENERATED' || fail "plan progress: first line missing GENERATED"
grep -q '2/3' "$PP_HTML" || fail "plan progress: phase 1 count 2/3 missing"
grep -q 'Alpha phase' "$PP_HTML" || fail "plan progress: phase description missing"

# --- audit ------------------------------------------------------------------
AU_HTML="$CTX/audits/testaudit/00-inventory.html"
run audit testaudit >/dev/null || fail "audit render exited non-zero"
[[ -f "$AU_HTML" ]] || fail "audit: 00-inventory.html not written"
head -1 "$AU_HTML" | grep -q '^<!-- GENERATED' || fail "audit: first line missing GENERATED"
grep -q 'FIND-01' "$AU_HTML" || fail "audit: finding id FIND-01 missing"

# --- coverage ---------------------------------------------------------------
CO_HTML="$CTX/audits/test-coverage/coverage-matrix.html"
run coverage >/dev/null || fail "coverage render exited non-zero"
[[ -f "$CO_HTML" ]] || fail "coverage: coverage-matrix.html not written"
head -1 "$CO_HTML" | grep -q '^<!-- GENERATED' || fail "coverage: first line missing GENERATED"
grep -q 'billing' "$CO_HTML" || fail "coverage: module row billing missing"

# --- idempotency: re-run is structurally identical --------------------------
run backlog >/dev/null || fail "backlog second run exited non-zero"
gen_count="$(grep -c '<!-- GENERATED' "$BL_HTML")"
[[ "$gen_count" -eq 1 ]] || fail "backlog: duplicate GENERATED header on re-run (count=$gen_count)"
wrap_count="$(grep -c 'class="wrap"' "$BL_HTML")"
[[ "$wrap_count" -eq 1 ]] || fail "backlog: duplicate page body on re-run (wrap count=$wrap_count)"
id_count="$(grep -c 'BL-001' "$BL_HTML")"
[[ "$id_count" -eq 1 ]] || fail "backlog: item BL-001 duplicated on re-run (count=$id_count)"

# --- hand-edit is overwritten on regeneration -------------------------------
printf '\n<!-- HAND EDITED — SHOULD NOT SURVIVE -->\n' >> "$BL_HTML"
run backlog >/dev/null || fail "backlog render exited non-zero after hand-edit"
grep -q 'HAND EDITED' "$BL_HTML" && fail "backlog: hand-edit survived regeneration"

# --- unknown target exits 2 -------------------------------------------------
run bogus >/dev/null 2>"$WS/err.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown target should exit 2 (got $rc)"
grep -q '^ERROR:' "$WS/err.txt" || fail "unknown target should print ERROR: on stderr"

# --- missing source exits 2 with ERROR: -------------------------------------
run audit does-not-exist >/dev/null 2>"$WS/err2.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "missing audit source should exit 2 (got $rc)"
grep -q '^ERROR:' "$WS/err2.txt" || fail "missing source should print ERROR: on stderr"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — four renderers (backlog/plans/audit/coverage), sibling paths, GENERATED header, key values, idempotency, hand-edit overwrite, unknown-target and missing-source exit 2"
