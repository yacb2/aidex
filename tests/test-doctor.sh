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
#   (f) stale .version            -> exit 1, reports the mismatch
#
# Run with: bash tests/test-doctor.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Derived, never hard-coded (drift repair 2026-07-24): the fixture used to pin
# .version to a literal "0.20.0", so scenario (a) went silently red the moment
# install.sh's VERSION was bumped past it — the fixture was red from the first
# release after caffcad (2026-07-05) until this repair. Any value another file
# owns must be read from that file, or the test rots on the owner's next edit.
REPO_VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$REPO_ROOT/install.sh" | head -1)"
[[ -n "$REPO_VERSION" ]] || { echo "FAIL: could not parse VERSION from install.sh"; exit 1; }
REPO_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$REPO_COMMIT" ]] || { echo "FAIL: could not read HEAD sha"; exit 1; }

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
  # A rule: copied into ~/.aidex/rules/ AND symlinked into ~/.claude/rules/, which is
  # the only surface Claude Code loads. Both halves are part of a healthy install.
  mkdir -p "$A/rules" "$C/rules"
  echo "# a rule" > "$A/rules/aidex-demo.md"
  ln -s "$A/rules/aidex-demo.md" "$C/rules/aidex-demo.md"
  printf 'skills/skill-a\nhooks/aidex-router.sh\nhooks/durability-run.sh\nrules/aidex-demo.md\n' > "$A/.manifest"
  echo "$REPO_VERSION" > "$A/.version"
  echo "$REPO_COMMIT" > "$A/.commit"
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

# ---------- (g) a manifest rule that never got symlinked must FAIL ----------
# Regression (deep audit 2026-07-25): create_symlink refuses to clobber an existing
# ~/.claude/rules/<name>.md (correct — it must not eat the user's file), warns once, and
# moves on. The rule then never loads in ANY session, yet it stays listed in .manifest and
# check 5 only tests `[ -e "$AIDEX_DIR/$item" ]` — which passes, because the COPY exists.
# run_doctor contained zero mentions of rules, so it reported "all checks passed" for an
# install whose always-on rules were silently absent. Only 1 of the 3 shipped rules carries
# the aidex- prefix, so generic names like autonomy.md are the likely collisions.
make_fixture
rm "$C/rules/aidex-demo.md"                      # the clobber-skip outcome
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(g) unlinked rule: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*rule" || fail "(g) unlinked rule: no FAIL line about rules"
echo "$out" | grep -q "aidex-demo.md" || fail "(g) unlinked rule: did not name the unloaded rule"

# (g2) a rule shadowed by a real user file is the same defect, and must also fail.
make_fixture
rm "$C/rules/aidex-demo.md"
echo "# the user's own file of the same name" > "$C/rules/aidex-demo.md"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(g2) shadowed rule: expected exit 1, got $rc"
echo "$out" | grep -q "aidex-demo.md" || fail "(g2) shadowed rule: did not name the shadowed rule"

# (g3) the healthy fixture must still pass — the new check must not cry wolf.
make_fixture
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "(g3) healthy rules: new check regressed the healthy fixture (rc=$rc)"
echo "$out" | grep -qi "rule" || fail "(g3) healthy rules: doctor does not report on rules at all"

# ---------- (f) stale .version still reports a mismatch ----------
# Guards the (a) repair: deriving the fixture version from install.sh makes (a)
# green forever, which would also hide a genuinely broken version check. This
# asserts the check still fires, so the repair cannot mask what it repairs.
make_fixture
echo "0.0.1-stale" > "$A/.version"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(f) stale version: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*version mismatch" || fail "(f) stale version: missing version-mismatch FAIL line"
echo "$out" | grep -q "0.0.1-stale" || fail "(f) stale version: did not name the installed version"
echo "$out" | grep -q "$REPO_VERSION" || fail "(f) stale version: did not name the repo version"

# ---------- (e) real install smoke ----------
out="$(bash "$REPO_ROOT/install.sh" --doctor 2>&1)"; rc=$?
[[ "$rc" -eq 0 || "$rc" -eq 1 ]] || fail "(e) real install smoke: unexpected exit $rc"
echo "$out" | grep -q "aidex doctor" || fail "(e) real install smoke: missing report header"
echo "$out" | grep -qE "PASS:|FAIL:" || fail "(e) real install smoke: no PASS/FAIL lines in report"

# ---------- (h) content drift: same version, different commit ----------
# VERSION only moves on a release, so a matching version says nothing about the
# commits that landed since. Without a commit marker, an install 19 commits stale
# and a current one are indistinguishable and doctor calls both healthy.
make_fixture
echo "deadbee" > "$A/.commit"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(h) content drift: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*drift" || fail "(h) content drift: missing drift FAIL line"
echo "$out" | grep -q "deadbee" || fail "(h) content drift: did not name the installed commit"
echo "$out" | grep -q "$REPO_COMMIT" || fail "(h) content drift: did not name the repo commit"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — doctor reports version/symlinks/exec-bits/python3/manifest/hooks; exits 0 healthy, 1 on any failure"
