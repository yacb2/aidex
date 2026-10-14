#!/usr/bin/env bash
# test-detect-topology.sh — detect-topology.sh reports the facts bootstrap decides on.
# Layer 1 (script, no daemon): a fixture tree is the whole input.

set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

P="$TMP/proj"
mkdir -p "$P/.context" "$P/sub"
git -C "$P" init -q . >/dev/null 2>&1
# worktree-c26: a modern compose filename, and a sub-repo whose .git is a FILE
# (submodule or linked worktree), both invisible to the old patterns.
: > "$P/compose.yaml"
: > "$P/sub/compose.yml"
mkdir -p "$TMP/gitdir"
printf 'gitdir: %s\n' "$TMP/gitdir" > "$P/sub/.git"

out="$(cd "$P" && bash "$SCRIPTS/detect-topology.sh" 2>&1)"
grep -qx 'compose.yaml' <<<"$out" || fail "compose.yaml at the root was not listed: $out"
grep -qx 'sub/compose.yml' <<<"$out" || fail "compose.yml one level down was not listed: $out"
grep -q '^sub/ has its own .git' <<<"$out" || fail "a .git FILE was not reported as a sub-repo: $out"
grep -q '^sub/ — signal(s): own .git' <<<"$out" || fail "a .git FILE was not reported as a service signal: $out"

# A .git FILE that points into <repo>/.git/worktrees/ is a linked worktree, and one into
# .git/modules/ a submodule: neither is "its own .git" (split-git signal), both are named.
git -C "$TMP" init -q other >/dev/null 2>&1
git -C "$TMP/other" -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m i >/dev/null 2>&1
git -C "$TMP/other" worktree add -q "$P/lw" -b lwbranch >/dev/null 2>&1
mkdir -p "$P/sm"; printf 'gitdir: /x/.git/modules/sm\n' > "$P/sm/.git"
out="$(cd "$P" && bash "$SCRIPTS/detect-topology.sh" 2>&1)"
grep -q '^lw/ has its own .git' <<<"$out" && fail "a linked worktree was reported as its own repo: $out"
grep -q '^lw/ — signal(s):.*own .git' <<<"$out" && fail "a linked worktree got an own-.git service signal: $out"
grep -q '^lw/ is a linked worktree of .*other' <<<"$out" || fail "a linked worktree was not named: $out"
grep -q '^sm/ has its own .git' <<<"$out" && fail "a submodule was reported as its own repo: $out"
grep -q '^sm/ is a submodule' <<<"$out" || fail "a submodule was not named: $out"
# The same rule for the root: running from inside a linked worktree.
mkdir -p "$P/lw/.context"
out="$(cd "$P/lw" && bash "$SCRIPTS/detect-topology.sh" 2>&1)"
grep -q 'root has its own .git' <<<"$out" && fail "a linked-worktree root was reported as its own repo: $out"
grep -q 'root is a linked worktree of .*other' <<<"$out" || fail "a linked-worktree root was not named: $out"

if [[ $failures -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — detect-topology: compose.yml/.yaml and a .git file are reported"
