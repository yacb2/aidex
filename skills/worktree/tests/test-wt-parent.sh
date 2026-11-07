#!/usr/bin/env bash
# test-wt-parent.sh — WT_PARENT moves where worktrees live, and every script that
# finds them by directory follows it.
#
#   worktree.sh    DEST_FOR and the `list` glob were hardcoded to <root>/../<project>-wt-*,
#                  so a project could not keep its worktrees in a folder of their own.
#   orphan-sweep   builds its "live on disk" set from the same glob: a worktree under
#                  WT_PARENT would have its Docker resources reported as ORPHAN.
#   leftover-sweep scans the same wrappers and, run from inside one, finds the
#                  workspace by looking beside it.
#
# Behavioural, no daemon: docker is a stub.
# Run with: bash skills/worktree/tests/test-wt-parent.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
WT="$DIR/../scripts/worktree.sh"
ORPHAN="$DIR/../scripts/orphan-sweep.sh"
LEFTOVER="$DIR/../scripts/leftover-sweep.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/slots"; mkdir -p "$TMPDIR"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/docker" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "info") exit 0 ;;
  *"ps -a"*) printf '%s\t%s\t\n' root-wt-p1 "" ;;
  *"volume ls"*) echo root-wt-p1_db ;;
  *) exit 0 ;;
esac
FAKE
chmod +x "$BIN/docker"
export PATH="$BIN:$PATH"

git_q() { /usr/bin/git "$@" >/dev/null 2>&1; }

r="$TMP/root"
mkdir -p "$r/.context/worktrees"
printf 'WT_PARTICIPANTS="."\nWT_PARENT="../wts"\n' > "$r/.context/worktrees/config.env"
printf '.context/worktrees/\n' > "$r/.gitignore"
( cd "$r" && git_q init . && git_q config user.email t@example.com && git_q config user.name t \
  && echo hi > f.txt && git_q add -A && git_q commit -qm init )

# --- new creates WT_PARENT and lands there ------------------------------------
[[ -e "$TMP/wts" ]] && fail "fixture: wts must not exist before new"
( cd "$r" && bash "$WT" new p1 --branch wt/p1 --no-infra ) >/dev/null 2>&1 || fail "new p1 failed"
[[ -d "$TMP/wts/root-wt-p1" ]] || fail "new did not create the worktree under WT_PARENT"
[[ -e "$TMP/root-wt-p1" ]] && fail "new still created the sibling path"

# --- list sees it, and only this project's wrappers ---------------------------
mkdir -p "$TMP/wts/other-wt-x"
rows="$(cd "$r" && bash "$WT" list --porcelain 2>/dev/null)"
row="$(awk -F'\t' '$1 == "p1"' <<<"$rows")"
[[ -n "$row" ]] || fail "list did not show the worktree under WT_PARENT: $rows"
[[ "$(awk -F'\t' '{print $6}' <<<"$row")" == "$TMP/wts/root-wt-p1" ]] || fail "list DIR is not the WT_PARENT path: $row"
grep -q 'STRAY-DIR' <<<"$row" && fail "a live worktree under WT_PARENT read as STRAY-DIR: $row"
grep -q 'other-wt-x' <<<"$rows" && fail "list showed another project's wrapper: $rows"
[[ "$(wc -l <<<"$rows" | tr -d ' ')" -eq 1 ]] || fail "list must show exactly one row: $rows"

# --- orphan-sweep counts it as live -------------------------------------------
out="$(cd "$r" && bash "$ORPHAN" 2>&1)"
grep -q 'root-wt-p1' <<<"$out" && fail "orphan-sweep reported a live WT_PARENT worktree as orphan: $out"

# --- leftover-sweep scans WT_PARENT, from the root and from inside a wrapper ---
mkdir -p "$TMP/wts/root-wt-empty/backend"
out="$(cd "$r" && bash "$LEFTOVER" 2>&1)"
grep -q "removed empty leftover: $TMP/wts/root-wt-empty" <<<"$out" || fail "leftover-sweep missed an empty wrapper under WT_PARENT: $out"
[[ -d "$TMP/wts/other-wt-x" ]] || fail "leftover-sweep removed another project's wrapper"
mkdir -p "$TMP/wts/root-wt-empty2"
out="$(cd "$TMP/wts/root-wt-p1" && bash "$LEFTOVER" 2>&1)"
grep -q "removed empty leftover: $TMP/wts/root-wt-empty2" <<<"$out" || fail "leftover-sweep run inside a WT_PARENT wrapper did not find its workspace: $out"

# --- down removes it ------------------------------------------------------------
( cd "$r" && bash "$WT" down p1 ) >/dev/null 2>&1 || fail "down p1 failed"
[[ -e "$TMP/wts/root-wt-p1" ]] && fail "down left the WT_PARENT worktree on disk"

if [[ "$failures" -eq 0 ]]; then echo "PASS: test-wt-parent.sh"; else echo "$failures failure(s)"; exit 1; fi
