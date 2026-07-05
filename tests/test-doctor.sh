#!/usr/bin/env bash
# test-doctor.sh — install.sh --doctor, against fixture ~/.aidex + ~/.claude
# trees pointed at via AIDEX_DIR/CLAUDE_DIR env overrides.
#
# Scenarios:
#   (a) healthy fixture           -> exit 0, all PASS
#   (b) broken symlink            -> exit 1, names the link
#   (c) missing exec bit          -> exit 1, names the file
#   (d) manifest entry deleted    -> exit 1
#   (e) real install smoke        -> runs without crashing, report shape ok
#
# Run with: bash tests/test-doctor.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
A="$TMP/aidex"
C="$TMP/claude"

make_fixture() {
  rm -rf "$A" "$C"
  mkdir -p "$A/skills/skill-a/scripts" "$A/hooks" "$C/skills"
  echo "echo hi" > "$A/skills/skill-a/scripts/x.sh"
  chmod +x "$A/skills/skill-a/scripts/x.sh"
  echo "echo router" > "$A/hooks/aidex-router.sh"
  echo "echo durability" > "$A/hooks/durability-run.sh"
  chmod +x "$A/hooks/aidex-router.sh" "$A/hooks/durability-run.sh"
  printf 'skills/skill-a\nhooks/aidex-router.sh\nhooks/durability-run.sh\n' > "$A/.manifest"
  echo "0.20.0" > "$A/.version"
  ln -s "$A/skills/skill-a" "$C/skills/skill-a"
}

run_doctor() {
  (AIDEX_DIR="$A" CLAUDE_DIR="$C" bash "$REPO_ROOT/install.sh" --doctor 2>&1)
}

# ---------- (a) healthy fixture ----------
make_fixture
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "(a) healthy fixture: expected exit 0, got $rc"
echo "$out" | grep -q "^FAIL" && fail "(a) healthy fixture: unexpected FAIL line(s)"
echo "$out" | grep -qi "all checks passed" || fail "(a) healthy fixture: missing pass summary"

# ---------- (b) broken symlink ----------
make_fixture
rm "$A/skills/skill-a/scripts/x.sh" # keep symlink target dir but break a different link
mkdir -p "$A/skills/skill-a/scripts"
echo "echo hi" > "$A/skills/skill-a/scripts/x.sh"
chmod +x "$A/skills/skill-a/scripts/x.sh"
rm -rf "$A/skills/skill-ghost"
mkdir -p "$A/skills/skill-ghost"
ln -s "$A/skills/skill-ghost" "$C/skills/skill-ghost"
rm -rf "$A/skills/skill-ghost" # target now missing -> dangling symlink
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(b) broken symlink: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*broken symlink" || fail "(b) broken symlink: missing broken-symlink FAIL line"
echo "$out" | grep -q "skill-ghost" || fail "(b) broken symlink: did not name the broken link"

# ---------- (c) missing exec bit ----------
make_fixture
chmod -x "$A/skills/skill-a/scripts/x.sh"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(c) missing exec bit: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*non-executable" || fail "(c) missing exec bit: missing non-executable FAIL line"
echo "$out" | grep -q "x.sh" || fail "(c) missing exec bit: did not name the offending file"

# ---------- (d) manifest entry pointing to a deleted file ----------
make_fixture
rm -rf "$A/skills/skill-a"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(d) manifest entry deleted: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*manifest entries missing" || fail "(d) manifest entry deleted: missing manifest FAIL line"
echo "$out" | grep -q "skills/skill-a" || fail "(d) manifest entry deleted: did not name the missing entry"

# ---------- (e) real install smoke ----------
out="$(bash "$REPO_ROOT/install.sh" --doctor 2>&1)"; rc=$?
[[ "$rc" -eq 0 || "$rc" -eq 1 ]] || fail "(e) real install smoke: unexpected exit $rc"
echo "$out" | grep -q "aidex doctor" || fail "(e) real install smoke: missing report header"
echo "$out" | grep -qE "PASS:|FAIL:" || fail "(e) real install smoke: no PASS/FAIL lines in report"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — doctor reports version/symlinks/exec-bits/python3/manifest/hooks; exits 0 healthy, 1 on any failure"
