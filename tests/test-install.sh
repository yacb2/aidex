#!/usr/bin/env bash
# test-install.sh — install.sh guards, in a fully isolated HOME + mini fixture repo.
#
# Guards under test (audit/2026-07-02-suite-analysis, HIGH/MED):
#   G1 uninstall option 3: personal (non-manifest) files under ~/.aidex/ are never
#      silently destroyed, and NO dangling ~/.claude symlinks are left behind.
#   G2 interactive update (option 2): the manifest reflects what was ACTUALLY
#      installed/kept — declined new items stay out; declined removals stay in.
#   G3 copy_item excludes gitignored build junk (__pycache__/, *.pyc, .DS_Store).
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
           "$FIX/skills/skill-b" "$FIX/rules"
  cp "$REPO_ROOT/install.sh" "$FIX/install.sh"
  echo "# a" > "$FIX/skills/skill-a/SKILL.md"
  echo "echo hi" > "$FIX/skills/skill-a/scripts/x.sh"
  echo "junk" > "$FIX/skills/skill-a/scripts/__pycache__/x.cpython-310.pyc"
  echo "# b" > "$FIX/skills/skill-b/SKILL.md"
  echo "# rule" > "$FIX/rules/r.md"
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

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — pycache excluded, manifest reflects choices, personal files guarded, no dangling symlinks"
