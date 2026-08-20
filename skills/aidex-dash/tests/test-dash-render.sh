#!/usr/bin/env bash
# test-dash-render.sh — the four dash renderers against a built temp `.context`
# fixture (house pattern, same assert style as test-coverage-matrix.sh): each
# renderer writes its sibling HTML with a GENERATED first line and the expected
# key values; re-running is idempotent (one GENERATED line, no duplicate
# sections); a hand-edit is overwritten; an unknown target and a missing source
# both exit 2 with a plain-text ERROR (never a traceback); an EMPTY active set
# (all plans/backlog items closed and archived, D-10) renders an empty board —
# only a missing directory is an error.
#
# Run with: bash skills/aidex-dash/tests/test-dash-render.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RENDER="$TESTS_DIR/../scripts/dash/render.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

WS="$(mktemp -d)"
WS2="$(mktemp -d)"
trap 'rm -rf "$WS" "$WS2"' EXIT
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

run() { python3 "$RENDER" "$1" "${@:2}"; }   # root-parameterized: one spelling for every invocation

# --- backlog ----------------------------------------------------------------
BL_HTML="$CTX/backlog/00-index.html"
run "$WS" backlog >/dev/null || fail "backlog render exited non-zero"
[[ -f "$BL_HTML" ]] || fail "backlog: sibling 00-index.html not written"
head -1 "$BL_HTML" | grep -q '^<!-- GENERATED' || fail "backlog: first line missing GENERATED"
grep -q 'BL-001' "$BL_HTML" || fail "backlog: item id BL-001 missing"
grep -q 'P1 HIGH' "$BL_HTML" || fail "backlog: priority bar label missing"
grep -q '<th data-k="2" data-t="s">Type' "$BL_HTML" || fail "backlog: Type column header missing"
grep -q '>bug<' "$BL_HTML" || fail "backlog: type chip 'bug' missing"

# --- plans rollup -----------------------------------------------------------
PL_HTML="$CTX/plans/00-index.html"
run "$WS" plans >/dev/null || fail "plans rollup render exited non-zero"
[[ -f "$PL_HTML" ]] || fail "plans: rollup 00-index.html not written"
head -1 "$PL_HTML" | grep -q '^<!-- GENERATED' || fail "plans rollup: first line missing GENERATED"
grep -q 'Test plan' "$PL_HTML" || fail "plans rollup: plan title missing"

# --- plan progress (multi-file) ---------------------------------------------
PP_HTML="$CTX/plans/testplan/00-index.html"
run "$WS" plans testplan >/dev/null || fail "plan progress render exited non-zero"
[[ -f "$PP_HTML" ]] || fail "plans: testplan progress 00-index.html not written"
head -1 "$PP_HTML" | grep -q '^<!-- GENERATED' || fail "plan progress: first line missing GENERATED"
grep -q '2/3' "$PP_HTML" || fail "plan progress: phase 1 count 2/3 missing"
grep -q 'Alpha phase' "$PP_HTML" || fail "plan progress: phase description missing"

# --- audit ------------------------------------------------------------------
AU_HTML="$CTX/audits/testaudit/00-inventory.html"
run "$WS" audit testaudit >/dev/null || fail "audit render exited non-zero"
[[ -f "$AU_HTML" ]] || fail "audit: 00-inventory.html not written"
head -1 "$AU_HTML" | grep -q '^<!-- GENERATED' || fail "audit: first line missing GENERATED"
grep -q 'FIND-01' "$AU_HTML" || fail "audit: finding id FIND-01 missing"

# --- coverage ---------------------------------------------------------------
CO_HTML="$CTX/audits/test-coverage/coverage-matrix.html"
run "$WS" coverage >/dev/null || fail "coverage render exited non-zero"
[[ -f "$CO_HTML" ]] || fail "coverage: coverage-matrix.html not written"
head -1 "$CO_HTML" | grep -q '^<!-- GENERATED' || fail "coverage: first line missing GENERATED"
grep -q 'billing' "$CO_HTML" || fail "coverage: module row billing missing"

# --- idempotency: re-run is structurally identical --------------------------
run "$WS" backlog >/dev/null || fail "backlog second run exited non-zero"
gen_count="$(grep -c '<!-- GENERATED' "$BL_HTML")"
[[ "$gen_count" -eq 1 ]] || fail "backlog: duplicate GENERATED header on re-run (count=$gen_count)"
wrap_count="$(grep -c 'class="wrap"' "$BL_HTML")"
[[ "$wrap_count" -eq 1 ]] || fail "backlog: duplicate page body on re-run (wrap count=$wrap_count)"
id_count="$(grep -c 'BL-001' "$BL_HTML")"
[[ "$id_count" -eq 1 ]] || fail "backlog: item BL-001 duplicated on re-run (count=$id_count)"

# --- hand-edit is overwritten on regeneration -------------------------------
printf '\n<!-- HAND EDITED — SHOULD NOT SURVIVE -->\n' >> "$BL_HTML"
run "$WS" backlog >/dev/null || fail "backlog render exited non-zero after hand-edit"
grep -q 'HAND EDITED' "$BL_HTML" && fail "backlog: hand-edit survived regeneration"

# --- unknown target exits 2 -------------------------------------------------
run "$WS" bogus >/dev/null 2>"$WS/err.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown target should exit 2 (got $rc)"
grep -q '^ERROR:' "$WS/err.txt" || fail "unknown target should print ERROR: on stderr"

# --- missing source exits 2 with ERROR: -------------------------------------
run "$WS" audit does-not-exist >/dev/null 2>"$WS/err2.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "missing audit source should exit 2 (got $rc)"
grep -q '^ERROR:' "$WS/err2.txt" || fail "missing source should print ERROR: on stderr"

# --- empty active set renders an empty board, not exit 2 --------------------
# (was: zero active plans / backlog items — the healthy all-archived end-state
# after a D-10 close — made the rollups die "no plans found" / "no backlog
# items found", leaving a stale board that still showed the closed item open)
#
# The archived fixtures are deliberate LEAK TRIPWIRES: archived bodies are
# glob-counted, never parsed, so their `status: open` changes nothing today —
# but if the live scan ever leaks into _archive/, they parse as open and the
# open/active/parsed tiles asserted at 0 below stop matching.
mkdir -p "$WS2/.context/plans/_archive" "$WS2/.context/backlog/_archive"
cat > "$WS2/.context/plans/_archive/2026-01-01-leak-tripwire.md" <<'EOF'
---
title: "Archived plan (leak tripwire)"
status: open
---
# Archived — glob-counted only; the open status is the tripwire
EOF
cat > "$WS2/.context/backlog/_archive/2026-01-01-bl-901-leak-tripwire.md" <<'EOF'
---
title: "Archived item (leak tripwire)"
id: BL-901
status: open
---
# Archived — glob-counted only; the open status is the tripwire
EOF

run "$WS2" plans >/dev/null 2>"$WS2/err.txt"; rc=$?
[[ "$rc" -eq 0 ]] || fail "plans: empty active set should render, not exit $rc ($(head -1 "$WS2/err.txt"))"
EPL="$WS2/.context/plans/00-index.html"
[[ -f "$EPL" ]] || fail "plans: empty board 00-index.html not written"
head -1 "$EPL" | grep -q '^<!-- GENERATED' || fail "plans empty board: first line missing GENERATED"
grep -q '<span class="n">0</span><span class="l">plans</span>' "$EPL" \
  || fail "plans empty board: plans=0 tile missing (archive leaked into live set?)"
grep -q '<span class="n">0</span><span class="l">open</span>' "$EPL" \
  || fail "plans empty board: open=0 tile missing"
grep -q '<span class="n">1</span><span class="l">archived</span>' "$EPL" \
  || fail "plans empty board: archived=1 tile missing"
grep -q 'leak tripwire' "$EPL" && fail "plans empty board: archived fixture rendered as live content"

run "$WS2" backlog >/dev/null 2>"$WS2/err2.txt"; rc=$?
[[ "$rc" -eq 0 ]] || fail "backlog: empty active set should render, not exit $rc ($(head -1 "$WS2/err2.txt"))"
EBL="$WS2/.context/backlog/00-index.html"
[[ -f "$EBL" ]] || fail "backlog: empty board 00-index.html not written"
head -1 "$EBL" | grep -q '^<!-- GENERATED' || fail "backlog empty board: first line missing GENERATED"
grep -q '<span class="n">0</span><span class="l">active items</span>' "$EBL" \
  || fail "backlog empty board: active=0 tile missing (archive leaked into live set?)"
grep -q '<span class="n">0</span><span class="l">live files parsed</span>' "$EBL" \
  || fail "backlog empty board: parsed=0 tile missing"
grep -q '<span class="n">1</span><span class="l">archived</span>' "$EBL" \
  || fail "backlog empty board: archived=1 tile missing"
grep -q 'BL-901' "$EBL" && fail "backlog empty board: archived fixture rendered as live content"

# the boundary stays: a MISSING plans/ or backlog/ directory (unlike an empty
# one) is still exit 2 — one nested root exercises both targets
mkdir -p "$WS2/no-plans/.context"
run "$WS2/no-plans" plans >/dev/null 2>"$WS2/no-plans/err.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "plans: missing plans directory should still exit 2 (got $rc)"
grep -q '^ERROR: no plans directory' "$WS2/no-plans/err.txt" || fail "plans: missing dir should print the designed ERROR:"
run "$WS2/no-plans" backlog >/dev/null 2>"$WS2/no-plans/err2.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "backlog: missing backlog directory should still exit 2 (got $rc)"
grep -q '^ERROR: no backlog directory' "$WS2/no-plans/err2.txt" || fail "backlog: missing dir should print the designed ERROR:"

# --- N files, zero parsed: die loudly, never a healthy zero board -----------
# (the guard removed in d4cfe74 was also the only detector of total parse
# failure: _items() dropped unparseable files silently, so a BOM/blank-led
# corpus rendered exit-0 byte-identical to the legitimate all-archived board)
BROKEN="$WS2/broken"
mkdir -p "$BROKEN/.context/backlog"
printf '\xef\xbb\xbf---\ntitle: "BOM item"\nid: BL-910\nstatus: open\npriority: P1\n---\n# BOM\n' \
  > "$BROKEN/.context/backlog/2026-01-01-bl-910-bom.md"
printf '\n---\ntitle: "Blank-led item"\nid: BL-911\nstatus: open\npriority: P1\n---\n# Blank\n' \
  > "$BROKEN/.context/backlog/2026-01-01-bl-911-blank.md"
run "$BROKEN" backlog >/dev/null 2>"$BROKEN/err.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "backlog: all-unparseable corpus should exit 2, not render a healthy board (got $rc)"
grep -q '^ERROR:.*none parsed' "$BROKEN/err.txt" || fail "backlog: total-parse-failure ERROR should say none parsed"
grep -q 'bl-910-bom.md' "$BROKEN/err.txt" || fail "backlog: total-parse-failure ERROR should name the first offender"
[[ ! -f "$BROKEN/.context/backlog/00-index.html" ]] || fail "backlog: total parse failure must not write a board"

# partial failure renders, but every skipped file is a NOTE on stderr
cat > "$BROKEN/.context/backlog/2026-01-02-bl-912-good.md" <<'EOF'
---
title: "Good item"
id: BL-912
status: open
priority: P2
---
# Good
EOF
run "$BROKEN" backlog >/dev/null 2>"$BROKEN/err2.txt"; rc=$?
[[ "$rc" -eq 0 ]] || fail "backlog: mixed corpus should render (got $rc)"
n_notes="$(grep -c '^NOTE: skipped (unparseable front matter)' "$BROKEN/err2.txt")"
[[ "$n_notes" -eq 2 ]] || fail "backlog: expected 2 NOTE lines for the 2 unparseable files (got $n_notes)"
grep -q 'BL-912' "$BROKEN/.context/backlog/00-index.html" || fail "backlog: parsed item missing from mixed board"

# --- glob-metacharacter roots: items must not vanish -------------------------
# (no glob.escape anywhere in the dash layer meant a root like foo-[bl-9]
# treated [...] as a pattern: every glob matched nothing and both boards
# rendered confidently empty — archived tiles zero too — where pre-d4cfe74
# the empty result at least died)
BR="$WS2/br-[bl-9]"
mkdir -p "$BR/.context/plans/_archive" "$BR/.context/backlog/_archive"
cat > "$BR/.context/plans/2026-02-01-live.md" <<'EOF'
---
title: "Live plan in bracketed root"
status: open
---
# Live
EOF
cat > "$BR/.context/plans/_archive/2026-01-01-old.md" <<'EOF'
---
title: "Archived plan"
status: done
---
# Old
EOF
cat > "$BR/.context/backlog/2026-02-01-bl-920-live.md" <<'EOF'
---
title: "Live item in bracketed root"
id: BL-920
status: open
priority: P1
estimate: S
---
# Live
EOF
cat > "$BR/.context/backlog/_archive/2026-01-01-bl-919-old.md" <<'EOF'
---
title: "Old archived item"
id: BL-919
status: done
---
# Old
EOF
run "$BR" plans >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] || fail "plans: bracketed root should render (got $rc)"
BRPL="$BR/.context/plans/00-index.html"
grep -q '<span class="n">1</span><span class="l">plans</span>' "$BRPL" \
  || fail "plans: bracketed root lost its live plan (glob metachars unescaped)"
grep -q '<span class="n">1</span><span class="l">archived</span>' "$BRPL" \
  || fail "plans: bracketed root lost its archived count"
run "$BR" backlog >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] || fail "backlog: bracketed root should render (got $rc)"
BRBL="$BR/.context/backlog/00-index.html"
grep -q 'BL-920' "$BRBL" || fail "backlog: bracketed root lost its live item (glob metachars unescaped)"
grep -q '<span class="n">1</span><span class="l">archived</span>' "$BRBL" \
  || fail "backlog: bracketed root lost its archived count"

# --- a stray _archive/00-index.md is never a live plan ----------------------
GH="$WS2/ghost"
mkdir -p "$GH/.context/plans/_archive"
cat > "$GH/.context/plans/_archive/00-index.md" <<'EOF'
---
title: "Archive ghost index"
status: open
---
# Ghost
EOF
cat > "$GH/.context/plans/2026-03-01-real.md" <<'EOF'
---
title: "Real live plan"
status: open
---
# Real
EOF
run "$GH" plans >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] || fail "plans: ghost fixture should render (got $rc)"
GHPL="$GH/.context/plans/00-index.html"
grep -q '<span class="n">1</span><span class="l">plans</span>' "$GHPL" \
  || fail "plans: stray _archive/00-index.md counted as a live plan"
grep -q '<span class="n">1</span><span class="l">open</span>' "$GHPL" \
  || fail "plans: stray _archive/00-index.md counted as open"
grep -q 'Archive ghost index' "$GHPL" && fail "plans: ghost index rendered as a live row"
grep -q '<span class="n">1</span><span class="l">archived</span>' "$GHPL" \
  || fail "plans: ghost index should count once, as archived"

# --- a plan directory without 00-index.md dies, never vanishes --------------
# (its phase files are invisible to both rollup globs, so pre-fix the plan
# silently disappeared from the board — plans=0 over live work)
NOIX="$WS2/noindex"
mkdir -p "$NOIX/.context/plans/2026-03-01-broken"
cat > "$NOIX/.context/plans/2026-03-01-broken/01-phase.md" <<'EOF'
# Phase 1
- [ ] Task
EOF
run "$NOIX" plans >/dev/null 2>"$NOIX/err.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "plans: index-less plan dir should exit 2, not render it invisible (got $rc)"
grep -q '^ERROR: plan directory without 00-index.md: 2026-03-01-broken/' "$NOIX/err.txt" \
  || fail "plans: index-less ERROR should name the directory"
[[ ! -f "$NOIX/.context/plans/00-index.html" ]] || fail "plans: index-less failure must not write a board"

# --- the resolved root is always visible on stderr ---------------------------
# (nearest-ancestor find_project_root can resolve to a stray .context-bearing
# subtree; with empty states now rendering instead of dying, the resolved
# root on stderr is the wrong-root tripwire — on success AND on error)
run "$WS2" plans >/dev/null 2>"$WS2/root.txt"
grep -Fxq "root: $WS2" "$WS2/root.txt" || fail "render: resolved root missing from stderr on success"
run "$WS2/no-plans" plans >/dev/null 2>"$WS2/no-plans/root.txt"
grep -Fxq "root: $WS2/no-plans" "$WS2/no-plans/root.txt" || fail "render: resolved root missing from stderr on error"

# --- a failed write never truncates the previous good board ------------------
# (open(out,'w') truncated in place: an I/O failure mid-write left a half
# file whose intact GENERATED first line still passed every first-line check)
run "$WS2" plans >/dev/null 2>&1 || fail "plans: pre-write render failed"
cp "$EPL" "$WS2/board-before.html"
( ulimit -f 1; run "$WS2" plans >/dev/null 2>"$WS2/ulimit-err.txt" ); rc=$?
[[ "$rc" -ne 0 ]] || fail "plans: write beyond ulimit should fail (got rc=0)"
cmp -s "$EPL" "$WS2/board-before.html" || fail "plans: failed write corrupted the previous good board"
stray="$(find "$WS2/.context/plans" -name '*.tmp' | wc -l | tr -d ' ')"
[[ "$stray" -eq 0 ]] || fail "plans: failed write left $stray .tmp file(s) behind"

# --- audit: zero data rows is a board, not a structural error ---------------
# (the old guard 'not headers or not rows' died on sparse data with a
# factually false message — the exact class d4cfe74 fixed, one renderer over;
# a D-10 cycle close archives every resolved row off the board legitimately)
mkdir -p "$WS/.context/audits/emptyaudit"
cat > "$WS/.context/audits/emptyaudit/00-inventory.md" <<'EOF'
---
title: "Audit Inventory"
status: active
---
# Inventory

| ID | Type | Module | Summary | Status | Severity |
|---|---|---|---|---|---|
EOF
run "$WS" audit emptyaudit >/dev/null 2>"$WS/err3.txt"; rc=$?
[[ "$rc" -eq 0 ]] || fail "audit: zero-row inventory should render, not exit $rc ($(grep '^ERROR:' "$WS/err3.txt" | head -1))"
EAU="$WS/.context/audits/emptyaudit/00-inventory.html"
[[ -f "$EAU" ]] && head -1 "$EAU" | grep -q '^<!-- GENERATED' || fail "audit: empty board missing or missing GENERATED"
grep -q '<span class="n">0</span><span class="l">findings</span>' "$EAU" \
  || fail "audit: zero-row inventory should show findings=0"

# --- audit: the template sentinel row is not a finding -----------------------
# (a fresh new-audit.sh scaffold rendered '1 findings / 1 resolved' while
# validate-audit.sh skips the same '^| —' row and reports 0 — two consumers
# of one canon disagreeing on a virgin scaffold)
mkdir -p "$WS/.context/audits/freshaudit"
cat > "$WS/.context/audits/freshaudit/00-inventory.md" <<'EOF'
---
title: "Audit Inventory"
status: active
---
# Inventory

| ID | Type | Module | Summary | Status | Severity |
|---|---|---|---|---|---|
| — | — | — | *No findings yet — first sweep pending.* | — | — |
EOF
run "$WS" audit freshaudit >/dev/null 2>&1; rc=$?
[[ "$rc" -eq 0 ]] || fail "audit: sentinel-only scaffold should render (got $rc)"
FAU="$WS/.context/audits/freshaudit/00-inventory.html"
grep -q '<span class="n">0</span><span class="l">findings</span>' "$FAU" \
  || fail "audit: sentinel row counted as a finding"
grep -q '<span class="n">0</span><span class="l">resolved</span>' "$FAU" \
  || fail "audit: sentinel row counted as resolved"

# the kept half of the split guard: a renamed required column still dies
mkdir -p "$WS/.context/audits/renamedaudit"
cat > "$WS/.context/audits/renamedaudit/00-inventory.md" <<'EOF'
---
title: "Audit Inventory"
status: active
---
# Inventory

| Identifier | Type | Module | Summary | Status | Severity |
|---|---|---|---|---|---|
| FIND-01 | bug | auth | Something. | open | P1 |
EOF
run "$WS" audit renamedaudit >/dev/null 2>"$WS/err4.txt"; rc=$?
[[ "$rc" -eq 2 ]] || fail "audit: renamed required column should still exit 2 (got $rc)"
grep -q '^ERROR: no findings table with ID/Status/Severity columns' "$WS/err4.txt" \
  || fail "audit: renamed-column ERROR message changed"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — four renderers (backlog/plans/audit/coverage), sibling paths, GENERATED header, key values, idempotency, hand-edit overwrite, unknown-target and missing-source exit 2, empty active set renders symmetrically (missing dirs still exit 2)"
