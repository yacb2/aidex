#!/usr/bin/env bash
# test-doctor.sh — install.sh --doctor, against a fixture ~/.claude tree pointed at
# via CLAUDE_DIR (and an absent legacy dir via AIDEX_DIR).
#
# Scenarios:
#   (a) healthy fixture               -> exit 0, all PASS
#   (b) manifest entry is a symlink   -> exit 1, names it (the old layout)
#   (c) missing exec bit              -> exit 1, names the file
#   (d) manifest entry deleted        -> exit 1
#   (e) real install smoke            -> runs without crashing, report shape ok
#   (f) stale version                 -> exit 1, reports the mismatch
#   (g) rule missing from ~/.claude/rules -> exit 1, names the rule
#   (h) content drift (same version, other commit) -> exit 1
#   (i) legacy ~/.aidex still present -> exit 1
#   (j) unmanaged aidex-* skill dir   -> exit 1, names it
#
# Run with: bash tests/test-doctor.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

# Derived, never hard-coded: a fixture pinned to a literal version goes red on the
# next release (drift repair 2026-07-24).
REPO_VERSION="$(sed -n 's/^VERSION="\(.*\)"/\1/p' "$REPO_ROOT/install.sh" | head -1)"
[[ -n "$REPO_VERSION" ]] || { echo "FAIL: could not parse VERSION from install.sh"; exit 1; }
REPO_COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$REPO_COMMIT" ]] || { echo "FAIL: could not read HEAD sha"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
C="$TMP/claude"
L="$TMP/legacy-absent"
# A fixture repo that ships hooks/h.sh, so the doctor's hook check has something to expect.
FIXREPO="$TMP/repo"; mkdir -p "$FIXREPO/hooks"; cp "$REPO_ROOT/install.sh" "$FIXREPO/install.sh"; echo "echo nudge" > "$FIXREPO/hooks/h.sh"
git -C "$FIXREPO" init -q && git -C "$FIXREPO" add -A && git -C "$FIXREPO" -c user.email=t@t -c user.name=t commit -qm fixture
FIX_COMMIT="$(git -C "$FIXREPO" rev-parse --short HEAD)"

make_fixture() {
  rm -rf "$C" "$L"
  mkdir -p "$C/skills/skill-a/scripts" "$C/rules" "$C/hooks" "$C/aidex"
  echo "echo hi" > "$C/skills/skill-a/scripts/x.sh"
  chmod +x "$C/skills/skill-a/scripts/x.sh"
  echo "# a rule" > "$C/rules/aidex-demo.md"
  echo "echo nudge" > "$C/hooks/h.sh"; chmod +x "$C/hooks/h.sh"
  printf 'skills/skill-a\nrules/aidex-demo.md\nhooks/h.sh\n' > "$C/aidex/manifest"
  echo "$REPO_VERSION" > "$C/aidex/version"
  echo "$FIX_COMMIT" > "$C/aidex/commit"
}

run_doctor() {
  (cd "$FIXREPO" && AIDEX_DIR="$L" CLAUDE_DIR="$C" AIDEX_SHIPPED_HOOKS="h.sh" bash install.sh --doctor 2>&1)
}

# ---------- (a) healthy fixture ----------
make_fixture
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 0 ]] || fail "(a) healthy fixture: expected exit 0, got $rc: $out"
echo "$out" | grep -q "^FAIL" && fail "(a) healthy fixture: unexpected FAIL line(s)"
echo "$out" | grep -qi "all checks passed" || fail "(a) healthy fixture: missing pass summary"

# ---------- (b) a manifest entry that is a symlink (old layout) ----------
make_fixture
mkdir -p "$TMP/elsewhere/skill-a"
rm -rf "$C/skills/skill-a"; ln -s "$TMP/elsewhere/skill-a" "$C/skills/skill-a"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(b) symlinked entry: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*symlinks, not copies" || fail "(b) symlinked entry: missing FAIL line"
echo "$out" | grep -q "skills/skill-a" || fail "(b) symlinked entry: did not name the entry"

# ---------- (c) missing exec bit ----------
make_fixture
chmod -x "$C/skills/skill-a/scripts/x.sh"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(c) missing exec bit: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*non-executable" || fail "(c) missing exec bit: missing non-executable FAIL line"
echo "$out" | grep -q "x.sh" || fail "(c) missing exec bit: did not name the offending file"

# ---------- (d) manifest entry pointing to a deleted directory ----------
make_fixture
rm -rf "$C/skills/skill-a"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(d) manifest entry deleted: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*manifest entries missing" || fail "(d) manifest entry deleted: missing manifest FAIL line"
echo "$out" | grep -q "skills/skill-a" || fail "(d) manifest entry deleted: did not name the missing entry"

# ---------- (g) a manifest rule absent from ~/.claude/rules must FAIL ----------
make_fixture
rm "$C/rules/aidex-demo.md"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(g) missing rule: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*rule" || fail "(g) missing rule: no FAIL line about rules"
echo "$out" | grep -q "aidex-demo.md" || fail "(g) missing rule: did not name the rule"

# ---------- (f) stale version ----------
make_fixture
echo "0.0.1-stale" > "$C/aidex/version"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(f) stale version: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*version mismatch" || fail "(f) stale version: missing version-mismatch FAIL line"
echo "$out" | grep -q "0.0.1-stale" || fail "(f) stale version: did not name the installed version"
echo "$out" | grep -q "$REPO_VERSION" || fail "(f) stale version: did not name the repo version"

# ---------- (h) content drift: same version, different commit ----------
make_fixture
echo "deadbee" > "$C/aidex/commit"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(h) content drift: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*drift" || fail "(h) content drift: missing drift FAIL line"
echo "$out" | grep -q "deadbee" || fail "(h) content drift: did not name the installed commit"

# ---------- (i) legacy ~/.aidex still present ----------
make_fixture
mkdir -p "$L/skills"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(i) legacy dir: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*legacy" || fail "(i) legacy dir: missing legacy FAIL line"
echo "$out" | grep -q -- "--update" || fail "(i) legacy dir: did not point at --update"

# ---------- (j) an aidex-* skill directory outside the manifest ----------
make_fixture
mkdir -p "$C/skills/aidex-ghost"; echo "# ghost" > "$C/skills/aidex-ghost/SKILL.md"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(j) unmanaged aidex-*: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*unmanaged aidex-\*" || fail "(j) unmanaged aidex-*: missing FAIL line"
echo "$out" | grep -q "aidex-ghost" || fail "(j) unmanaged aidex-*: did not name the directory"

# ---------- (k) a shipped hook outside the manifest must FAIL ----------
make_fixture
printf 'skills/skill-a\nrules/aidex-demo.md\n' > "$C/aidex/manifest"
out="$(run_doctor)"; rc=$?
[[ "$rc" -eq 1 ]] || fail "(k) unmanaged shipped hook: expected exit 1, got $rc"
echo "$out" | grep -q "FAIL:.*hook" || fail "(k) unmanaged shipped hook: missing FAIL line"
echo "$out" | grep -q "h.sh" || fail "(k) unmanaged shipped hook: did not name the hook"

# ---------- (e) real install smoke ----------
out="$(bash "$REPO_ROOT/install.sh" --doctor 2>&1)"; rc=$?
[[ "$rc" -eq 0 || "$rc" -eq 1 ]] || fail "(e) real install smoke: unexpected exit $rc"
echo "$out" | grep -q "aidex doctor" || fail "(e) real install smoke: missing report header"
echo "$out" | grep -qE "PASS:|FAIL:" || fail "(e) real install smoke: no PASS/FAIL lines in report"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — doctor reports version/drift/legacy/manifest/copies/exec-bits/python3/rules/hooks; exits 0 healthy, 1 on any failure"
