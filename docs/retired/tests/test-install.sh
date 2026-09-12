#!/usr/bin/env bash
# test-install.sh — install.sh guards, in a fully isolated HOME + mini fixture repo.
#
# Since v0.40 the suite installs straight into ~/.claude/ as real files; there is
# no ~/.aidex/ layer. Guards under test:
#   G1 uninstall removes ONLY manifest entries: a skill of the user's sitting next
#      to the suite in ~/.claude/skills survives, and so does a name the suite
#      never claimed.
#   G2 interactive update (option 2): the manifest reflects what was ACTUALLY
#      installed/kept — declined new items stay out; declined removals stay in.
#   G3 copy_item excludes gitignored build junk (__pycache__/, *.pyc, .DS_Store).
#   G4 version-only bump refreshes the version marker on a no-change --update.
#   G5 only SHIPPED_HOOKS install, executable; hooks/eval/ and retired hooks do not.
#   G7 uninstalling with no manifest refuses loudly (BL-089).
#   G8 an unrecognized update choice changes nothing and does not report success.
#   G9 never clobber: a user directory that shares a suite skill's name is skipped,
#      left intact and kept out of the manifest.
#   G10 migration from the pre-0.40 layout: symlinks into ~/.aidex/ become copies,
#      the user's own linked skill is materialised, state moves to ~/.claude/aidex/,
#      and ~/.aidex/ is PARKED (renamed with a README) — never deleted.
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
C="$H/.claude"
MF="$C/aidex/manifest"

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
  echo "echo retired" > "$FIX/hooks/retired.sh"
  echo "echo eval" > "$FIX/hooks/eval/run-eval.sh"
  echo "x	y" > "$FIX/hooks/eval/cases.tsv"
}

export AIDEX_SHIPPED_HOOKS="h.sh"
run_install() { (cd "$FIX" && HOME="$H" bash install.sh "$@" </dev/null >/dev/null 2>&1); }
run_with_input() { local input="$1"; shift; (cd "$FIX" && printf '%s' "$input" | HOME="$H" bash install.sh "$@" >/dev/null 2>&1); }

# ---------- fresh install + G3 + G5 ----------
make_fixture
run_install || fail "fresh install exited non-zero"
[[ -d "$C/skills/skill-a" && ! -L "$C/skills/skill-a" ]] || fail "skill-a is not a real directory in ~/.claude/skills"
[[ -f "$C/rules/r.md" && ! -L "$C/rules/r.md" ]] || fail "rule is not a real file in ~/.claude/rules"
grep -qx "skills/skill-a" "$MF" || fail "manifest missing skills/skill-a"
grep -qx "rules/r.md" "$MF" || fail "manifest missing rules/r.md"
[[ -f "$C/aidex/version" ]] || fail "version marker missing"
[[ ! -e "$H/.aidex" ]] || fail "fresh install created a ~/.aidex layer"
if find "$C/skills" -name '__pycache__' -o -name '*.pyc' | grep -q .; then
  fail "G3: __pycache__/*.pyc junk copied into ~/.claude/skills"
fi
[[ -x "$C/skills/skill-a/scripts/x.sh" ]] || fail "skill script not executable after install"
grep -qx "hooks/h.sh" "$MF" || fail "G5: shipped hook missing from manifest"
[[ -x "$C/hooks/h.sh" ]] || fail "G5: shipped hook not installed executable"
[[ ! -e "$C/hooks/retired.sh" ]] || fail "G5: retired hook was installed"
[[ ! -e "$C/hooks/eval" ]] || fail "G5: hooks/eval was installed"

# ---------- G2a: declined NEW item must stay OUT of the manifest ----------
mkdir -p "$FIX/skills/skill-c"; echo "# c" > "$FIX/skills/skill-c/SKILL.md"
run_with_input "2
n
" --update
if grep -qx "skills/skill-c" "$MF"; then
  fail "G2a: declined new item skill-c was written to the manifest"
fi
[[ ! -d "$C/skills/skill-c" ]] || fail "G2a: declined new item was installed anyway"
rm -rf "$FIX/skills/skill-c"

# ---------- G2b: declined REMOVAL must stay IN the manifest (still installed) ----------
rm -rf "$FIX/skills/skill-b"
run_with_input "2
n
" --update
grep -qx "skills/skill-b" "$MF" \
  || fail "G2b: declined removal dropped skill-b from the manifest (invisible orphan)"
[[ -d "$C/skills/skill-b" ]] || fail "G2b: declined removal deleted skill-b anyway"

# ---------- G1: uninstall removes only what the manifest lists ----------
mkdir -p "$C/skills/my-personal"; echo "# mine" > "$C/skills/my-personal/SKILL.md"
echo "# my rule" > "$C/rules/mine.md"
run_with_input "1
" --uninstall
[[ -f "$C/skills/my-personal/SKILL.md" ]] || fail "G1: uninstall deleted a personal skill"
[[ -f "$C/rules/mine.md" ]] || fail "G1: uninstall deleted a personal rule"
[[ ! -e "$C/skills/skill-a" ]] || fail "G1: manifest-tracked skill-a should be removed"
[[ ! -e "$C/rules/r.md" ]] || fail "G1: manifest-tracked rule should be removed"
[[ ! -e "$C/hooks/h.sh" ]] || fail "G1: manifest-tracked hook should be removed"
[[ ! -e "$C/aidex" ]] || fail "G1: state dir should be gone after uninstall"

# ---------- G7: uninstalling with no manifest must fail loudly ----------
make_fixture
run_install || fail "G7: fresh install exited non-zero"
rm -f "$MF"
out="$( (cd "$FIX" && printf '1\n' | HOME="$H" bash install.sh --uninstall 2>&1) )"; rc=$?
[[ "$rc" -ne 0 ]] || fail "G7: uninstall with no manifest exited 0"
[[ "$out" == *"manifest missing"* ]] || fail "G7: no 'manifest missing' message: $out"
[[ -d "$C/skills/skill-a" ]] || fail "G7: removed files despite refusing to run"

# ---------- G4: version-only bump must refresh the marker on --update ----------
make_fixture
run_install || fail "G4: fresh install exited non-zero"
sed -i '' 's/^VERSION=.*/VERSION="9.9.9"/' "$FIX/install.sh"
run_install --update || fail "G4: no-change --update exited non-zero"
[[ "$(cat "$C/aidex/version" 2>/dev/null)" == "9.9.9" ]] \
  || fail "G4: version not refreshed on no-change update (got '$(cat "$C/aidex/version" 2>/dev/null)')"

# ---------- G8: an unrecognized update choice must not report success over a no-op ----------
make_fixture
run_install || fail "G8: fresh install exited non-zero"
before_version="$(cat "$C/aidex/version")"
echo "# a CHANGED" > "$FIX/skills/skill-a/SKILL.md"
sed -i '' 's/^VERSION=.*/VERSION="9.9.9"/' "$FIX/install.sh"
out="$( (cd "$FIX" && printf 'x\n' | HOME="$H" bash install.sh --update 2>&1) )"; rc=$?
[[ "$rc" -ne 0 ]] || fail "G8: unrecognized choice exited 0 over a no-op"
[[ "$out" != *"Updated to v"* ]] || fail "G8: reported 'Updated to v...' without installing anything"
[[ "$(cat "$C/aidex/version" 2>/dev/null)" == "$before_version" ]] \
  || fail "G8: stamped version on a choice that installed nothing"
[[ "$(cat "$C/skills/skill-a/SKILL.md")" == "# a" ]] \
  || fail "G8: installed content changed on an unrecognized choice"

# ---------- G9: never clobber a user directory that shares a suite name ----------
make_fixture
mkdir -p "$C/skills/skill-b"; echo "# the user's own skill-b" > "$C/skills/skill-b/SKILL.md"
out="$( (cd "$FIX" && HOME="$H" bash install.sh </dev/null 2>&1) )"
[[ "$(cat "$C/skills/skill-b/SKILL.md")" == "# the user's own skill-b" ]] || fail "G9: user's skill-b was overwritten"
grep -qx "skills/skill-b" "$MF" && fail "G9: a skipped user-owned name was written to the manifest"
[[ "$out" == *"skill-b"*"not aidex's"* ]] || fail "G9: skip was not reported: $out"
[[ -d "$C/skills/skill-a" ]] || fail "G9: the rest of the install did not proceed"

# ---------- G10: migration from the pre-0.40 layout ----------
make_fixture
A="$H/.aidex"
mkdir -p "$A/skills/skill-a/scripts" "$A/skills/skill-b" "$A/skills/theirs" "$A/rules" "$A/hooks" "$A/backups/proj" "$C/skills" "$C/rules"
echo "# old a" > "$A/skills/skill-a/SKILL.md"; echo "# old b" > "$A/skills/skill-b/SKILL.md"
echo "# theirs, not a suite item" > "$A/skills/theirs/SKILL.md"
echo "# old rule" > "$A/rules/r.md"
echo "snap" > "$A/backups/proj/x"
echo '{}' > "$A/.census-trust"
printf 'skills/skill-a\nskills/skill-b\nrules/r.md\nhooks/h.sh\n' > "$A/.manifest"
echo "0.39.0" > "$A/.version"
ln -s "$A/skills/skill-a" "$C/skills/skill-a"
ln -s "$A/skills/skill-b" "$C/skills/skill-b"
ln -s "$A/skills/theirs" "$C/skills/theirs"
ln -s "$A/rules/r.md" "$C/rules/r.md"
run_install --update || fail "G10: --update over a legacy layout exited non-zero"
[[ -d "$C/skills/skill-a" && ! -L "$C/skills/skill-a" ]] || fail "G10: skill-a is still a symlink"
[[ "$(cat "$C/skills/skill-a/SKILL.md")" == "# a" ]] || fail "G10: skill-a was not refreshed from the repo"
[[ -f "$C/rules/r.md" && ! -L "$C/rules/r.md" ]] || fail "G10: rule is still a symlink"
[[ -d "$C/skills/theirs" && ! -L "$C/skills/theirs" ]] || fail "G10: the user's own linked skill was not materialised"
[[ "$(cat "$C/skills/theirs/SKILL.md")" == "# theirs, not a suite item" ]] || fail "G10: materialised skill lost its content"
[[ ! -e "$A" ]] || fail "G10: ~/.aidex still present after migration"
parked="$(ls -d "$H"/.aidex-to-delete-* 2>/dev/null | head -1)"
[[ -n "$parked" ]] || fail "G10: ~/.aidex was not parked as ~/.aidex-to-delete-<date>"
[[ -f "$parked/README.txt" ]] || fail "G10: parked directory has no README"
[[ -f "$parked/skills/theirs/SKILL.md" ]] || fail "G10: parking lost content (it must move, never delete)"
[[ -f "$C/aidex/census-trust" ]] || fail "G10: census-trust not moved to the state dir"
[[ -f "$C/aidex/backups/proj/x" ]] || fail "G10: backups not moved to the state dir"
grep -qx "skills/skill-a" "$MF" && grep -qx "rules/r.md" "$MF" && grep -qx "hooks/h.sh" "$MF" \
  || fail "G10: new manifest incomplete: $(cat "$MF" 2>/dev/null)"
grep -qx "skills/theirs" "$MF" && fail "G10: the user's materialised skill was claimed by the manifest"
run_install --doctor || fail "G10: doctor is not green right after migration"

# ---------- G11: a pre-existing BYTE-IDENTICAL copy is adopted, not skipped ----------
# The depth hook lived in ~/.claude/hooks/ as a by-hand copy before it shipped; a
# differing file is the user's (G9), an identical one is this very item.
make_fixture
mkdir -p "$C/hooks"; cp "$FIX/hooks/h.sh" "$C/hooks/h.sh"
run_install || fail "G11: install exited non-zero"
grep -qx "hooks/h.sh" "$MF" || fail "G11: identical pre-existing hook was not adopted into the manifest"
[[ -x "$C/hooks/h.sh" ]] || fail "G11: adopted hook not executable"

# ---------- G12: --update adopts an identical item that is outside the manifest ----------
# Field case 2026-08-28: the depth hook already sat in ~/.claude/hooks/ as a by-hand
# copy; the updater diffed it, saw "unchanged" and never put it under the manifest.
make_fixture
run_install || fail "G12: fresh install exited non-zero"
grep -v '^hooks/' "$MF" > "$MF.tmp" && mv "$MF.tmp" "$MF"      # simulate an unowned identical hook
run_install --update || fail "G12: --update exited non-zero"
grep -qx "hooks/h.sh" "$MF" || fail "G12: --update did not adopt the identical unmanaged hook"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — real copies in ~/.claude, pycache excluded, manifest reflects choices, user files never clobbered or removed, shipped hooks only, legacy layout migrated and parked"
