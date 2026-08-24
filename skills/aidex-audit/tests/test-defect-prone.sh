#!/usr/bin/env bash
# test-defect-prone.sh — the defect-prone section affected_tests.py renders when
# a change touches a file that measurably breaks (BL-133 criterion 2).
#
# aidex has no module-map.json, so a live diff here proves nothing either way:
# the fixture workspace IS the evidence. Scenarios:
#   (a) no data file          -> output byte-identical to the un-instrumented run
#   (b) module with no e2e    -> NO E2E, naming the module
#   (c) module with e2e specs -> counted as covered, not reported as a gap
#   (d) file in no module     -> "the gap cannot even be located"
#   (e) migration             -> suppressed and COUNTED, never silently dropped
#   (f) rows for another project only -> join failure named, never read as all-clear
#   (g) --command             -> byte-identical stdout and exit code
#   (h) --denominator typed   -> the empty-by-construction risk is called out
#   (i) non-flagged row       -> silent
#   (j) e2e mapped, no specs  -> still a gap
#   (k) worktree checkout     -> the -wt- suffix collapses onto the main prefix
#
# Run with: bash skills/aidex-audit/tests/test-defect-prone.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
FIXTURE="$TESTS_DIR/fixtures/coverage-workspace.sh"
AFFECTED="$SCRIPTS_DIR/coverage/affected_tests.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

DATA_REL=".context/audits/test-coverage/defect-prone.jsonl"

# write_data <ws> <prefix> [row-json...] — prefix is the project segment the
# producer stamps on every path; rows are appended verbatim.
write_data() {
  local ws="$1"; shift
  local prefix="$1"; shift
  mkdir -p "$ws/.context/audits/test-coverage"
  : > "$ws/$DATA_REL"
  local r
  for r in "$@"; do
    printf '%s\n' "${r//@/$prefix}" >> "$ws/$DATA_REL"
  done
}

META='{"meta": {"denominator": "all", "base_rate": 0.15, "ratio": 2.0, "min_touches": 8}}'

# ---------------------------------------------------------------------------
# (a) no data file -> the section is a silent no-op. Every project without a
#     producer run is in this state, so the un-instrumented output must not move.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
echo x >> "$WS/backend/apps/billing/views.py"
out_a="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "(a) missing data file should exit 0 (got $rc)"
echo "$out_a" | grep -qi 'defect-prone' \
  && fail "(a) no data file must render nothing: $out_a"
echo "$out_a" | grep -q '^\[billing\]$' \
  || fail "(a) the primary selection must still render: $out_a"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (b) a flagged change in a module with an EMPTY e2e glob list -> the gap is
#     named with the module, before the change lands.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/people/views.py", "share": 0.46, "bug": 6, "touches": 13, "flagged": true}'
echo x >> "$WS/backend/apps/people/views.py"
out_b="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_b" | grep -q 'DEFECT-PRONE CHANGES — 1 changed file' \
  || fail "(b) expected the defect-prone header: $out_b"
echo "$out_b" | grep -q 'above 2x the base bug rate (15.0%)' \
  || fail "(b) meta base rate/ratio should be stated: $out_b"
echo "$out_b" | grep -q 'NO E2E: module people — no e2e tests mapped' \
  || fail "(b) the gap should name the module: $out_b"
echo "$out_b" | grep -q 'BEFORE this change lands' \
  || fail "(b) expected the before-it-lands instruction: $out_b"
echo "$out_b" | grep -q 'disposable database, never dev' \
  || fail "(b) the E2E it asks for must respect rules/e2e-testing.md: $out_b"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (c) a flagged change in a module that DOES have e2e specs is not a gap. The
#     mechanism asks for the missing spec, not for a spec that exists.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/billing/views.py", "share": 0.44, "bug": 39, "touches": 88, "flagged": true}'
echo x >> "$WS/backend/apps/billing/views.py"
out_c="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_c" | grep -q 'covered: 1 flagged file already reached by e2e specs' \
  || fail "(c) a covered flagged file should count as covered: $out_c"
echo "$out_c" | grep -q 'NO E2E' \
  && fail "(c) a covered file must not be reported as a gap: $out_c"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (d) a flagged file matching no module -> the worse gap of the two, and it is
#     said so rather than dropped for being unmappable.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
mkdir -p "$WS/frontend/src/shared"
echo "export const x = 1;" > "$WS/frontend/src/shared/util.ts"
git -C "$WS/frontend" add -A
write_data "$WS" "$PFX" "$META" \
  '{"file": "@frontend/src/shared/util.ts", "share": 0.35, "bug": 38, "touches": 109, "flagged": true}'
out_d="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_d" | grep -q 'NO E2E: no module in the map — the gap cannot even be located' \
  || fail "(d) an unmapped flagged file should say the gap cannot be located: $out_d"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (e) a migration is not a surface an E2E spec can cover, so it is suppressed —
#     and COUNTED, per the house `waived: N` / `ignored: N` idiom.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
mkdir -p "$WS/backend/apps/billing/migrations"
echo "operations = []" > "$WS/backend/apps/billing/migrations/0035_rename.py"
git -C "$WS/backend" add -A
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/billing/migrations/0035_rename.py", "share": 0.48, "bug": 12, "touches": 25, "flagged": true}'
out_e="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_e" | grep -q 'suppressed: 1 migration' \
  || fail "(e) a flagged migration should be suppressed AND counted: $out_e"
echo "$out_e" | grep -q 'NO E2E' \
  && fail "(e) a migration must not be asked for an E2E spec: $out_e"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (f) rows that all belong to another project. The naive intersection returns
#     zero here, which reads as "nothing is defect-prone" and is really a broken
#     join — the exact implausibly-total-negative trap. Say so.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
write_data "$WS" "someone_else_ws/" "$META" \
  '{"file": "@backend/apps/people/views.py", "share": 0.46, "bug": 6, "touches": 13, "flagged": true}'
echo x >> "$WS/backend/apps/people/views.py"
out_f="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_f" | grep -q 'DEFECT-PRONE DATA — 1 row(s), none for this workspace' \
  || fail "(f) a prefix mismatch must be named, not read as an all-clear: $out_f"
echo "$out_f" | grep -q 'nothing was checked' \
  || fail "(f) the warning should say nothing was checked: $out_f"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (g) --command is consumed by a caller that RUNS it and branches on the exit
#     code. The advisory section must not reach it, in either.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
echo x >> "$WS/backend/apps/billing/views.py"   # flagged, covered by e2e
echo x >> "$WS/backend/apps/people/views.py"    # flagged, no e2e -> a gap
before_g="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"; rc_before=$?
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/billing/views.py", "share": 0.44, "bug": 39, "touches": 88, "flagged": true}' \
  '{"file": "@backend/apps/people/views.py", "share": 0.46, "bug": 6, "touches": 13, "flagged": true}'
after_g="$(python3 "$AFFECTED" "$WS" --command 2>/dev/null)"; rc_after=$?
err_g="$(python3 "$AFFECTED" "$WS" --command 2>&1 >/dev/null)"
[[ "$before_g" == "$after_g" ]] \
  || fail "(g) --command stdout changed with a data file present: $after_g"
[[ "$rc_before" -eq "$rc_after" ]] \
  || fail "(g) --command exit code moved from $rc_before to $rc_after"
echo "$after_g" | grep -qi 'defect-prone' \
  && fail "(g) the advisory section leaked into executed stdout: $after_g"
# Both routes into this tooling (aidex-bugfix step 6, plan-exec verification)
# call --command. A section only rendered in human mode would be a check nothing
# calls — the BL-135 defect again — so it must reach the reader here, on stderr.
echo "$err_g" | grep -q 'NO E2E: module people' \
  || fail "(g) --command must still surface the gap on stderr: $err_g"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (g2) --command exit 3 (nothing mapped) is the path where a flagged file
#      matching no module lands. Exiting without naming its gap would drop the
#      worst case of all.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
mkdir -p "$WS/frontend/src/shared"
echo "export const x = 1;" > "$WS/frontend/src/shared/util.ts"
git -C "$WS/frontend" add -A
write_data "$WS" "$PFX" "$META" \
  '{"file": "@frontend/src/shared/util.ts", "share": 0.35, "bug": 38, "touches": 109, "flagged": true}'
err_g2="$(python3 "$AFFECTED" "$WS" --command 2>&1 >/dev/null)"
python3 "$AFFECTED" "$WS" --command >/dev/null 2>&1
[[ $? -eq 3 ]] || fail "(g2) an all-unmapped diff should still exit 3"
echo "$err_g2" | grep -q 'the gap cannot even be located' \
  || fail "(g2) the gap must be named even on the exit-3 path: $err_g2"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (h) --denominator typed raises the base rate ~3x and can leave nothing
#     flagged. A data file built that way must not be consumed silently.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
write_data "$WS" "$PFX" \
  '{"meta": {"denominator": "typed", "base_rate": 0.485, "ratio": 2.0, "min_touches": 8}}' \
  '{"file": "@backend/apps/people/views.py", "share": 0.99, "bug": 12, "touches": 13, "flagged": true}'
echo x >> "$WS/backend/apps/people/views.py"
out_h="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_h" | grep -q 'denominator typed' \
  || fail "(h) a typed-denominator data file should be called out: $out_h"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (i) a row below the threshold is data, not a finding. Only `flagged` renders.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/people/views.py", "share": 0.12, "bug": 2, "touches": 17, "flagged": false}'
echo x >> "$WS/backend/apps/people/views.py"
out_i="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_i" | grep -qi 'defect-prone' \
  && fail "(i) a non-flagged row must render nothing: $out_i"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (j) e2e globs mapped but matching no tracked file. "The map mentions e2e" is
#     not coverage — the specs have to exist.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
python3 - "$WS" <<'PYJ'
import json, sys
p = sys.argv[1] + "/.context/audits/test-coverage/module-map.json"
m = json.load(open(p))
for mod in m["modules"]:
    if mod["id"] == "people":
        mod["tests"]["e2e"] = ["frontend/tests/e2e/people/**"]
json.dump(m, open(p, "w"), indent=2)
PYJ
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/people/views.py", "share": 0.46, "bug": 6, "touches": 13, "flagged": true}'
echo x >> "$WS/backend/apps/people/views.py"
out_j="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_j" | grep -q 'e2e mapped but no spec files exist' \
  || fail "(j) mapped-but-absent e2e specs should still be a gap: $out_j"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (k) a worktree checkout. The producer collapses `proj-wt-branch/x` onto
#     `proj/x`, so the consumer must strip the same suffix off its own basename
#     or every worktree silently matches nothing.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
WT="$WS-wt-feature"
mv "$WS" "$WT"
write_data "$WT" "$PFX" "$META" \
  '{"file": "@backend/apps/people/views.py", "share": 0.46, "bug": 6, "touches": 13, "flagged": true}'
echo x >> "$WT/backend/apps/people/views.py"
out_k="$(python3 "$AFFECTED" "$WT" 2>/dev/null)"
echo "$out_k" | grep -q 'NO E2E: module people' \
  || fail "(k) a worktree checkout should still match the collapsed prefix: $out_k"
rm -rf "$WT"

# ---------------------------------------------------------------------------
# (l) typed denominator and NOTHING flagged — the exact case the NOTE exists
#     for ("can leave nothing flagged"). It was emitted only after the
#     no-hits early return, so the empty-by-construction file was consumed
#     silently.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
write_data "$WS" "$PFX" \
  '{"meta": {"denominator": "typed", "base_rate": 0.485, "ratio": 2.0, "min_touches": 8}}' \
  '{"file": "@backend/apps/people/views.py", "share": 0.30, "bug": 4, "touches": 13, "flagged": false}'
echo x >> "$WS/backend/apps/people/views.py"
out_l="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_l" | grep -q 'denominator typed' \
  || fail "(l) a typed data file with nothing flagged must still be called out: $out_l"
rm -rf "$WS"

# ---------------------------------------------------------------------------
# (m) the e2e glob matches only a NON-spec helper (the fixture's routes.ts,
#     the NS 2026-08-23 case). "A tracked file matches the glob" is not a
#     spec; the matrix already filters by E2E_SPEC_RE and this must agree.
# ---------------------------------------------------------------------------
WS="$(bash "$FIXTURE")"
PFX="$(basename "$WS")/"
git -C "$WS/frontend" rm -q tests/e2e/billing/a.spec.ts
git -C "$WS/frontend" commit -qm "drop the spec, keep the route table"
write_data "$WS" "$PFX" "$META" \
  '{"file": "@backend/apps/billing/views.py", "share": 0.44, "bug": 39, "touches": 88, "flagged": true}'
echo x >> "$WS/backend/apps/billing/views.py"
out_m="$(python3 "$AFFECTED" "$WS" 2>/dev/null)"
echo "$out_m" | grep -q 'e2e mapped but no spec files exist' \
  || fail "(m) a non-spec file under the e2e glob is not cover: $out_m"
echo "$out_m" | grep -q 'covered:' \
  && fail "(m) zero specs must not read as covered: $out_m"
rm -rf "$WS"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — defect-prone: silent without data, gap naming (no-module/no-e2e/no-specs), covered, migration suppressed+counted, prefix-mismatch named, --command stdout untouched but routed on stderr (incl. exit 3), typed-denominator flagged (with and without hits), non-spec helper is not cover, worktree prefix collapse"
