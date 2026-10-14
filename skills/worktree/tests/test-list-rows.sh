#!/usr/bin/env bash
# test-list-rows.sh — `list --porcelain` must report what is true about each
# worktree, one tab-separated row of six non-empty fields.
#
#   worktree-c05  a worktree whose participants are only the root token (`.`) was
#                 shown as STRAY-DIR: its checkout IS $DEST, so git prints
#                 `worktree $DEST` with no trailing slash and the registration
#                 grep anchored on `$DEST/` never matched.
#   worktree-c10  the BRANCH column probed $DEST/<full participant path>, but a
#                 nested participant ("apps/backend") is checked out at
#                 $DEST/backend, so BRANCH was always "-".
#   worktree-c11  an empty .wt-slot (`new --no-infra` writes exactly that) or a
#                 detached HEAD printed an EMPTY field; a consumer reading with
#                 IFS=$'\t' collapses adjacent tabs and every later column shifts.
#   BL-776        a non-empty .wt-slot that is not a slot (`abc`, `0`, `99`) was
#                 printed as the SLOT instead of falling back to the claim; an
#                 out-of-range claim was shown, `08` printed a bash base error and
#                 18446744073709551617 wrapped into range.
#   BL-804        a claim with no directory (MISSING-DIR) printed its filename's
#                 number raw: a planted slot-abc showed SLOT abc.
#
# Behavioural, no daemon: docker is a stub that exits 0.
# Run with: bash skills/worktree/tests/test-list-rows.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/slots"; mkdir -p "$TMPDIR"
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\nexit 0\n' > "$BIN/docker"; chmod +x "$BIN/docker"

git_q() { /usr/bin/git "$@" >/dev/null 2>&1; }
init_repo() {  # init_repo <dir>: a git repo with one commit
  mkdir -p "$1"
  ( cd "$1" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
    && echo hi > f.txt && git_q add -A && git_q commit -qm init )
}
row_for() {  # row_for <project-dir> <slug>: the porcelain row of that slug
  ( cd "$1" && PATH="$BIN:$PATH" bash "$WT" list --porcelain 2>/dev/null ) | awk -F'\t' -v s="$2" '$1 == s'
}
# A row is sound when it has six fields and none is empty.
check_row() {  # check_row <label> <row>
  awk -F'\t' '{ if (NF != 6) bad = 1; for (i = 1; i <= NF; i++) if ($i == "") bad = 1 } END { exit bad }' <<<"$2" \
    || fail "$1: the row does not have six non-empty fields: $(printf '%s' "$2" | sed -n l)"
}

# --- c05 + c11. a root-only worktree with an empty .wt-slot -------------------
r="$TMP/root"
mkdir -p "$r/.context/worktrees"
printf 'WT_PARTICIPANTS="."\n' > "$r/.context/worktrees/config.env"
printf '.context/worktrees/\n' > "$r/.gitignore"
init_repo "$r"
( cd "$r" && PATH="$BIN:$PATH" bash "$WT" new lr --branch wt/lr --no-infra ) >/dev/null 2>&1 \
  || fail "fixture: new lr failed"
row="$(row_for "$r" lr)"
grep -q 'STRAY-DIR' <<<"$row" \
  && fail "c05: a live root-only worktree was reported as STRAY-DIR: $row"
check_row "c11 empty .wt-slot" "$row"
[[ "$(awk -F'\t' '{print $3}' <<<"$row")" == "wt/lr" ]] \
  || fail "c05: the BRANCH of a root-only worktree must be wt/lr: $row"

# c11, second source: a detached HEAD has no branch name.
git_q -C "$TMP/root-wt-lr" checkout --detach
check_row "c11 detached HEAD" "$(row_for "$r" lr)"

# --- BL-776. a .wt-slot that is not a slot falls back to the claim, else "-" --
# Valid means what `up` accepts: an integer in 1..WT_MAX_SLOTS (default 9).
# A valid .wt-slot still wins over the claim, and a claim out of range is no slot
# either. `08` must be judged without bash's octal error on stderr, and a number
# that wraps 64-bit arithmetic back into range is not a slot.
sd="$TMPDIR/aidex-wt-slots-root"; mkdir -p "$sd"
for c in 'abc|3|3' '0|3|3' '99|3|3' 'abc||-' '2|3|2' 'abc|12|-' '08|3|3' \
         '18446744073709551617|3|3'; do
  IFS='|' read -r file claim want <<<"$c"
  rm -f "$sd"/slot-*
  [[ -n "$claim" ]] && printf '%s lr\n' "$$" > "$sd/slot-$claim"
  printf '%s\n' "$file" > "$TMP/root-wt-lr/.wt-slot"
  got="$(row_for "$r" lr | awk -F'\t' '{print $2}')"
  [[ "$got" == "$want" ]] \
    || fail "BL-776: .wt-slot '$file' with claim '${claim:--}' must list SLOT $want, got '$got'"
  err="$( cd "$r" && PATH="$BIN:$PATH" bash "$WT" list --porcelain 2>&1 >/dev/null )"
  [[ -z "$err" ]] || fail "BL-776: .wt-slot '$file': list wrote to stderr: $err"
done
rm -f "$sd"/slot-*

# --- BL-804. a claim with no directory (MISSING-DIR) shows its slot by the same rule --
# The row printed the claim FILENAME's number raw, so a planted slot-abc showed
# SLOT abc. Like an invalid .wt-slot, an invalid number lists as "-"; the row
# itself stays, since a claim with no directory is a leak the agent must see.
for c in 'abc|-' '0|-' '007|-' '99|-' '3|3'; do
  IFS='|' read -r claim want <<<"$c"
  rm -f "$sd"/slot-*
  printf '%s ghost\n' "$$" > "$sd/slot-$claim"
  row="$(row_for "$r" ghost)"
  check_row "BL-804 slot-$claim" "$row"
  [[ "$(awk -F'\t' '{print $2 "|" $6}' <<<"$row")" == "$want|MISSING-DIR" ]] \
    || fail "BL-804: claim slot-$claim with no directory must list SLOT $want as MISSING-DIR, got: $row"
  err="$( cd "$r" && PATH="$BIN:$PATH" bash "$WT" list 2>&1 >/dev/null )"
  grep -q "claim for 'ghost' (slot $want) has no directory" <<<"$err" \
    || fail "BL-804: claim slot-$claim: the warning must name slot $want, got: $err"
done
rm -f "$sd"/slot-*

# --- c10. a nested participant's branch ---------------------------------------
n="$TMP/nest"
mkdir -p "$n/.context/worktrees"
printf 'WT_PARTICIPANTS="apps/backend"\n' > "$n/.context/worktrees/config.env"
init_repo "$n/apps/backend"
( cd "$n" && PATH="$BIN:$PATH" bash "$WT" new nb --branch wt/nb --no-infra ) >/dev/null 2>&1 \
  || fail "fixture: new nb failed"
[[ "$(row_for "$n" nb | awk -F'\t' '{print $3}')" == "wt/nb" ]] \
  || fail "c10: the BRANCH of a nested participant must be wt/nb: $(row_for "$n" nb)"

# --- the DIRTY column: a participant's work, and a root checkout's, both read YES -
dirty_col() { row_for "$1" "$2" | awk -F'\t' '{print $5}'; }
[[ "$(dirty_col "$n" nb)" == "no" ]] || fail "dirty: a clean nested participant must list no: $(row_for "$n" nb)"
echo wip > "$TMP/nest-wt-nb/backend/wip.txt"
[[ "$(dirty_col "$n" nb)" == "YES" ]] || fail "dirty: untracked work in a participant must list YES: $(row_for "$n" nb)"
# A root-only worktree ("." participant) has its checkout as the participant itself.
[[ "$(dirty_col "$r" lr)" == "no" ]] || fail "dirty: a clean root-only worktree must list no: $(row_for "$r" lr)"
echo wip > "$TMP/root-wt-lr/wip.txt"
[[ "$(dirty_col "$r" lr)" == "YES" ]] || fail "dirty: untracked work in a root-only worktree must list YES: $(row_for "$r" lr)"
# BL-267 shape: $DEST is a checkout of the ROOT repo and the participants lack ".",
# so only the root-checkout status line of DIRTY_LINES can see its work.
rc="$TMP/rc"
mkdir -p "$rc/.context/worktrees"
printf 'WT_PARTICIPANTS="backend"\n' > "$rc/.context/worktrees/config.env"
printf 'backend/\n.context/worktrees/\n.wt-branch\n.wt-slot\n' > "$rc/.gitignore"
init_repo "$rc"; init_repo "$rc/backend"
( cd "$rc" && PATH="$BIN:$PATH" bash "$WT" new rcw --branch wt/rcw --no-infra ) >/dev/null 2>&1 || fail "fixture: new rcw failed"
mv "$TMP/rc-wt-rcw" "$TMP/rc-wt-rcw.stage"
git_q -C "$rc" worktree add -q -b wt/root-rcw "$TMP/rc-wt-rcw"
mv "$TMP/rc-wt-rcw.stage/backend" "$TMP/rc-wt-rcw/backend"
mv "$TMP/rc-wt-rcw.stage/.wt-branch" "$TMP/rc-wt-rcw/.wt-branch" 2>/dev/null
rm -rf "$TMP/rc-wt-rcw.stage"
[[ "$(dirty_col "$rc" rcw)" == "no" ]] || fail "dirty: a clean root checkout must list no: $(row_for "$rc" rcw)"
echo wip > "$TMP/rc-wt-rcw/root-wip.txt"
[[ "$(dirty_col "$rc" rcw)" == "YES" ]] || fail "dirty: untracked work in a root checkout (participants without .) must list YES: $(row_for "$rc" rcw)"

# --- c05 follow-up. a path with regex metacharacters is matched literally ------
# `p[1]` as a grep pattern matches "p1", not "p[1]": the live worktree read as STRAY-DIR.
m="$TMP/p[1]"
mkdir -p "$m/.context/worktrees"
printf 'WT_PARTICIPANTS="."\n' > "$m/.context/worktrees/config.env"
printf '.context/worktrees/\n' > "$m/.gitignore"
init_repo "$m"
( cd "$m" && PATH="$BIN:$PATH" bash "$WT" new mt --branch wt/mt --no-infra ) >/dev/null 2>&1 \
  || fail "fixture: new mt failed"
mrow="$(row_for "$m" mt)"
[[ -n "$mrow" ]] || fail "c05: no row for the worktree under a path with [ ] (its slug was not derived)"
grep -q 'STRAY-DIR' <<<"$mrow" \
  && fail "c05: a live worktree under a path with [ ] was reported as STRAY-DIR: $mrow"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — list rows: a root-only worktree is registered, a nested participant shows its branch, no row has an empty field"
