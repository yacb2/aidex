#!/usr/bin/env bash
# test-coverage-playbook.sh — Phase 5 of the test-coverage plan: the 8th stock
# playbook + docs + validate integration.
#
# Covers:
#   - new-audit.sh test-coverage <slug> scaffolds the run and seeds
#     00-methodology.md from the test-coverage playbook (research delegation +
#     Django+Vue profile present, no unsubstituted {{placeholders}})
#   - the `coverage` short form normalizes to test-coverage/
#   - registry lockstep: the 04-playbooks table lists exactly one row per
#     methodology template file (the registry-lag guard)
#   - validate passes on a scaffolded + matrix-generated fixture workspace, and
#     flags a coverage-matrix.md that lacks the GENERATED header
#
# Run with: bash skills/aidex-audit/tests/test-coverage-playbook.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_DIR="$(cd "$TESTS_DIR/.." && pwd -P)"
SCRIPTS="$SKILL_DIR/scripts"
TEMPLATES="$SKILL_DIR/assets/templates/methodology"
PLAYBOOKS="$SKILL_DIR/references/04-playbooks.md"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# ---- 1. scaffold: new test-coverage seeds the playbook ----
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP" "${WS:-}"' EXIT
mkdir -p "$TMP/.context"
TODAY="$(date +%F)"

( cd "$TMP" && bash "$SCRIPTS/new-audit.sh" test-coverage first-pass ) >/dev/null 2>&1 \
  || fail "new test-coverage: exited non-zero"
M="$TMP/.context/audits/test-coverage"
[[ -d "$M/$TODAY-first-pass" ]] || fail "test-coverage run folder missing: $M/$TODAY-first-pass"
[[ -f "$M/$TODAY-first-pass/index.md" && -f "$M/$TODAY-first-pass/findings.md" ]] \
  || fail "test-coverage run folder incomplete"
[[ -f "$M/00-methodology.md" ]] || fail "test-coverage 00-methodology.md not seeded"
grep -qi 'aidex-research' "$M/00-methodology.md" \
  || fail "00-methodology.md missing the aidex-research delegation"
grep -q 'Vue Router' "$M/00-methodology.md" \
  || fail "00-methodology.md missing the Django+Vue+Playwright+Vitest profile"
if grep -rn '{{' "$M" >/dev/null 2>&1; then
  fail "unsubstituted {{placeholders}} in test-coverage scaffold: $(grep -rl '{{' "$M" | tr '\n' ' ')"
fi

# ---- 2. `coverage` alias normalizes into test-coverage/ ----
( cd "$TMP" && bash "$SCRIPTS/new-audit.sh" coverage second-pass ) >/dev/null 2>&1 \
  || fail "alias 'coverage': exited non-zero"
[[ -d "$M/$TODAY-second-pass" ]] || fail "alias 'coverage' did not normalize into audits/test-coverage/"
[[ ! -d "$TMP/.context/audits/coverage" ]] || fail "alias 'coverage' created a separate coverage/ folder"

# ---- 3. registry lockstep: one 04-playbooks row per template file ----
tpl_count="$(find "$TEMPLATES" -maxdepth 1 -name '*.md.template' | wc -l | tr -d ' ')"
row_count="$(grep -oE '/methodology/[a-z0-9-]+\.md\.template\)' "$PLAYBOOKS" | sort -u | wc -l | tr -d ' ')"
[[ "$tpl_count" -eq "$row_count" ]] \
  || fail "registry lag: $tpl_count methodology templates but $row_count linked rows in 04-playbooks.md"
grep -q 'test-coverage' "$PLAYBOOKS" || fail "04-playbooks.md does not mention test-coverage"

# ---- 4. validate: passes on a real fixture, flags a matrix without GENERATED ----
WS="$(bash "$TESTS_DIR/fixtures/coverage-workspace.sh")"
# Scaffold the test-coverage boards inside the fixture (module-map.json already there).
( cd "$WS" && bash "$SCRIPTS/new-audit.sh" test-coverage baseline ) >/dev/null 2>&1 \
  || fail "new test-coverage in fixture: exited non-zero"
# Generate the matrix (GENERATED header) from the fixture's module-map + git repos.
python3 "$SCRIPTS/coverage/coverage_matrix.py" "$WS" >/dev/null 2>&1 \
  || fail "coverage_matrix.py: exited non-zero in fixture"
MATRIX="$WS/.context/audits/test-coverage/coverage-matrix.md"
[[ -f "$MATRIX" ]] || fail "coverage-matrix.md not generated in fixture"

bash "$SCRIPTS/validate-audit.sh" "$WS/.context/audits" >/dev/null 2>&1
rc=$?
[[ "$rc" -eq 0 ]] || fail "validate should pass (exit 0) on scaffolded+generated fixture, got exit $rc"

# module-map.json parses via the lib's load CLI.
python3 "$SCRIPTS/coverage/_coverage_lib.py" load "$WS" >/dev/null 2>&1 \
  || fail "_coverage_lib.py load: rejected a valid module-map"

# Hand-create a matrix without the GENERATED header -> validate warns (still exit 0).
printf '# Coverage Matrix\n\nHand-written by a human, missing the required header.\n' > "$MATRIX"
out="$(bash "$SCRIPTS/validate-audit.sh" "$WS/.context/audits" 2>&1)"
rc=$?
[[ "$rc" -eq 0 ]] || fail "validate should stay exit 0 (warning, not error) for a hand-created matrix, got $rc"
echo "$out" | grep -qi 'GENERATED' \
  || fail "validate did not warn about the coverage-matrix.md missing the GENERATED header"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — test-coverage playbook scaffold, coverage alias, registry lockstep, validate pass + GENERATED-header warning"
