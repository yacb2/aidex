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

# --- c10. a nested participant's branch ---------------------------------------
n="$TMP/nest"
mkdir -p "$n/.context/worktrees"
printf 'WT_PARTICIPANTS="apps/backend"\n' > "$n/.context/worktrees/config.env"
init_repo "$n/apps/backend"
( cd "$n" && PATH="$BIN:$PATH" bash "$WT" new nb --branch wt/nb --no-infra ) >/dev/null 2>&1 \
  || fail "fixture: new nb failed"
[[ "$(row_for "$n" nb | awk -F'\t' '{print $3}')" == "wt/nb" ]] \
  || fail "c10: the BRANCH of a nested participant must be wt/nb: $(row_for "$n" nb)"

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
