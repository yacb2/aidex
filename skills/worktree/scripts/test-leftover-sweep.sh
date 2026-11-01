#!/usr/bin/env bash
# test-leftover-sweep.sh — leftover-sweep.sh removes empty `<ws>-wt-*` wrapper dirs,
# reports non-empty unregistered ones, drops dead worktree records under those wrappers
# only, and leaves live worktrees, foreign siblings and other workspaces alone.
# Real git, no Docker. Each block builds its own workspace.
#
# Run with: bash skills/worktree/scripts/test-leftover-sweep.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/leftover-sweep.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# mkws NAME — split workspace $TMP/NAME/ws with config.env and sub-repo `app`; sets P and WS
mkws() {
  P="$TMP/$1/projects"; WS="$P/alpha"
  mkdir -p "$WS/.context/worktrees"; : > "$WS/.context/worktrees/config.env"
  git init -q "$WS/app" && git -C "$WS/app" commit -q --allow-empty -m init
}
run() { bash "$SCRIPT" --root "$WS" 2>&1; }

# --- clean case ---
mkws clean
out="$(run)"
[[ "$out" == "no worktree leftovers" ]] || fail "clean: got [$out]"

# --- main block: empty, nested empty, content, live, dead record, foreign ---
mkws main
mkdir -p "$P/alpha-wt-empty" "$P/alpha-wt-nested/a/b" "$P/alpha-wt-full/sub" "$P/beta-wt-empty" "$P/alphabet" "$P/alpha-int-empty"
echo x > "$P/alpha-wt-full/sub/file.txt"
mkdir -p "$P/alpha-wt-live"
git -C "$WS/app" worktree add -q -b live "$P/alpha-wt-live/app"
git -C "$WS/app" worktree add -q -b dead "$P/alpha-wt-dead/app"
rm -rf "$P/alpha-wt-dead/app"
out="$(run)"; rc=$?
[[ $rc -eq 0 ]] || fail "main: exit code $rc"
[[ ! -e "$P/alpha-wt-empty" && "$out" == *"removed empty leftover: $P/alpha-wt-empty"* ]] || fail "(a) empty wrapper: $out"
[[ ! -e "$P/alpha-wt-nested" ]] || fail "(b) nested-empty wrapper not removed"
[[ ! -e "$P/alpha-wt-dead" ]] || fail "(e) wrapper of dead record not removed"
[[ -f "$P/alpha-wt-full/sub/file.txt" ]] || fail "(c) wrapper with file was touched"
[[ "$out" == *"LEFTOVER (not empty, ask the owner): $P/alpha-wt-full"* ]] || fail "(c) no LEFTOVER line: $out"
[[ "$out" == *"entries: sub "* ]] || fail "(c) entries not listed exactly: $out"
[[ -d "$P/alpha-wt-live/app" && "$out" != *"alpha-wt-live"* ]] || fail "(d) live worktree touched or printed: $out"
[[ -d "$P/beta-wt-empty" && -d "$P/alphabet" && -d "$P/alpha-int-empty" ]] || fail "(f) non-wt sibling removed"
[[ "$out" != *beta-wt-empty* && "$out" != *alphabet* && "$out" != *alpha-int-empty* ]] || fail "(f) non-wt sibling printed: $out"
[[ "$(git -C "$WS/app" worktree list --porcelain)" != *prunable* ]] || fail "(e) prunable record remains"
[[ "$out" == *"pruned dead worktree record: $P/alpha-wt-dead/app"* ]] || fail "(e) no prune line: $out"
[[ "$out" != *"no worktree leftovers"* ]] || fail "findings printed the clean line"

# --- near miss: empty alpha-wt-x beside live alpha-wt-x2/app ---
mkws near
mkdir -p "$P/alpha-wt-x" "$P/alpha-wt-x2"
git -C "$WS/app" worktree add -q -b x2 "$P/alpha-wt-x2/app"
out="$(run)"
[[ ! -e "$P/alpha-wt-x" ]] || fail "near: alpha-wt-x not removed"
[[ -d "$P/alpha-wt-x2/app" && "$out" != *alpha-wt-x2* ]] || fail "near: alpha-wt-x2 touched or printed: $out"

# --- worktree registered exactly at the candidate (root-checkout shape) ---
mkws rootshape
git -C "$WS/app" worktree add -q -b rootwt "$P/alpha-wt-rootshape"
out="$(run)"
[[ -d "$P/alpha-wt-rootshape" && "$out" == "no worktree leftovers" ]] || fail "rootshape: $out"

# --- F2: a dead record outside the wrappers is left alone ---
mkws outside
git -C "$WS/app" worktree add -q -b elsewhere "$TMP/outside/elsewhere/x"
rm -rf "$TMP/outside/elsewhere/x"
out="$(run)"
[[ "$(git -C "$WS/app" worktree list --porcelain)" == *"$TMP/outside/elsewhere/x"* ]] || fail "outside: foreign record pruned"
[[ "$out" == *"prunable record outside the workspace wrappers (left alone): $TMP/outside/elsewhere/x"* ]] || fail "outside: not listed: $out"

# --- N1: relative gitdir (worktree.useRelativePaths) is matched too ---
mkws rel
git -C "$WS/app" -c worktree.useRelativePaths=true worktree add -q -b relwt "$P/alpha-wt-rel/app"
rm -rf "$P/alpha-wt-rel/app"
out="$(run)"
[[ "$(git -C "$WS/app" worktree list --porcelain)" != *prunable* && ! -e "$P/alpha-wt-rel" ]] || fail "rel: $out"

# --- F3: a child with a broken .git does not kill the sweep ---
mkws broken
mkdir -p "$WS/brokenrepo" "$P/alpha-wt-empty"
echo "gitdir: /nonexistent" > "$WS/brokenrepo/.git"
out="$(run)"; rc=$?
[[ $rc -eq 0 ]] || fail "broken: rc $rc: $out"
[[ ! -e "$P/alpha-wt-empty" ]] || fail "broken: empty wrapper not removed: $out"
[[ "$out" == *"broken git repo (skipped): $WS/brokenrepo"* ]] || fail "broken: repo not named: $out"

# --- F4: an empty wrapper that cannot be rmdir'd is a LEFTOVER, not "removed" ---
mkws ro
mkdir -p "$P/alpha-wt-ro/outer/inner"; chmod 555 "$P/alpha-wt-ro/outer"
out="$(run)"
chmod 755 "$P/alpha-wt-ro/outer"
[[ -e "$P/alpha-wt-ro" && "$out" != *"removed empty leftover"* && "$out" == *"LEFTOVER"*"alpha-wt-ro"* ]] || fail "ro: $out"

# --- emptiness: .DS_Store is noise; a symlink or a dotfile is content ---
mkws noise
mkdir -p "$P/alpha-wt-ds/a" "$P/alpha-wt-link/empty" "$P/alpha-wt-dot"
: > "$P/alpha-wt-ds/.DS_Store"; : > "$P/alpha-wt-ds/a/.DS_Store"
ln -s /nonexistent "$P/alpha-wt-link/l"
: > "$P/alpha-wt-dot/.wt-slot"
out="$(run)"
[[ ! -e "$P/alpha-wt-ds" ]] || fail "ds: .DS_Store-only wrapper not removed: $out"
[[ -L "$P/alpha-wt-link/l" && -d "$P/alpha-wt-link/empty" && "$out" == *"LEFTOVER"*"alpha-wt-link"* ]] || fail "symlink-only wrapper: $out"
[[ -f "$P/alpha-wt-dot/.wt-slot" && "$out" == *"LEFTOVER"*"alpha-wt-dot"* ]] || fail "dotfile-only wrapper: $out"

# --- F1: no --root, from inside a worktree's sub-repo (gt3 shape) and from the root ---
P="$TMP/gt3/projects"; WS="$P/alpha"
mkdir -p "$WS/.context/worktrees"; : > "$WS/.context/worktrees/config.env"
git init -q "$WS" && git -C "$WS" commit -q --allow-empty -m init
git init -q "$WS/aidex" && git -C "$WS/aidex" commit -q --allow-empty -m init
git -C "$WS" worktree add -q -b rootx "$P/alpha-wt-x"
git -C "$WS/aidex" worktree add -q -b aidexx "$P/alpha-wt-x/aidex"
mkdir -p "$WS/aidex-notes" "$P/alpha-wt-old"
out="$(cd "$P/alpha-wt-x/aidex" && bash "$SCRIPT" 2>&1)"; rc=$?
[[ $rc -eq 0 && -d "$WS/aidex-notes" ]] || fail "gt3: workspace folder touched (rc $rc): $out"
[[ ! -e "$P/alpha-wt-old" ]] || fail "gt3: alpha-wt-old not removed: $out"
[[ -d "$P/alpha-wt-x/aidex" && "$out" != *alpha-wt-x* ]] || fail "gt3: live wrapper touched or printed: $out"
mkdir -p "$P/alpha-wt-old2"
out="$(cd "$WS" && bash "$SCRIPT" 2>&1)"
[[ ! -e "$P/alpha-wt-old2" && -d "$WS/aidex-notes" ]] || fail "gt3 from root: $out"

# --- N3: root rule order: from the wrapper, a symlinked .context must not make the wrapper the root ---
mkdir -p "$P/alpha-wt-old3"
ln -s "$WS/.context" "$P/alpha-wt-x/.context"
out="$(cd "$P/alpha-wt-x" && bash "$SCRIPT" 2>&1)"
[[ ! -e "$P/alpha-wt-old3" ]] || fail "wrapper-cwd root: $out"
rm "$P/alpha-wt-x/.context"

# --- no config: nothing touched ---
mkws noconf
rm "$WS/.context/worktrees/config.env"; mkdir -p "$P/alpha-wt-empty"
out="$(run)"
[[ -d "$P/alpha-wt-empty" && "$out" == "no worktree config at $WS; leftover sweep skipped" ]] || fail "noconf: $out"

if [[ $failures -eq 0 ]]; then echo "ok: leftover-sweep"; exit 0; fi
echo "$failures failure(s)"; exit 1
