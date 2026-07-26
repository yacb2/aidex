#!/usr/bin/env bash
# test-install.sh — install.sh guards, in a fully isolated HOME + mini fixture repo.
#
# Guards under test (audit/2026-07-02-suite-analysis, HIGH/MED):
#   G1 uninstall option 3: personal (non-manifest) files under ~/.aidex/ are never
#      silently destroyed, and NO dangling ~/.claude symlinks are left behind.
#   G2 interactive update (option 2): the manifest reflects what was ACTUALLY
#      installed/kept — declined new items stay out; declined removals stay in.
#   G3 copy_item excludes gitignored build junk (__pycache__/, *.pyc, .DS_Store).
#   G5 hooks/ subdirectories (e.g. hooks/eval/) are collected as items, copied
#      into ~/.aidex/hooks/, their .sh made executable, and never symlinked.
#   G6 uninstall option 1 ("keeps ~/.aidex/ intact") keeps the manifest, so a
#      follow-up option 2 can still find what to remove; G6b the kept manifest is
#      not counted as personal content by option 3.
#   G7 uninstalling with no manifest refuses loudly instead of reporting success
#      over a no-op (audit/2026-07-25, BL-089).
#
# Run with: bash tests/test-install.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"
FIX="$TMP/repo"

make_fixture() {
  rm -rf "$FIX" "$H"
  mkdir -p "$H" "$FIX/skills/skill-a/scripts" "$FIX/skills/skill-a/scripts/__pycache__" \
           "$FIX/skills/skill-b" "$FIX/rules" "$FIX/hooks/eval"
  cp "$REPO_ROOT/install.sh" "$FIX/install.sh"
  echo "# a" > "$FIX/skills/skill-a/SKILL.md"
  echo "echo hi" > "$FIX/skills/skill-a/scripts/x.sh"
  echo "junk" > "$FIX/skills/skill-a/scripts/__pycache__/x.cpython-310.pyc"
  echo "# b" > "$FIX/skills/skill-b/SKILL.md"
  echo "# rule" > "$FIX/rules/r.md"
  echo "echo hook" > "$FIX/hooks/h.sh"
  echo "echo eval" > "$FIX/hooks/eval/run-eval.sh"
  echo "x	y" > "$FIX/hooks/eval/cases.tsv"
}

run_install() { (cd "$FIX" && HOME="$H" bash install.sh "$@" </dev/null >/dev/null 2>&1); }
run_with_input() { local input="$1"; shift; (cd "$FIX" && HOME="$H" printf '%s' "$input" | HOME="$H" bash install.sh "$@" >/dev/null 2>&1); }

# ---------- fresh install + G3 ----------
make_fixture
run_install || fail "fresh install exited non-zero"
[[ -L "$H/.claude/skills/skill-a" && -L "$H/.claude/skills/skill-b" ]] || fail "skill symlinks missing after install"
grep -qx "skills/skill-a" "$H/.aidex/.manifest" || fail "manifest missing skills/skill-a"
if find "$H/.aidex" -name '__pycache__' -o -name '*.pyc' | grep -q .; then
  fail "G3: __pycache__/*.pyc junk copied into ~/.aidex"
fi

# ---------- G5: hooks/ subdirectory installed, executable, never symlinked ----------
grep -qx "hooks/eval" "$H/.aidex/.manifest" || fail "G5: hooks/eval missing from manifest"
[[ -f "$H/.aidex/hooks/eval/cases.tsv" ]] || fail "G5: hooks/eval/cases.tsv not copied"
[[ -x "$H/.aidex/hooks/h.sh" ]] || fail "G5: hooks/h.sh not executable"
[[ -x "$H/.aidex/hooks/eval/run-eval.sh" ]] || fail "G5: hooks/eval/run-eval.sh not executable"
[[ ! -e "$H/.claude/hooks" ]] || fail "G5: hooks were symlinked into ~/.claude"

# ---------- G2a: declined NEW item must stay OUT of the manifest ----------
mkdir -p "$FIX/skills/skill-c"; echo "# c" > "$FIX/skills/skill-c/SKILL.md"
run_with_input "2
n
" --update
if grep -qx "skills/skill-c" "$H/.aidex/.manifest"; then
  fail "G2a: declined new item skill-c was written to the manifest"
fi
[[ ! -d "$H/.aidex/skills/skill-c" ]] || fail "G2a: declined new item was installed anyway"
rm -rf "$FIX/skills/skill-c"

# ---------- G2b: declined REMOVAL must stay IN the manifest (still installed) ----------
rm -rf "$FIX/skills/skill-b"
run_with_input "2
n
" --update
grep -qx "skills/skill-b" "$H/.aidex/.manifest" \
  || fail "G2b: declined removal dropped skill-b from the manifest (invisible orphan)"
[[ -d "$H/.aidex/skills/skill-b" ]] || fail "G2b: declined removal deleted skill-b anyway"

# ---------- G1: uninstall option 3 with personal content ----------
# Personal (non-manifest) skill living under ~/.aidex + its ~/.claude symlink.
mkdir -p "$H/.aidex/skills/my-personal"
echo "# mine" > "$H/.aidex/skills/my-personal/SKILL.md"
ln -s "$H/.aidex/skills/my-personal" "$H/.claude/skills/my-personal"

# Decline the personal purge: personal files must survive, no dangling links.
run_with_input "3
n
" --uninstall
[[ -f "$H/.aidex/skills/my-personal/SKILL.md" ]] || fail "G1: declined purge still deleted personal files"
[[ ! -e "$H/.aidex/skills/skill-a" ]] || fail "G1: manifest-tracked skill-a should be removed by option 3"
[[ -L "$H/.claude/skills/my-personal" && -e "$H/.claude/skills/my-personal" ]] \
  || fail "G1: personal symlink should survive intact when purge is declined"

# Accept the purge (explicit token, not a bare y): everything goes, and the
# personal symlink must NOT be left dangling.
run_with_input "3
delete
" --uninstall
[[ ! -d "$H/.aidex" ]] || fail "G1: accepted purge left ~/.aidex behind"
if [[ -L "$H/.claude/skills/my-personal" && ! -e "$H/.claude/skills/my-personal" ]]; then
  fail "G1: accepted purge left a DANGLING personal symlink in ~/.claude/skills"
fi

# ---------- G6: uninstall option 1 must keep the manifest ----------
# The menu promises "keeps ~/.aidex/ intact"; the manifest is what describes it.
# Deleting it there left options 2/3 removing 0 files and broke --doctor/--update.
make_fixture
run_install || fail "G6: fresh install exited non-zero"
run_with_input "1
" --uninstall
[[ -f "$H/.aidex/.manifest" ]] || fail "G6: option 1 deleted the manifest it promised to keep"
[[ ! -L "$H/.claude/skills/skill-a" ]] || fail "G6: option 1 left the symlink it was asked to remove"
[[ -d "$H/.aidex/skills/skill-a" ]] || fail "G6: option 1 removed files under ~/.aidex"
# The kept manifest is what makes a follow-up option 2 able to do its job.
run_with_input "2
" --uninstall
[[ ! -d "$H/.aidex/skills/skill-a" ]] || fail "G6: option 2 after option 1 removed nothing (stranded by a lost manifest)"

# ---------- G6b: option 3 on a clean tree still removes ~/.aidex ----------
# The kept manifest must not be mistaken for personal content.
make_fixture
run_install || fail "G6b: fresh install exited non-zero"
out="$( (cd "$FIX" && HOME="$H" printf '3\n' | HOME="$H" bash install.sh --uninstall 2>&1) )"
[[ ! -d "$H/.aidex" ]] || fail "G6b: option 3 kept ~/.aidex on a tree with nothing personal: $out"
[[ "$out" != *"PERSONAL"* ]] || fail "G6b: the kept manifest was reported as a personal file"

# ---------- G7: uninstalling with no manifest must fail loudly ----------
make_fixture
run_install || fail "G7: fresh install exited non-zero"
rm -f "$H/.aidex/.manifest"
out="$( (cd "$FIX" && HOME="$H" printf '3\ndelete\n' | HOME="$H" bash install.sh --uninstall 2>&1) )"; rc=$?
[[ "$rc" -ne 0 ]] || fail "G7: uninstall with no manifest exited 0"
[[ "$out" == *"manifest missing"* ]] || fail "G7: no 'manifest missing' message: $out"
[[ "$out" != *"Removing aidex-managed files"* ]] || fail "G7: printed removal headers over a no-op"
[[ -d "$H/.aidex/skills/skill-a" ]] || fail "G7: removed files despite refusing to run"

# ---------- G4: version-only bump must refresh ~/.aidex/.version on --update ----------
# A release commit that only bumps VERSION= produces zero item changes; the update's
# early "everything up to date" exit must still stamp the new version.
make_fixture
run_install || fail "G4: fresh install exited non-zero"
sed -i '' 's/^VERSION=.*/VERSION="9.9.9"/' "$FIX/install.sh"
run_install --update || fail "G4: no-change --update exited non-zero"
[[ "$(cat "$H/.aidex/.version" 2>/dev/null)" == "9.9.9" ]] \
  || fail "G4: .version not refreshed on no-change update (got '$(cat "$H/.aidex/.version" 2>/dev/null)')"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — pycache excluded, manifest reflects choices, personal files guarded, no dangling symlinks, version stamped on no-change update, hook subdirs installed executable"
