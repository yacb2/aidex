#!/usr/bin/env bash
# test-doctor.sh — scripts/doctor.sh, one cell per acceptance criterion of the
# doctor plan, each with a passing AND a failing fixture.
#
# Fully fixtured, house style of test-skill-overrides-check.sh: both roots are
# injected (--claude-dir, --plugin-root), so no assertion reads the machine's real
# ~/.claude. The one exception is deliberate and labelled F1: a single cell runs the
# doctor against THIS REPO's plugin root, because "the shipped tree is healthy" is
# the claim the 34 fixtured cells could not make — ten tracked scripts were mode
# 100644 and every cell stayed green (BL-428).
#
# The predecessor's cell list (docs/retired/tests/test-doctor.sh, scenarios a-j) is
# the reference; only the cells of the four kept checks are ported — version, drift,
# legacy dir, manifest and rules belong to the plugin manager now. Cells marked F2-F8
# are the adversarial review's findings, each written red before its fix.
#
# Run with: bash skills/aidex/tests/test-doctor.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOCTOR="$DIR/../scripts/doctor.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

[[ -x "$DOCTOR" ]] || { echo "FAIL: $DOCTOR is missing or not executable"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P="$TMP/plugin"    # the fixture plugin root
C="$TMP/claude"    # the fixture ~/.claude

mkskill() { mkdir -p "$1"; printf -- '---\nname: %s\n---\nbody\n' "$(basename "$1")" > "$1/SKILL.md"; }

hooks_json() {  # $1 = the hook path, relative to the plugin root
  cat > "$P/hooks/hooks.json" <<JSON
{
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "bash \\"\${CLAUDE_PLUGIN_ROOT}/$1\\"" } ] }
    ]
  }
}
JSON
}

make_fixture() {
  rm -rf "$P" "$C"
  # plugin root: two skills, one with a script; one wired hook.
  mkskill "$P/skills/skill-a"
  mkskill "$P/skills/skill-b"
  mkdir -p "$P/skills/skill-a/scripts" "$P/hooks"
  printf 'echo hi\n' > "$P/skills/skill-a/scripts/x.sh"; chmod +x "$P/skills/skill-a/scripts/x.sh"
  printf 'echo nudge\n' > "$P/hooks/h.sh"; chmod +x "$P/hooks/h.sh"
  hooks_json "hooks/h.sh"
  # a personal store with one skill of the user's own, which is never a finding.
  mkskill "$C/skills/my-own-skill"
}

settings() { printf '%s\n' "$1" > "$C/settings.json"; }
run() { bash "$DOCTOR" --claude-dir "$C" --plugin-root "$P" "$@" 2>&1; }

# A snapshot of every path under the two roots with its mode, size and mtime, plus
# the content hash of every file. Criterion 6 is "the script writes nothing", and a
# check that only compared names would miss a rewritten file or a chmod.
snapshot() {
  find "$P" "$C" | sort | while IFS= read -r f; do
    stat -f '%N %p %z %m' "$f"
  done
  find "$P" "$C" -type f | sort | xargs shasum 2>/dev/null
}

# ── criterion 5 (pass half) + criteria 1a/2a/3a/4a: a healthy fixture ─────────
make_fixture
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "5 a healthy fixture exits 0" || bad "5 rc=$RC: $OUT"
grep -q '^FAIL' <<<"$OUT" && bad "5 healthy fixture printed a FAIL line: $OUT" \
  || ok "5 a healthy fixture prints no FAIL line"
grep -qx 'aidex doctor: all checks passed' <<<"$OUT" \
  && ok "5 the pass summary is the exact line" || bad "5 summary: $OUT"
grep -q '^PASS: no stray skill copies' <<<"$OUT" && ok "1 no stray copy is a PASS" || bad "1 pass half: $OUT"
grep -q '^PASS: every skill script and wired hook is executable' <<<"$OUT" \
  && ok "2 exec bits present is a PASS" || bad "2 pass half: $OUT"
grep -qE '^PASS: python3 on PATH \(/' <<<"$OUT" \
  && ok "3 python3 present is a PASS naming its path" || bad "3 pass half: $OUT"
# A user's own skill in the personal store is not a stray copy of the plugin's.
grep -q 'my-own-skill' <<<"$OUT" && bad "1 a user's own skill was reported: $OUT" \
  || ok "1 a personal skill the plugin does not ship is left alone"

# ── criterion 1 (fail half): an aidex-* directory in the personal store ───────
make_fixture
mkskill "$C/skills/aidex-ghost"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "1 an aidex-* stray copy exits 1" || bad "1 rc=$RC: $OUT"
grep -q '^FAIL: .*skills/aidex-ghost shadows the plugin' <<<"$OUT" \
  && ok "1 the stray directory is named" || bad "1 not named: $OUT"
grep -q 'rm -rf' <<<"$OUT" && ok "1 the FAIL carries its fix command" || bad "1 no fix command: $OUT"

# ── F6: a name the plugin also ships is a NOTE, not a FAIL ───────────────────
# Owner decision 2026-09-20: plugin skills are namespaced (/aidex:plan), a personal
# `plan/` is /plan, and the repo's own policy is that a user directory sharing a
# suite name is skipped. Prescribing `rm -rf` on it is the one destructive mistake
# this read-only script could cause.
make_fixture
mkskill "$C/skills/skill-b"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "F6 a personal dir named like a plugin skill does not fail the run" \
  || bad "F6 rc=$RC: $OUT"
grep -q '^NOTE: .*skills/skill-b has the same name as a plugin skill' <<<"$OUT" \
  && ok "F6 it is reported as a NOTE" || bad "F6 no NOTE line: $OUT"
grep -q 'rm -rf' <<<"$OUT" && bad "F6 a NOTE prescribed rm -rf: $OUT" \
  || ok "F6 the NOTE prescribes no destructive command"
grep -qx 'aidex doctor: all checks passed' <<<"$OUT" \
  && ok "F6 a NOTE does not change the summary" || bad "F6 summary: $OUT"

# ── F4: a SYMLINKED stray copy is found, and its fix is rm, not rm -rf ────────
make_fixture
mkskill "$TMP/elsewhere/aidex-ghost"
ln -s "$TMP/elsewhere/aidex-ghost" "$C/skills/aidex-ghost"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "F4 a symlinked stray copy exits 1" || bad "F4 rc=$RC: $OUT"
grep -q 'skills/aidex-ghost shadows' <<<"$OUT" \
  && ok "F4 the symlink is named" || bad "F4 not named: $OUT"
grep -q 'rm -rf' <<<"$OUT" && bad "F4 rm -rf prescribed for a symlink: $OUT" \
  || ok "F4 the prescription for a symlink is a plain rm"

# ── criterion 2 (fail half a): a skill script lost its exec bit ──────────────
make_fixture
chmod -x "$P/skills/skill-a/scripts/x.sh"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "2 a non-executable skill script exits 1" || bad "2 rc=$RC: $OUT"
grep -q '^FAIL: not executable: .*scripts/x.sh' <<<"$OUT" \
  && ok "2 the non-executable script is named" || bad "2 not named: $OUT"
grep -q 'chmod +x .*scripts/x.sh' <<<"$OUT" \
  && ok "2 the FAIL carries its chmod line" || bad "2 no chmod line: $OUT"

# ── criterion 2 (fail half b): a WIRED HOOK lost its exec bit ────────────────
make_fixture
chmod -x "$P/hooks/h.sh"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "2 a non-executable wired hook exits 1" || bad "2b rc=$RC: $OUT"
grep -q '^FAIL: not executable: .*hooks/h.sh' <<<"$OUT" \
  && ok "2 the hook hooks.json wires is checked too" || bad "2b not named: $OUT"

# ── F2a: a hook wired under a SUBDIRECTORY is still read ─────────────────────
# The extractor's character class had no `/`, so hooks/nudges/h.sh yielded zero
# names — and checks 2 and 4 both printed PASS having enumerated nothing.
make_fixture
mkdir -p "$P/hooks/nudges"; mv "$P/hooks/h.sh" "$P/hooks/nudges/h.sh"
hooks_json "hooks/nudges/h.sh"
chmod -x "$P/hooks/nudges/h.sh"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "F2a a nested wired hook is read from hooks.json" || bad "F2a rc=$RC: $OUT"
grep -q '^FAIL: not executable: .*hooks/nudges/h.sh' <<<"$OUT" \
  && ok "F2a the nested hook is named" || bad "F2a not named: $OUT"

# ── F2b: hooks.json present but naming no hook at all is a FAIL, not a PASS ──
make_fixture
printf '{"hooks": {}}\n' > "$P/hooks/hooks.json"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "F2b a hooks.json naming no hook exits 1" || bad "F2b rc=$RC: $OUT"
grep -q '^FAIL: could not read any hook from ' <<<"$OUT" \
  && ok "F2b the empty enumeration says so instead of passing" || bad "F2b no FAIL line: $OUT"

# ── F2c: a hooks/ directory with no hooks.json wires nothing ─────────────────
make_fixture
rm "$P/hooks/hooks.json"
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "F2c hooks/ without hooks.json exits 1" || bad "F2c rc=$RC: $OUT"
grep -q '^FAIL: .*hooks/ exists but ' <<<"$OUT" \
  && ok "F2c the missing hooks.json is named" || bad "F2c no FAIL line: $OUT"

# ── F2d: a plugin that ships no hooks at all is legitimately a PASS ──────────
make_fixture
rm -rf "$P/hooks"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "F2d a plugin with no hooks/ at all exits 0" || bad "F2d rc=$RC: $OUT"

# ── criterion 4 (fail half): the same hook wired again in settings.json ──────
make_fixture
settings '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/h.sh"}]}]}}'
OUT="$(run)"; RC=$?
[[ $RC -eq 1 ]] && ok "4 a double-wired hook exits 1" || bad "4 rc=$RC: $OUT"
grep -q '^FAIL: h.sh is wired by the plugin AND by ' <<<"$OUT" \
  && ok "4 the doubled hook is named" || bad "4 not named: $OUT"
grep -q 'remove the SessionStart entry: bash ~/.claude/hooks/h.sh' <<<"$OUT" \
  && ok "4 the settings entry to remove is quoted back" || bad "4 entry not quoted: $OUT"

# ── F5: a basename collision outside any hooks/ dir is NOT a finding ─────────
# Matching the bare basename anywhere in the command told the user to delete their
# own unrelated entry — a destructive prescription on a healthy setting.
make_fixture
settings '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/bin/h.sh"}]}]}}'
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "F5 a same-named script outside hooks/ is not a double-wire" \
  || bad "F5 rc=$RC: $OUT"
grep -q '^PASS: no shipped hook is wired twice' <<<"$OUT" \
  && ok "F5 the check still passes explicitly" || bad "F5 pass half: $OUT"

# ── criterion 4 (pass half a): settings.json wiring another hook ─────────────
make_fixture
settings '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/someone-elses.sh"}]}]}}'
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "4 a hook nobody ships is not a finding" || bad "4 rc=$RC: $OUT"
grep -q '^PASS: no shipped hook is wired twice' <<<"$OUT" \
  && ok "4 the pass half says what it checked" || bad "4 pass half: $OUT"

# ── criterion 4 (pass half b): NO settings.json at all ───────────────────────
# "A missing settings.json is a PASS, never an error" — the common case on a fresh
# machine, and the one a crash would hit first.
make_fixture
[[ ! -e "$C/settings.json" ]] || bad "4 fixture precondition: settings.json exists"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "4 a missing settings.json exits 0" || bad "4 missing settings rc=$RC: $OUT"
grep -q '^PASS: no .*settings.json' <<<"$OUT" \
  && ok "4 the missing file is reported as a PASS, not an error" || bad "4 missing settings: $OUT"

# ── criterion 4 (pass half c): a settings.json with no hooks key ─────────────
make_fixture
settings '{"model": "opus", "skillOverrides": {}}'
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "4 a hook-less settings.json exits 0" || bad "4 hook-less rc=$RC: $OUT"
grep -q '^PASS: no shipped hook is wired twice' <<<"$OUT" \
  && ok "4 a hook-less settings.json passes the check, not skips it" || bad "4 hook-less: $OUT"

# ── F8: unreadable settings.json is its own message, not "invalid JSON" ──────
# Sending a permissions problem to "fix the JSON" is a fix nobody can apply.
if [[ "$(id -u)" -ne 0 ]]; then
  make_fixture
  settings '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/h.sh"}]}]}}'
  chmod 000 "$C/settings.json"
  OUT="$(run)"; RC=$?
  chmod 644 "$C/settings.json"
  [[ $RC -eq 1 ]] && ok "F8 an unreadable settings.json exits 1" || bad "F8 rc=$RC: $OUT"
  grep -q '^FAIL: cannot read ' <<<"$OUT" \
    && ok "F8 it is reported as unreadable, not as invalid JSON" || bad "F8 message: $OUT"
else
  ok "F8 skipped — running as root, where chmod 000 is not a permission error"
fi

# ── criterion 3 (fail half) + the python3-less half of criterion 4 ───────────
# Simulated with a PATH that holds the tools the script needs and no python3.
make_fixture
settings '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/someone-elses.sh"}]}]}}'
BIN="$TMP/nopy-bin"; mkdir -p "$BIN"
for t in bash find grep sed sort basename dirname stat shasum chmod mktemp rm cat id; do
  src="$(command -v "$t" 2>/dev/null)" && ln -sf "$src" "$BIN/$t"
done
[[ ! -e "$BIN/python3" ]] || bad "3 fixture precondition: python3 leaked into the stub PATH"
nopy() { PATH="$BIN" bash "$DOCTOR" --claude-dir "$C" --plugin-root "$P" 2>&1; }
OUT="$(nopy)"; RC=$?
[[ $RC -eq 1 ]] && ok "3 no python3 on PATH exits 1" || bad "3 rc=$RC: $OUT"
grep -q '^FAIL: python3 not found on PATH' <<<"$OUT" \
  && ok "3 the missing interpreter is reported" || bad "3 not reported: $OUT"
grep -qx 'FAIL: cannot check hooks without python3' <<<"$OUT" \
  && ok "4 a settings.json that cannot be parsed degrades to a FAIL, not a crash" \
  || bad "4 no python3: $OUT"
grep -qx 'aidex doctor: 2 check(s) failed' <<<"$OUT" \
  && ok "5 two failing checks are counted as two" || bad "5 count: $OUT"

# ── F3: no python3 AND no settings.json — Acceptance 4 says PASS ─────────────
# The absent file is decided before the interpreter is needed: there is nothing to
# parse, so python3's absence cannot make check 4 fail.
make_fixture
[[ ! -e "$C/settings.json" ]] || bad "F3 fixture precondition: settings.json exists"
OUT="$(nopy)"; RC=$?
[[ $RC -eq 1 ]] && ok "F3 only the python3 check fails (exit 1)" || bad "F3 rc=$RC: $OUT"
grep -q '^PASS: no .*settings.json' <<<"$OUT" \
  && ok "F3 a missing settings.json passes even without python3" || bad "F3 check 4: $OUT"
grep -qx 'aidex doctor: 1 check(s) failed' <<<"$OUT" \
  && ok "F3 exactly one check is counted as failed" || bad "F3 count: $OUT"

# ── criterion 5: the failure summary line, and exit 2 on a usage error ───────
make_fixture
mkskill "$C/skills/aidex-ghost"
OUT="$(run)"
grep -qx 'aidex doctor: 1 check(s) failed' <<<"$OUT" \
  && ok "5 one failing check is counted as one" || bad "5 count: $OUT"
bash "$DOCTOR" --claude-dir "$C" --plugin-root "$P" --nonsense >/dev/null 2>&1
[[ $? -eq 2 ]] && ok "5 a usage error is exit 2, distinct from a failing check" \
  || bad "5 unknown option did not exit 2"

# ── F7: a wrong root is a usage error, never a green report ──────────────────
make_fixture
mkdir -p "$TMP/not-a-plugin"
OUT="$(bash "$DOCTOR" --claude-dir "$C" --plugin-root "$TMP/not-a-plugin" 2>&1)"; RC=$?
[[ $RC -eq 2 ]] && ok "F7 a --plugin-root with no skills/ is exit 2" || bad "F7 rc=$RC: $OUT"
grep -q 'skills' <<<"$OUT" && ok "F7 the message says what is missing" || bad "F7 message: $OUT"
grep -q 'all checks passed' <<<"$OUT" && bad "F7 a wrong root reported a healthy install: $OUT" \
  || ok "F7 a wrong root never prints a pass summary"

OUT="$(bash "$DOCTOR" --claude-dir "$TMP/no-such-home" --plugin-root "$P" 2>&1)"; RC=$?
[[ $RC -eq 2 ]] && ok "F7 a --claude-dir that does not exist is exit 2" || bad "F7 rc=$RC: $OUT"

# ...but an existing home that simply has no skills/ yet is healthy, not an error.
make_fixture
rm -rf "$C/skills"
OUT="$(run)"; RC=$?
[[ $RC -eq 0 ]] && ok "F7 a claude-dir without skills/ is a PASS, not a usage error" \
  || bad "F7 no skills dir rc=$RC: $OUT"

# ── F1: the shipped tree itself ─────────────────────────────────────────────
# The one cell that reads outside the fixtures, on purpose: --claude-dir is a fresh
# empty directory, so only the PLUGIN half of the report can speak. Ten tracked
# scripts were mode 100644 while all 34 fixtured cells were green (BL-428).
REAL_ROOT="$(cd "$DIR/../../.." && pwd -P)"
FRESH="$TMP/fresh-home"; mkdir -p "$FRESH"
OUT="$(bash "$DOCTOR" --claude-dir "$FRESH" --plugin-root "$REAL_ROOT" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && ok "F1 the doctor is green against this repo's own plugin root" \
  || bad "F1 rc=$RC: $OUT"

# ── criterion 6: the run writes nothing ─────────────────────────────────────
# Both a healthy tree and a failing one: a "fix" that slipped in would most likely
# fire on the failing side.
make_fixture
BEFORE="$(snapshot)"
run >/dev/null 2>&1
[[ "$BEFORE" == "$(snapshot)" ]] && ok "6 a healthy run leaves the fixture tree byte-identical" \
  || bad "6 the healthy run changed the fixture tree"

make_fixture
mkskill "$C/skills/aidex-ghost"; chmod -x "$P/skills/skill-a/scripts/x.sh"
settings '{"hooks": {"SessionStart": [{"hooks": [{"type": "command", "command": "bash ~/.claude/hooks/h.sh"}]}]}}'
BEFORE="$(snapshot)"
run >/dev/null 2>&1
[[ "$BEFORE" == "$(snapshot)" ]] && ok "6 a FAILING run leaves the fixture tree byte-identical" \
  || bad "6 the failing run changed the fixture tree"

echo
[[ $FAIL -eq 0 ]] && { echo "OK — doctor: $PASS cells (stray copies, exec bits, python3, double-wired hooks; read-only)"; exit 0; }
echo "$FAIL failure(s), $PASS ok"; exit 1
