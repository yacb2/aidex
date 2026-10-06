#!/usr/bin/env bash
# test-pre-push-version-guard.sh — .githooks/pre-push refuses a push to main that
# carries new commits without a new plugin version and its v<version> tag.
# Why: 276 commits reached origin between v1.4.0 and v1.5.0 with plugin.json still
# at 1.4.0, so an installed plugin had no version to update to (2026-10-06).
# Layer: the real hook fed git's pre-push stdin protocol in a throwaway repo.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HERE/.githooks/pre-push"
FAIL=0
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/prepush.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q -b main repo && cd repo || exit 1
git config user.email t@t && git config user.name t
mkdir .claude-plugin
setver() { printf '{\n  "name": "x",\n  "version": "%s"\n}\n' "$1" > .claude-plugin/plugin.json; }
setver 1.0.0; git add -A; git commit -qm init; git tag v1.0.0
BASE="$(git rev-parse HEAD)"
Z=0000000000000000000000000000000000000000

push() { # $1 local sha, $2 remote sha, $3 remote ref
  printf 'refs/heads/main %s %s %s\n' "$1" "$3" "$2" | bash "$HOOK" origin url >/dev/null 2>&1
}

echo a > a; git add a; git commit -qm "feat: a"
push "$(git rev-parse HEAD)" "$BASE" refs/heads/main && fail "new commits, same version: push allowed"

setver 1.1.0; git add -A; git commit -qm "chore(release): v1.1.0"
push "$(git rev-parse HEAD)" "$BASE" refs/heads/main && fail "version bumped but no v1.1.0 tag: push allowed"

git tag v1.1.0
push "$(git rev-parse HEAD)" "$BASE" refs/heads/main || fail "version bumped and tagged: push refused"

push "$(git rev-parse HEAD)" "$BASE" refs/heads/other || fail "push to a non-main branch refused"
push "$BASE" "$BASE" refs/heads/main || fail "nothing new: push refused"
push "$Z" "$BASE" refs/heads/main || fail "branch delete refused"

[ "$FAIL" -eq 0 ] && echo "ok: pre-push version guard (6 cases)" || { echo "$FAIL failure(s)"; exit 1; }
