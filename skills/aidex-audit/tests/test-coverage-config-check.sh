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
# Summary
# ---------------------------------------------------------------------------
if [[ $failures -eq 0 ]]; then
  echo "All coverage-config-check tests passed."
  exit 0
else
  echo "$failures test(s) failed."
  exit 1
fi
