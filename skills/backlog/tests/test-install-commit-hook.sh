#!/usr/bin/env bash
# test-install-commit-hook.sh — the post-commit hook lands where git actually reads hooks from
# (backlog-c17): the hooksPath directory when core.hooksPath is set, the common hooks
# directory from a linked worktree. `--git-dir`/hooks was neither.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
G() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

echo "install-commit-hook.sh:"
R="$TMP/repo"; git init -q "$R"; ( cd "$R" && G commit -q --allow-empty -m init )
( cd "$R" && git config core.hooksPath .githooks && bash "$SCRIPTS/install-commit-hook.sh" >/dev/null 2>&1 )
[[ -x "$R/.githooks/post-commit" && ! -e "$R/.git/hooks/post-commit" ]] \
  && ok "hooksPath: the hook goes to the directory git reads" || bad "hooksPath: $(ls "$R/.githooks" "$R/.git/hooks" 2>&1 | tr '\n' ' ')"
( cd "$R" && bash "$SCRIPTS/install-commit-hook.sh" --remove >/dev/null 2>&1 )
[[ -f "$R/.githooks/post-commit" ]] && ! grep -q 'aidex commit-trailer' "$R/.githooks/post-commit" \
  && ok "hooksPath: --remove strips the block from the same directory" || bad "hooksPath: --remove left the block or the file"

R2="$TMP/repo2"; git init -q "$R2"; ( cd "$R2" && G commit -q --allow-empty -m init && G worktree add -q "$TMP/wt" -b wtb )
( cd "$TMP/wt" && bash "$SCRIPTS/install-commit-hook.sh" >/dev/null 2>&1 ); RC=$?
[[ $RC -eq 0 && -x "$R2/.git/hooks/post-commit" ]] \
  && ok "linked worktree: the hook is written to the common hooks directory" || bad "worktree: rc=$RC $(ls "$R2/.git/hooks" | tr '\n' ' ')"

echo; [[ $FAIL -eq 0 ]] && { echo "OK — install-commit-hook: $PASS cells"; exit 0; }; echo "$FAIL failure(s)"; exit 1
