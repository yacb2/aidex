#!/usr/bin/env bash
# test-coverage-config-check.sh — config_check.py against the
# coverage-config-check fixture workspace (house pattern, same style as
# test-coverage-sweep.sh). Guards the house failure mode: "checkers lie by
# omission" — a gate that passes violating input.
#
# Scenarios (each asserts on the reported KEY, not only on exit code):
#   (a) e2e-only          -> hasher_e2e present, hasher_pytest absent -> drift
#   (b) bad-settings-path -> hasher_pytest = unresolvable, not silently skipped
#   (c) two-entry-hasher  -> hasher_e2e present (second entry is not a violation)
#   (d) provider-no-pkg   -> coverage_provider absent despite the declaration
#   (e) clean             -> every key compliant, exit 0
#   (o) xdist-declared    -> a declared pytest-xdist is compliant, not drift
#   (p) own-checker       -> the checker's own tests/ is not project config
#
# Run with: bash skills/aidex-audit/tests/test-coverage-config-check.sh

set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPTS_DIR="$TESTS_DIR/../scripts"
FIXTURE="$TESTS_DIR/fixtures/coverage-config-check.sh"
CHECK="$SCRIPTS_DIR/coverage/config_check.py"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

WS="$(bash "$FIXTURE")"
trap 'rm -rf "$WS"' EXIT

run_one() {
  python3 "$CHECK" --root "$WS" "$1" --json
}

# ---------------------------------------------------------------------------
# (a) e2e-only: hasher_e2e present, hasher_pytest absent, overall drift
# ---------------------------------------------------------------------------
out_a="$(run_one e2e-only)"; rc_a=$?
v_e2e="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['e2e-only']['hasher_e2e']['value'])" "$out_a")"
[[ "$v_e2e" == "present" ]] || fail "(a) hasher_e2e should be present: $v_e2e"
v_pytest="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['e2e-only']['hasher_pytest']['value'])" "$out_a")"
[[ "$v_pytest" == "absent" ]] || fail "(a) hasher_pytest should be absent: $v_pytest"
[[ $rc_a -ne 0 ]] || fail "(a) e2e-only should report drift (exit != 0), got $rc_a"

# ---------------------------------------------------------------------------
# (b) bad-settings-path: hasher_pytest = unresolvable, never silently skipped
#     (a check keyed on config/settings/ would report this project 'absent'
#     or clean instead of naming the real problem)
# ---------------------------------------------------------------------------
out_b="$(run_one bad-settings-path)"
v_b="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['bad-settings-path']['hasher_pytest']['value'])" "$out_b")"
[[ "$v_b" == "unresolvable" ]] || fail "(b) hasher_pytest should be unresolvable, got: $v_b"

# ---------------------------------------------------------------------------
# (c) two-entry-hasher: MD5 first, PBKDF2 second -> hasher_e2e must be
#     'present', never penalized for the second entry
# ---------------------------------------------------------------------------
out_c="$(run_one two-entry-hasher)"
v_c="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['two-entry-hasher']['hasher_e2e']['value'])" "$out_c")"
[[ "$v_c" == "present" ]] || fail "(c) hasher_e2e should be present (MD5 first, second entry allowed), got: $v_c"

# ---------------------------------------------------------------------------
# (d) provider-no-pkg: coverage.provider declared, no @vitest/coverage-v8
#     package -> coverage_provider must be absent, not present
# ---------------------------------------------------------------------------
out_d="$(run_one provider-no-pkg)"
v_d="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['provider-no-pkg']['coverage_provider']['value'])" "$out_d")"
[[ "$v_d" == "absent" ]] || fail "(d) coverage_provider should be absent (declaration with no package), got: $v_d"

# ---------------------------------------------------------------------------
# (e) clean: every key compliant, exit 0
# ---------------------------------------------------------------------------
out_e="$(run_one clean)"; rc_e=$?
for key in hasher_pytest hasher_e2e vitest_include coverage_provider; do
  v="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['clean'][sys.argv[2]]['value'])" "$out_e" "$key")"
  [[ "$v" == "present" ]] || fail "(e) clean project's $key should be present, got: $v"
done
v_e_xdist="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['clean']['no_n_auto']['value'])" "$out_e")"
[[ "$v_e_xdist" == "compliant" ]] || fail "(e) clean project's no_n_auto should be compliant, got: $v_e_xdist"
[[ $rc_e -eq 0 ]] || fail "(e) clean project should exit 0, got $rc_e"

# ---------------------------------------------------------------------------
# (f) silent when clean: the non-JSON table run against ONLY the clean
# project prints nothing and exits 0 (compliance-sweep.sh's contract);
# --verbose restores the table even though nothing drifted.
# ---------------------------------------------------------------------------
out_f="$(python3 "$CHECK" --root "$WS" clean)"; rc_f=$?
[[ -z "$out_f" ]] || fail "(f) a clean-only run should print nothing, got: $out_f"
[[ $rc_f -eq 0 ]] || fail "(f) a clean-only run should exit 0, got $rc_f"
out_f_v="$(python3 "$CHECK" --root "$WS" clean --verbose)"
[[ -n "$out_f_v" ]] || fail "(f) --verbose should print the table even when clean"
echo "$out_f_v" | grep -q '^clean ' \
  || fail "(f) --verbose output should include the clean project's row: $out_f_v"

# ---------------------------------------------------------------------------
# (g) ci-n-auto: `-n auto` in .github/workflows/ci.yml must be drift — a walk
# that prunes hidden directories passes the one place CI config lives
# ---------------------------------------------------------------------------
out_g="$(run_one ci-n-auto)"
v_g="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ci-n-auto']['no_n_auto']['value'])" "$out_g")"
[[ "$v_g" == "drift" ]] || fail "(g) -n auto in .github/workflows must be drift, got: $v_g"

# ---------------------------------------------------------------------------
# (h) custom-hasher-first: a non-django.contrib hasher first must NOT read as
# MD5-first — the first list entry decides, whatever module it comes from
# ---------------------------------------------------------------------------
out_h="$(run_one custom-hasher-first)"
v_h="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['custom-hasher-first']['hasher_pytest']['value'])" "$out_h")"
[[ "$v_h" == "absent" ]] || fail "(h) custom hasher first must be absent, got: $v_h"
d_h="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['custom-hasher-first']['hasher_pytest']['detail'])" "$out_h")"
grep -q 'SlowCustomHasher' <<<"$d_h" || fail "(h) detail must name the real first hasher, got: $d_h"

# ---------------------------------------------------------------------------
# (i) ini-settings: the unquoted pytest.ini form is parsed, and pytest.ini
# wins over pyproject.toml (pytest's own precedence). The ini module puts a
# slow hasher first; the pyproject one puts MD5 first (#29)
# ---------------------------------------------------------------------------
out_i="$(run_one ini-settings)"
v_i="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ini-settings']['hasher_pytest']['value'])" "$out_i")"
[[ "$v_i" == "absent" ]] || fail "(i) unquoted pytest.ini DJANGO_SETTINGS_MODULE must be parsed and win: got $v_i"
d_i="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ini-settings']['hasher_pytest']['detail'])" "$out_i")"
grep -q 'PBKDF2PasswordHasher' <<<"$d_i" || fail "(i) detail must come from the pytest.ini module, got: $d_i"

# ---------------------------------------------------------------------------
# (j) req-dir: requirements/<env>.txt layout and a Dockerfile carrying
# PYTEST_ADDOPTS="-n auto" are both scanned (#30)
# ---------------------------------------------------------------------------
out_j="$(run_one req-dir)"
v_j="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['req-dir']['no_n_auto']['value'])" "$out_j")"
[[ "$v_j" == "drift" ]] || fail "(j) requirements/dev.txt + Dockerfile -n auto must be drift, got: $v_j"
h_j="$(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1])['req-dir']['no_n_auto']['hits']))" "$out_j")"
grep -q 'requirements/dev.txt' <<<"$h_j" || fail "(j) hits must name requirements/dev.txt: $h_j"
grep -q 'Dockerfile' <<<"$h_j" || fail "(j) hits must name the Dockerfile: $h_j"
grep -q 'pytest-xdist' <<<"$h_j" && fail "(j) a declared pytest-xdist must not be a hit: $h_j"

# ---------------------------------------------------------------------------
# (k) provider-mismatch: provider 'istanbul' declared with only
# @vitest/coverage-v8 installed -> absent, the package must match the
# declared provider (#31)
# ---------------------------------------------------------------------------
out_k="$(run_one provider-mismatch)"
v_k="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['provider-mismatch']['coverage_provider']['value'])" "$out_k")"
[[ "$v_k" == "absent" ]] || fail "(k) provider istanbul + coverage-v8 package must be absent, got: $v_k"

# ---------------------------------------------------------------------------
# (l) usage errors are exit 2, never silent-clean (#42) or a traceback (#62)
# ---------------------------------------------------------------------------
EMPTY="$(mktemp -d)"
err_l="$(python3 "$CHECK" --root "$EMPTY" 2>&1 >/dev/null)"; rc_l=$?
[[ $rc_l -eq 2 ]] || fail "(l) a root with no projects must exit 2, got $rc_l"
grep -q 'no projects' <<<"$err_l" || fail "(l) empty root must say 'no projects' on stderr: $err_l"
rmdir "$EMPTY"
err_l2="$(python3 "$CHECK" --root 2>&1 >/dev/null)"; rc_l2=$?
[[ $rc_l2 -eq 2 ]] || fail "(l) --root without a value must exit 2, got $rc_l2"
grep -q 'Traceback' <<<"$err_l2" && fail "(l) --root without a value must not traceback: $err_l2"

# ---------------------------------------------------------------------------
# (m) symlinked project dir: discovery must follow symlinks (BL-204) — a
#     symlink-built scratch workspace read vitest_include as a silent n/a
# ---------------------------------------------------------------------------
REAL_M="$(mktemp -d)"
mkdir -p "$REAL_M/frontend"
cat > "$REAL_M/frontend/vitest.config.ts" <<'EOF_M'
export default { test: { coverage: { include: ['src/**'] } } }
EOF_M
mkdir -p "$WS/symlinked-frontend"
ln -s "$REAL_M/frontend" "$WS/symlinked-frontend/frontend"
out_m="$(run_one symlinked-frontend)"
v_m="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['symlinked-frontend']['vitest_include']['value'])" "$out_m")"
[[ "$v_m" == "present" ]] || fail "(m) vitest_include must follow a symlinked dir, got: $v_m"
rm -rf "$REAL_M"

# ---------------------------------------------------------------------------
# (n) coverage_threshold (BL-200): INFORMATIONAL, never drift. threshold-set
# reports present on both halves; clean has no threshold anywhere and must
# report absent on both — while STILL exiting 0, because adopting a
# threshold is a per-project decision the audit records as a finding, not
# rollout drift.
# ---------------------------------------------------------------------------
out_n="$(run_one threshold-set)"; rc_n=$?
v_n_fu="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['threshold-set']['fail_under']['value'])" "$out_n")"
[[ "$v_n_fu" == "present" ]] || fail "(n) threshold-set fail_under should be present: $v_n_fu"
d_n_fu="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['threshold-set']['fail_under']['detail'])" "$out_n")"
grep -q 'pyproject.toml' <<<"$d_n_fu" || fail "(n) fail_under detail must name where it was found: $d_n_fu"
v_n_vt="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['threshold-set']['vitest_thresholds']['value'])" "$out_n")"
[[ "$v_n_vt" == "present" ]] || fail "(n) threshold-set vitest_thresholds should be present: $v_n_vt"
[[ $rc_n -eq 0 ]] || fail "(n) threshold-set should be clean overall, got exit $rc_n"

out_n2="$(run_one clean)"; rc_n2=$?
v_n2_fu="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['clean']['fail_under']['value'])" "$out_n2")"
[[ "$v_n2_fu" == "absent" ]] || fail "(n) clean has no fail_under anywhere, should be absent: $v_n2_fu"
v_n2_vt="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['clean']['vitest_thresholds']['value'])" "$out_n2")"
[[ "$v_n2_vt" == "absent" ]] || fail "(n) clean has no vitest thresholds, should be absent: $v_n2_vt"
[[ $rc_n2 -eq 0 ]] || fail "(n) an absent coverage threshold must NOT count as drift (exit 0), got $rc_n2"

# ---------------------------------------------------------------------------
# (o) xdist-declared (BL-236): pytest-xdist declared in uv.lock and
# requirements.txt with no `-n auto` anywhere is the shape
# decision/2026-08-24-xdist-per-project-worker-counts.md mandates -> compliant.
# The old rule read a locked dependency as drift and called four compliant
# fleet backends drifted.
# ---------------------------------------------------------------------------
out_o="$(run_one xdist-declared)"
v_o="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['xdist-declared']['no_n_auto']['value'])" "$out_o")"
[[ "$v_o" == "compliant" ]] || fail "(o) a declared pytest-xdist with no -n auto must be compliant, got: $v_o"
h_o="$(python3 -c "import json,sys; print('\n'.join(json.loads(sys.argv[1])['xdist-declared']['no_n_auto']['hits']))" "$out_o")"
[[ -z "$h_o" ]] || fail "(o) a declared pytest-xdist must produce no hits, got: $h_o"

# ---------------------------------------------------------------------------
# (p) own-checker (BL-236): a directory holding scripts/coverage/config_check.py
# is a checkout of this checker, so the tests/ beside it is the checker's own
# test data -> its literal `-n auto` is not project drift. aidex was flagged by
# its own fixture.
# ---------------------------------------------------------------------------
out_p="$(run_one own-checker)"
v_p="$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['own-checker']['no_n_auto']['value'])" "$out_p")"
[[ "$v_p" == "compliant" ]] || fail "(p) the checker's own tests/ must be skipped, got: $v_p"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $failures -eq 0 ]]; then
  echo "All coverage-config-check tests passed."
  exit 0
else
  echo "$failures test(s) failed."
  exit 1
fi
