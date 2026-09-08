#!/usr/bin/env bash
# test-init.sh — smoke tests for skills/aidex/scripts/init-context.sh.
#
# Covers:
#   1. Fresh dir -> full .context/ skeleton created.
#   2. Re-run -> everything reported "exists"; a pre-written canary file in
#      backlog/ is left untouched.
#   3. Partial pre-existing .context/ (only plans/) -> fills the gaps only.
#   4. Suite not installed (AIDEX_DIR pointed at an empty temp dir) -> still
#      scaffolds the directories, notes the skipped seeding, exits 0.
#   5. The suggested CLAUDE.md block is printed to stdout but no CLAUDE.md
#      file is ever created.
#   8. The artifact-style.md question (BL-337): skipped and SAID to be skipped
#      without a TTY, answered by flag, answered at a real pty, and never asked
#      twice once the shared marker exists.
#
# Every invocation below redirects stdin from /dev/null on purpose: scenario 8
# gives init a `read` at a TTY, and run-all.sh does not redirect a test's stdin
# (run-all.sh:126), so a suite run from a terminal would otherwise hang inside
# a command substitution. Scenario 8 opens its own pty where it wants one.
#
# Run with: bash skills/aidex/tests/test-init.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
INIT="$SCRIPT_DIR/../scripts/init-context.sh"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

# --- Scenario 1: fresh dir -> full skeleton created ---

d1="$(mktemp -d)"
out1="$(bash "$INIT" "$d1" </dev/null)"

for sub in backlog plans decisions research references requests \
           backlog/_archive plans/_archive requests/_archive decisions/_archive; do
  if [[ -d "$d1/.context/$sub" ]]; then
    pass "scenario1: .context/$sub created"
  else
    fail "scenario1: .context/$sub missing"
  fi
done

created_count="$(printf '%s\n' "$out1" | grep -c '^created: \.context/')"
[[ "$created_count" -ge 9 ]] || fail "scenario1: expected >=9 created: lines, got $created_count"

# --- Scenario 2: re-run -> all exists, canary untouched ---

canary="$d1/.context/backlog/canary.md"
printf 'do not touch\n' > "$canary"

out2="$(bash "$INIT" "$d1" </dev/null)"
exists_count="$(printf '%s\n' "$out2" | grep -c '^exists: \.context/')"
[[ "$exists_count" -ge 9 ]] || fail "scenario2: expected >=9 exists: lines on re-run, got $exists_count"

if printf '%s\n' "$out2" | grep -q '^created: \.context/backlog$'; then
  fail "scenario2: backlog/ reported created on re-run"
else
  pass "scenario2: backlog/ reported exists on re-run"
fi

if [[ "$(cat "$canary")" == "do not touch" ]]; then
  pass "scenario2: canary file untouched"
else
  fail "scenario2: canary file was modified"
fi

rm -rf "$d1"

# --- Scenario 3: partial pre-existing .context/ (only plans/) -> fills gaps only ---

d3="$(mktemp -d)"
mkdir -p "$d3/.context/plans"
printf 'pre-existing\n' > "$d3/.context/plans/canary.md"

out3="$(bash "$INIT" "$d3" </dev/null)"

if printf '%s\n' "$out3" | grep -q '^exists: \.context/plans$'; then
  pass "scenario3: pre-existing plans/ reported exists"
else
  fail "scenario3: pre-existing plans/ not reported exists"
fi

for sub in backlog decisions research references requests \
           backlog/_archive plans/_archive requests/_archive decisions/_archive; do
  if [[ -d "$d3/.context/$sub" ]]; then
    pass "scenario3: gap $sub filled"
  else
    fail "scenario3: gap $sub not filled"
  fi
done

if [[ "$(cat "$d3/.context/plans/canary.md")" == "pre-existing" ]]; then
  pass "scenario3: plans/ pre-existing content untouched"
else
  fail "scenario3: plans/ pre-existing content was modified"
fi

rm -rf "$d3"

# --- Scenario 4: suite not installed (AIDEX_DIR -> empty temp dir) ---

d4="$(mktemp -d)"
empty_aidex="$(mktemp -d)"

out4="$(AIDEX_DIR="$empty_aidex" bash "$INIT" "$d4" </dev/null)"
rc4=$?

[[ $rc4 -eq 0 ]] || fail "scenario4: exit code expected 0, got $rc4"

for sub in backlog plans decisions research references requests \
           backlog/_archive plans/_archive requests/_archive decisions/_archive; do
  [[ -d "$d4/.context/$sub" ]] || fail "scenario4: .context/$sub not scaffolded without suite"
done

if printf '%s\n' "$out4" | grep -qi 'not installed'; then
  pass "scenario4: notes the skipped seeding"
else
  fail "scenario4: no note about skipped seeding"
fi

rm -rf "$d4" "$empty_aidex"

# --- Scenario 5: CLAUDE.md block printed, no file created ---

d5="$(mktemp -d)"
out5="$(bash "$INIT" "$d5" </dev/null)"

if printf '%s\n' "$out5" | grep -qi 'Suggested CLAUDE.md addition'; then
  pass "scenario5: CLAUDE.md suggestion block printed"
else
  fail "scenario5: CLAUDE.md suggestion block missing from output"
fi

if [[ -f "$d5/CLAUDE.md" ]]; then
  fail "scenario5: CLAUDE.md file was created"
else
  pass "scenario5: no CLAUDE.md file created"
fi

rm -rf "$d5"

# --- Scenario 6: _tmp/ scratch bucket seeded, README never overwritten (BL-028) ---

d6="$(mktemp -d)"
bash "$INIT" "$d6" </dev/null >/dev/null

if [[ -f "$d6/_tmp/README.md" ]]; then
  pass "scenario6: _tmp/README.md seeded"
else
  fail "scenario6: _tmp/README.md not created"
fi

if grep -q 'deleted at any time without asking' "$d6/_tmp/README.md"; then
  pass "scenario6: README carries the disposable contract"
else
  fail "scenario6: README missing the disposable contract"
fi

printf 'project-specific contract\n' > "$d6/_tmp/README.md"
out6="$(bash "$INIT" "$d6" </dev/null)"

if [[ "$(cat "$d6/_tmp/README.md")" == "project-specific contract" ]]; then
  pass "scenario6: existing _tmp/README.md left untouched"
else
  fail "scenario6: existing _tmp/README.md was overwritten"
fi

if printf '%s\n' "$out6" | grep -q '^exists: _tmp/README.md$'; then
  pass "scenario6: re-run reports the README as existing"
else
  fail "scenario6: re-run did not report _tmp/README.md as existing"
fi

rm -rf "$d6"

# --- Scenario 7: what init produces must pass aidex's own validator (BL-100) ---
# AIDEX_DIR points at the repo so the scaffold is built by the scripts under
# test, not by whatever version happens to be installed.

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
VALIDATE="$REPO_ROOT/skills/aidex-conventions/scripts/validate.py"

d7="$(mktemp -d)"
AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d7" </dev/null >/dev/null

if [[ -f "$d7/.context/references/01-project-commands.md" ]]; then
  pass "scenario7: project commands written as a reference (NN-<slug>.md)"
  if head -1 "$d7/.context/references/01-project-commands.md" | grep -q '^---$'; then
    pass "scenario7: the reference carries front-matter"
  else
    fail "scenario7: the reference has no front-matter block"
  fi
else
  fail "scenario7: .context/references/01-project-commands.md not written"
fi

val_out="$(cd "$d7" && python3 "$VALIDATE" 2>&1)"
if printf '%s\n' "$val_out" | grep -qE 'violations: 0 · warnings: 0'; then
  pass "scenario7: a fresh init validates clean (0 violations, 0 warnings)"
else
  fail "scenario7: fresh init fails aidex's own validator:
$val_out"
fi

# A project that predates the rename keeps its file; init must not duplicate it.
d7b="$(mktemp -d)"
mkdir -p "$d7b/.context/references"
printf 'legacy\n' > "$d7b/.context/references/project-commands.md"
AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d7b" </dev/null >/dev/null
if [[ -f "$d7b/.context/references/01-project-commands.md" ]]; then
  fail "scenario7: init duplicated a pre-existing project-commands.md"
else
  pass "scenario7: pre-existing project-commands.md not duplicated"
fi
[[ "$(cat "$d7b/.context/references/project-commands.md")" == "legacy" ]] \
  || fail "scenario7: pre-existing project-commands.md was overwritten"

rm -rf "$d7" "$d7b"

# --- Scenario 8: the artifact-style.md question (BL-337) ---
#
# Three criteria, and the third is an ABSENCE: without a TTY no profile must
# appear. An absence assertion that samples nothing passes vacuously, so each
# one below is paired with the mutation that makes the denied thing appear —
# the flag, and a real pty answering the prompt.
#
# AIDEX_DIR points at the repo throughout: the template the profile is seeded
# from ships in aidex-dash, and without it the step correctly skips itself.

PTY_DRIVER="$(mktemp -d)/pty-answer.py"
cat > "$PTY_DRIVER" <<'PYEOF'
"""Run a command on a real pty, answer its prompt, print everything it wrote.

The `read` branch of init-context.sh only exists when stdin is a terminal, so
a test that pipes into it exercises the no-TTY branch instead and proves
nothing. python3 is already a dependency of this file (scenario 7 runs
validate.py); `script` is not, and its BSD and GNU spellings differ.
"""
import os, pty, sys, time

reply, cmd = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)

out = b""
answered = False
deadline = time.time() + 20
while time.time() < deadline:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
    if not answered and b"empty declines" in out:
        os.write(fd, (reply + "\n").encode())
        answered = True
if not answered:
    # No prompt appeared. That is a real outcome (marker present, profile
    # present, template missing) — report it rather than hanging.
    try:
        os.write(fd, b"\n")
    except OSError:
        pass
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace"))
sys.exit(0 if os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0 else 1)
PYEOF

# 8a — ABSENCE: no flag, no TTY -> question skipped, said to be skipped,
#      and NOTHING written. Not even the marker: skipped is not asked, and a
#      marker here would silence aidex-dash's wrap-time offer too, losing the
#      question at both surfaces instead of moving it.
d8a="$(mktemp -d)"
out8a="$(AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d8a" </dev/null)"

if printf '%s\n' "$out8a" | grep -q 'no TTY — skipped the artifact-style.md question'; then
  pass "scenario8a: no TTY -> the skipped question is reported"
else
  fail "scenario8a: no TTY -> nothing reported the skipped question"
fi

[[ ! -f "$d8a/.context/artifact-style.md" ]] \
  && pass "scenario8a: no TTY -> no profile created" \
  || fail "scenario8a: a profile was created without an explicit yes"

[[ ! -f "$d8a/.context/.aidex-artifact-style-offered" ]] \
  && pass "scenario8a: no TTY -> no marker, so the wrap-time offer still fires" \
  || fail "scenario8a: a skipped question recorded itself as offered"

# 8b — MUTATION of 8a, via the flag: the denied file must now appear.
out8b="$(AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d8a" --artifact-style es </dev/null)"

if [[ -f "$d8a/.context/artifact-style.md" ]]; then
  pass "scenario8b: --artifact-style es creates the profile"
else
  fail "scenario8b: --artifact-style es did not create the profile"
fi

if grep -qx -- '- language: es' "$d8a/.context/artifact-style.md"; then
  pass "scenario8b: the language answer is written as the field wrap-report.sh reads"
else
  fail "scenario8b: the profile does not carry '- language: es'"
fi

if grep -q '{{PROJECT_NAME}}' "$d8a/.context/artifact-style.md"; then
  fail "scenario8b: {{PROJECT_NAME}} left unsubstituted"
else
  pass "scenario8b: {{PROJECT_NAME}} substituted"
fi

[[ -f "$d8a/.context/.aidex-artifact-style-offered" ]] \
  && pass "scenario8b: an answered question records itself in the shared marker" \
  || fail "scenario8b: the answered question left no record"

printf '%s\n' "$out8b" | grep -q '^created: \.context/artifact-style\.md$' \
  && pass "scenario8b: the creation is reported" \
  || fail "scenario8b: the creation was not reported"

# Re-running must not overwrite an answered profile.
printf 'hand-edited\n' >> "$d8a/.context/artifact-style.md"
out8b2="$(AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d8a" --artifact-style fr </dev/null)"
if grep -q 'hand-edited' "$d8a/.context/artifact-style.md"; then
  pass "scenario8b: an existing profile is never overwritten"
else
  fail "scenario8b: a re-run overwrote the existing profile"
fi
printf '%s\n' "$out8b2" | grep -q '^exists: \.context/artifact-style\.md$' \
  && pass "scenario8b: the existing profile is reported as existing" \
  || fail "scenario8b: the existing profile was not reported"

rm -rf "$d8a"

# 8c — MUTATION of 8a at a REAL pty: the interactive branch is the one a human
#      hits, and piping into it exercises the no-TTY branch instead.
d8c="$(mktemp -d)"
out8c="$(AIDEX_DIR="$REPO_ROOT" python3 "$PTY_DRIVER" "es" bash "$INIT" "$d8c")"
rc8c=$?

[[ $rc8c -eq 0 ]] || fail "scenario8c: init at a pty exited non-zero ($rc8c)"

if printf '%s\n' "$out8c" | grep -q 'empty declines'; then
  pass "scenario8c: at a TTY the question is actually asked"
else
  fail "scenario8c: no question was asked at a TTY: $out8c"
fi

if [[ -f "$d8c/.context/artifact-style.md" ]] && grep -qx -- '- language: es' "$d8c/.context/artifact-style.md"; then
  pass "scenario8c: a typed answer creates the profile in that language"
else
  fail "scenario8c: the typed answer did not produce the profile"
fi

rm -rf "$d8c"

# 8d — an EMPTY answer at the pty is a decline: recorded, nothing created.
d8d="$(mktemp -d)"
out8d="$(AIDEX_DIR="$REPO_ROOT" python3 "$PTY_DRIVER" "" bash "$INIT" "$d8d")"

[[ ! -f "$d8d/.context/artifact-style.md" ]] \
  && pass "scenario8d: an empty answer creates nothing" \
  || fail "scenario8d: an empty answer created the profile anyway"

[[ -f "$d8d/.context/.aidex-artifact-style-offered" ]] \
  && pass "scenario8d: the decline is recorded in the shared marker" \
  || fail "scenario8d: the decline left no record, so both surfaces will ask again"

# The decline must stop the question, at a pty, without a flag.
out8d2="$(AIDEX_DIR="$REPO_ROOT" python3 "$PTY_DRIVER" "es" bash "$INIT" "$d8d")"
if printf '%s\n' "$out8d2" | grep -q 'empty declines'; then
  fail "scenario8d: the question was asked a second time after a decline"
else
  pass "scenario8d: a declined question is not asked again"
fi
[[ ! -f "$d8d/.context/artifact-style.md" ]] \
  && pass "scenario8d: the re-run still created nothing" \
  || fail "scenario8d: the re-run created a profile nobody asked for"

# ...and the marker it wrote is the one aidex-dash's wrap-time offer reads, so
# that surface does not ask either. This is criterion 2 asserted at the
# CONSUMER's seam, not only where the file is written.
WRAP="$REPO_ROOT/skills/aidex-dash/scripts/wrap-report.sh"
if [[ -x "$WRAP" ]]; then
  mkdir -p "$d8d/.context/reports"
  wrapbody='<style>body{color:#111}@media (prefers-color-scheme: dark){body{color:#eee}}</style><div class="page"><main class="main"><h1>x</h1></main></div>'
  wraperr="$(printf '%s\n' "$wrapbody" | bash "$WRAP" --title "T" \
             --out "$d8d/.context/reports/a.html" 2>&1 >/dev/null)"
  if printf '%s\n' "$wraperr" | grep -q 'Offer the profile to the reader ONCE'; then
    fail "scenario8d: the wrap-time offer still fired after init recorded the decline"
  else
    pass "scenario8d: init's decline silences the wrap-time offer (one marker, two surfaces)"
  fi
else
  fail "scenario8d: wrap-report.sh not found at $WRAP"
fi

rm -rf "$d8d"

# 8e — --no-artifact-style is the flag form of that decline.
d8e="$(mktemp -d)"
out8e="$(AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d8e" --no-artifact-style </dev/null)"

[[ ! -f "$d8e/.context/artifact-style.md" ]] \
  && pass "scenario8e: --no-artifact-style creates nothing" \
  || fail "scenario8e: --no-artifact-style created a profile"

[[ -f "$d8e/.context/.aidex-artifact-style-offered" ]] \
  && pass "scenario8e: --no-artifact-style records the decline" \
  || fail "scenario8e: --no-artifact-style left no record"

printf '%s\n' "$out8e" | grep -q 'declined' \
  && pass "scenario8e: the decline is reported" \
  || fail "scenario8e: the decline was not reported"

# An explicit flag is an explicit yes even after a decline: the marker gates the
# QUESTION, never an answer the caller just gave.
AIDEX_DIR="$REPO_ROOT" bash "$INIT" "$d8e" --artifact-style es </dev/null >/dev/null
[[ -f "$d8e/.context/artifact-style.md" ]] \
  && pass "scenario8e: an explicit flag still creates the profile after a decline" \
  || fail "scenario8e: the marker blocked an explicit yes"

rm -rf "$d8e"

# 8f — no aidex-dash installed: no template, so the step skips itself and says so
#      instead of writing an empty profile.
d8f="$(mktemp -d)"
empty8f="$(mktemp -d)"
out8f="$(AIDEX_DIR="$empty8f" bash "$INIT" "$d8f" --artifact-style es </dev/null)"

[[ ! -f "$d8f/.context/artifact-style.md" ]] \
  && pass "scenario8f: no template -> no profile" \
  || fail "scenario8f: a profile was written without a template"

printf '%s\n' "$out8f" | grep -q 'aidex-dash not installed' \
  && pass "scenario8f: the missing template is noted" \
  || fail "scenario8f: the missing template was silent"

rm -rf "$d8f" "$empty8f" "$(dirname "$PTY_DRIVER")"

# 8g — a language code, and nothing else. The value is interpolated into a `sed`
#      s-expression delimited by `|`, so a `|` in it closes the substitution and
#      everything after is parsed as sed script — `w <path>` then writes an
#      arbitrary file. Reproduced 2026-09-08 before the guard existed.
d8g="$(mktemp -d)"
loot8g="$(mktemp -d)/PWNED"
out8g="$(bash "$INIT" "$d8g" --artifact-style "en|w ${loot8g}
s|x|x" </dev/null 2>&1)"; rc8g=$?

[[ ! -e "$loot8g" ]] \
  && pass "scenario8g: a '|' in the language code writes no arbitrary file" \
  || fail "scenario8g: sed injection wrote $loot8g"

[[ $rc8g -ne 0 ]] \
  && pass "scenario8g: a malformed language code is refused" \
  || fail "scenario8g: a malformed language code was accepted (rc=$rc8g)"

[[ ! -f "$d8g/.context/artifact-style.md" ]] \
  && pass "scenario8g: no profile is written from a malformed code" \
  || fail "scenario8g: a profile was written from a malformed code"

# the mutation: a well-formed code on the same path must still be accepted, or
# 8g would pass by refusing everything.
d8g2="$(mktemp -d)"
bash "$INIT" "$d8g2" --artifact-style pt-BR </dev/null >/dev/null 2>&1
grep -q '^- language: pt-BR$' "$d8g2/.context/artifact-style.md" 2>/dev/null \
  && pass "scenario8g: a well-formed code is still accepted (mutation)" \
  || fail "scenario8g: the guard also rejects a valid code"

rm -rf "$d8g" "$d8g2" "$(dirname "$loot8g")"

# 8h — never write through a symlink. The `-f` guard above returns true for a
#      symlink to an EXISTING file, so that case is covered; a symlink whose
#      target does not exist is not `-f`, and the write goes through it to a
#      path the caller never named.
d8h="$(mktemp -d)"
bash "$INIT" "$d8h" --no-artifact-style </dev/null >/dev/null 2>&1
target8h="$(mktemp -d)/planted.md"
rm -f "$d8h/.context/.aidex-artifact-style-offered"
ln -s "$target8h" "$d8h/.context/artifact-style.md"
out8h="$(bash "$INIT" "$d8h" --artifact-style es </dev/null 2>&1)"

[[ ! -e "$target8h" ]] \
  && pass "scenario8h: a dangling symlink is not written through" \
  || fail "scenario8h: the write followed the symlink to $target8h"

printf '%s\n' "$out8h" | grep -q 'symlink' \
  && pass "scenario8h: the refusal names the symlink" \
  || fail "scenario8h: the symlink was skipped silently"

rm -rf "$d8h" "$(dirname "$target8h")"

# --- Summary ---

if [[ $failures -eq 0 ]]; then
  printf 'All init-context.sh tests passed.\n'
  exit 0
else
  printf '%d test(s) failed.\n' "$failures"
  exit 1
fi
