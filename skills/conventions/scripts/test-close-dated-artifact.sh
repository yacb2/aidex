#!/usr/bin/env bash
# test-close-dated-artifact.sh — lifecycle test for close-dated-artifact.sh in an
# isolated temp project: request close (default done), decision close (superseded
# with back-ref, dropped), status validation, not-found and double-close refusal.
#
# Run with: bash skills/conventions/scripts/test-close-dated-artifact.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/close-dated-artifact.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/.context/requests" "$TMP/.context/decisions"
cd "$TMP"

mk() { # $1=path
  printf -- '---\ntitle: "t"\nstatus: %s\ncreated: 2026-01-01\nupdated: 2026-01-01\n---\nbody\n' "$2" > "$1"
}
mk ".context/requests/2026-01-01-export-feature.md" open
mk ".context/decisions/2026-01-02-old-choice.md" accepted
mk ".context/decisions/2026-01-03-bad-idea.md" accepted

# request: default done
out="$(bash "$SCRIPT" requests export-feature 2>/dev/null)" || fail "request close exited non-zero"
[[ "$out" == CLOSED*"_archive/2026-01-01-export-feature.md" ]] || fail "request: expected CLOSED archive path, got: $out"
grep -q "^status: done" ".context/requests/_archive/2026-01-01-export-feature.md" || fail "request: status not done"
grep -q "^updated: $(date +%F)" ".context/requests/_archive/2026-01-01-export-feature.md" || fail "request: updated not stamped"

# decision: superseded requires --superseded-by
bash "$SCRIPT" decisions old-choice --status superseded >/dev/null 2>&1 && fail "decision: superseded without --superseded-by should fail"
bash "$SCRIPT" decisions old-choice --status superseded --superseded-by decision/2026-07-02-new-choice >/dev/null 2>&1 || fail "decision superseded close exited non-zero"
grep -q "^superseded_by: decision/2026-07-02-new-choice" ".context/decisions/_archive/2026-01-02-old-choice.md" || fail "decision: superseded_by not written"

# decision: dropped; decisions require explicit status
bash "$SCRIPT" decisions bad-idea >/dev/null 2>&1 && fail "decision: close without --status should fail"
bash "$SCRIPT" decisions bad-idea --status dropped >/dev/null 2>&1 || fail "decision dropped close exited non-zero"
grep -q "^status: dropped" ".context/decisions/_archive/2026-01-03-bad-idea.md" || fail "decision: status not dropped"

# refusals: bad status, not found, double close
bash "$SCRIPT" requests whatever --status accepted >/dev/null 2>&1 && fail "requests: invalid status accepted should fail"
bash "$SCRIPT" requests no-such-slug >/dev/null 2>&1 && fail "not-found should exit non-zero"
bash "$SCRIPT" requests export-feature >/dev/null 2>&1 && fail "double close should fail (already archived / not found in active)"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi

# --- the EXACT filename resolves, not only a fragment -----------------------
# The lookup was `ls "$DIR/"*"$ARG"*.md`, so passing the full filename — the form every
# error message and every directory listing prints — expanded to `*<name>.md*.md` and
# matched nothing. Field-hit 2026-09-07 while closing a superseded ADR by the name the
# validator had just printed.
mk ".context/decisions/2026-02-02-exact-name.md" accepted
bash "$SCRIPT" decisions 2026-02-02-exact-name.md --status superseded \
  --superseded-by decision/2026-02-03-other.md >/dev/null 2>&1
[[ -f ".context/decisions/_archive/2026-02-02-exact-name.md" ]] \
  || fail "the exact filename did not resolve — the glob was *\$ARG*.md, so <name>.md matched nothing"

# --- a fragment naming two artifacts is refused; an exact stem wins (BL-541) ----
# The fragment lookup was `ls ... | head -1`, so it closed whichever file sorted first.
mk ".context/requests/2026-03-01-ambig-one.md" open
mk ".context/requests/2026-03-02-ambig-two.md" open
before="$(cat .context/requests/2026-03-0[12]-ambig-*.md)"
rc=0; err="$(bash "$SCRIPT" requests ambig 2>&1 >/dev/null)" || rc=$?
[[ $rc -eq 2 && "$err" == *ambiguous* ]] || fail "ambiguous fragment: expected exit 2 + 'ambiguous', got rc=$rc: $err"
[[ "$(cat .context/requests/2026-03-0[12]-ambig-*.md 2>/dev/null)" == "$before" ]] \
  || fail "ambiguous fragment mutated or archived a request"
# `stem-two` sorts before `stem`; the stem 2026-03-05-stem is what `stem` names exactly.
mk ".context/requests/2026-03-04-stem-two.md" open
mk ".context/requests/2026-03-05-stem.md" open
bash "$SCRIPT" requests stem >/dev/null 2>&1 || fail "exact stem: close exited non-zero"
[[ -f ".context/requests/_archive/2026-03-05-stem.md" && -f ".context/requests/2026-03-04-stem-two.md" ]] \
  || fail "exact stem: 'stem' did not close 2026-03-05-stem.md (closed the longer name instead)"

# --- a name that resolves to a file outside <type>/ is refused ------------------
# `notes.md` was stripped to `notes` and resolve_worklist's `[[ -f ]]` found ./notes
# in the CWD, so a file that is no request was rewritten and archived.
printf 'not an artifact\nstatus: x\n' > notes
rc=0; bash "$SCRIPT" requests notes.md >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] || fail "a CWD file named by the stripped slug was closed (rc=0)"
[[ -f notes && "$(cat notes)" == $'not an artifact\nstatus: x' && ! -e .context/requests/_archive/notes ]] \
  || fail "a CWD file outside requests/ was rewritten or archived"
# A path INTO the type folder is still accepted (the documented path form).
mk ".context/requests/2026-04-01-by-path.md" open
bash "$SCRIPT" requests .context/requests/2026-04-01-by-path.md >/dev/null 2>&1 \
  || fail "a relative path into requests/ was refused"
[[ -f ".context/requests/_archive/2026-04-01-by-path.md" ]] || fail "the relative path form did not archive"
# CDPATH makes `cd` echo the directory; the comparison must not read that echo.
mk ".context/requests/2026-04-02-cdpath.md" open
CDPATH=".:/usr" bash "$SCRIPT" requests .context/requests/2026-04-02-cdpath.md >/dev/null 2>&1 \
  || fail "with CDPATH set, a relative path into requests/ was refused"
# A worktree that links .context (work_hours_ws WT_LINKS): the folder is a symlink,
# so the file's physical dir differs from the unresolved $DIR — still the same folder.
mkdir sib && ln -s "$PWD/.context" sib/.context
mk ".context/requests/2026-04-03-linked.md" open
rc=0; (cd sib && bash "$SCRIPT" requests linked >/dev/null 2>&1) || rc=$?
[[ $rc -eq 0 && -f ".context/requests/_archive/2026-04-03-linked.md" ]] \
  || fail "through a symlinked .context, a request was refused (rc=$rc) or not archived"

# --- BL-551 review: the folder guard and the `.md` strip, each from a fresh project ----
# A path to a CWD file is taken as given; only the outside-$DIR guard stops it (a bare
# name no longer reaches that guard: it is a fragment, BL-566).
G="$(mktemp -d)"; mkdir -p "$G/.context/requests"
mk "$G/.context/requests/2026-05-01-only-one.md" open
( cd "$G" && printf 'x\nstatus: x\n' > notes
  rc=0; bash "$SCRIPT" requests ./notes >/dev/null 2>&1 || rc=$?
  [[ $rc -ne 0 && "$(cat notes)" == $'x\nstatus: x' && ! -e .context/requests/_archive/notes ]] ) \
  || fail "a path to a CWD file passed the outside-requests/ guard"
# `.md` alone must not strip to an empty fragment that globs the only open request.
rc=0; ( cd "$G" && bash "$SCRIPT" requests .md >/dev/null 2>&1 ) || rc=$?
[[ $rc -ne 0 && -f "$G/.context/requests/2026-05-01-only-one.md" ]] \
  || fail "'.md' alone closed the only open request (rc=$rc)"
# BL-566: a bare name that matches a real request is that request even with a same-named
# CWD file; the script's own `[[ -f "$ARG" ]]` took ./notes and died "outside requests/".
mk "$G/.context/requests/2026-05-02-notes.md" open
rc=0; ( cd "$G" && bash "$SCRIPT" requests notes >/dev/null 2>&1 ) || rc=$?
[[ $rc -eq 0 && -f "$G/.context/requests/_archive/2026-05-02-notes.md" && "$(cat "$G/notes")" == $'x\nstatus: x' ]] \
  || fail "with a stray ./notes, 'requests notes' did not close 2026-05-02-notes.md (rc=$rc)"
# An exported CDPATH must not redirect the folder guard: `cd requests` from G/work landed
# in G/.context/requests, so a user file G/work/requests/notes-cdpath.md passed as a request.
mkdir -p "$G/work/requests"; printf 'mine\nstatus: doing\n' > "$G/work/requests/notes-cdpath.md"
rc=0; err="$( cd "$G/work" && CDPATH="$G/.context" bash "$SCRIPT" requests requests/notes-cdpath.md 2>&1 >/dev/null )" || rc=$?
[[ $rc -ne 0 && "$err" == *"outside"* && "$(cat "$G/work/requests/notes-cdpath.md" 2>/dev/null)" == $'mine\nstatus: doing' \
   && ! -e "$G/.context/requests/_archive/notes-cdpath.md" ]] \
  || fail "with CDPATH exported, a user file outside requests/ was closed or not refused as outside (rc=$rc): $err"
# `..` after a symlinked folder inside requests/: a logical `cd ext/..` lands back in
# requests/, while the file the kernel opens is beside the link's target.
mkdir -p "$G/outside/sub" && ln -s "$G/outside/sub" "$G/.context/requests/ext"
printf 'mine\nstatus: doing\n' > "$G/outside/req-symlink.md"
rc=0; err="$( cd "$G/.context/requests" && bash "$SCRIPT" requests ext/../req-symlink.md 2>&1 >/dev/null )" || rc=$?
[[ $rc -ne 0 && "$err" == *"outside"* && "$(cat "$G/outside/req-symlink.md" 2>/dev/null)" == $'mine\nstatus: doing' \
   && ! -e "$G/.context/requests/_archive/req-symlink.md" ]] \
  || fail "a symlinked folder plus .. inside requests/ let an outside file through (rc=$rc): $err"
rm -rf "$G"

# The gate. Without it this file ended on an unconditional `echo`, so it printed OK and
# exited 0 with failures on screen — a suite that cannot fail, which is worse than no
# suite because the sweep that runs it reports green. Found 2026-09-07 while adding the
# exact-filename cell above: the FAIL line printed and the run still passed.
if [[ "$failures" -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
echo "OK — request/decision close, superseded back-ref, refusals"
