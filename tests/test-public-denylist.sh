#!/usr/bin/env bash
# test-public-denylist.sh — no private term reaches the public aidex repo through the tree,
# a commit message or release notes. The terms live in a PRIVATE list read at runtime
# (one POSIX ERE per line, case-insensitive, '#' and blank lines ignored); this file holds
# none, and its fixtures use invented words.
#
#   bash tests/test-public-denylist.sh                    self-test, canary, then the tree
#   bash tests/test-public-denylist.sh --messages <revs>  commit messages (git log args)
#   bash tests/test-public-denylist.sh --stdin            piped text (release notes)
#
# List: $AIDEX_PUBLIC_DENYLIST, else <main checkout>/../.claude/public-denylist.txt resolved
# from the git COMMON dir, because a relative ../.claude does not exist from a linked worktree.
# No list: the default mode prints "SKIP: no denylist" and exits 0 (public clones stay green);
# --messages and --stdin exit 1, so .githooks/pre-push and the release flow refuse.
# No \b in any pattern: git grep -E matches nothing with it here; use (^|[^A-Za-z0-9]).
# Layer: real git grep / grep over throwaway repos and lists; nothing is stubbed.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SELF="$ROOT/tests/test-public-denylist.sh"
common="$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
LIST="${AIDEX_PUBLIC_DENYLIST:-${common:+$(dirname "$common")/../.claude/public-denylist.txt}}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/denylist.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# CRs dropped first: a CRLF list would otherwise ask for a CR after every term. A blank
# line is match-all: drop it.
patterns() { tr -d '\r' < "$1" | grep -vE '^[[:space:]]*(#|$)' > "$2"; }
scan_text() { grep -inE -f "$1"; }   # stdin; exit 0 = hit, 1 = clean, 2 = grep cannot read the list
scan_tree() { git -C "$2" grep --untracked -inE -f "$1"; }   # untracked files too
hit_messages() { # $1 patterns, rest git-log args; exit 0 = hit, 1 = clean, 2 = git failed, 3 = bad list
  local p="$1" log rc=0; shift
  log="$(git log --format=%B "$@")" || return 2
  printf '%s\n' "$log" | scan_text "$p" >/dev/null || rc=$?
  [[ $rc -eq 1 ]] && return 1
  [[ $rc -eq 0 ]] || return 3
  for c in $(git rev-list "$@"); do
    git log -1 --format=%B "$c" | scan_text "$p" | sed "s/^/$(git rev-parse --short "$c"): /"
  done
  return 0
}
need_list() {
  [[ -f "$LIST" ]] || { echo "public-denylist: no denylist at ${LIST:-<unresolved>}" >&2; exit 1; }
  patterns "$LIST" "$TMP/p"
  [[ -s "$TMP/p" ]] || { echo "public-denylist: denylist $LIST has no entries" >&2; exit 1; }
}

case "${1:-}" in
  --stdin)
    need_list
    scan_text "$TMP/p"; rc=$?
    [[ $rc -eq 1 ]] && exit 0
    if [[ $rc -eq 0 ]]; then echo "public-denylist: listed term in stdin" >&2
    else echo "public-denylist: grep cannot read the denylist $LIST" >&2; fi
    exit 1 ;;
  --messages)
    shift; need_list
    hit_messages "$TMP/p" "$@"; rc=$?
    [[ $rc -eq 1 ]] && exit 0
    [[ $rc -eq 0 ]] && echo "public-denylist: listed term in a commit message" >&2
    [[ $rc -eq 2 ]] && echo "public-denylist: git log $* failed" >&2
    [[ $rc -eq 3 ]] && echo "public-denylist: grep cannot read the denylist $LIST" >&2
    exit 1 ;;
  "") ;;
  *) echo "usage: $0 [--messages <rev-range>|--stdin]" >&2; exit 64 ;;
esac

# --- self-test: invented terms in a throwaway repo and list -------------------------------
FAIL=0
fail() { echo "FAIL: $*"; FAIL=$((FAIL + 1)); }
printf '# comment #|.\n\nzorblax\n(^|[^A-Za-z0-9])QQX-[0-9]\n' > "$TMP/list"
patterns "$TMP/list" "$TMP/fp"
for line in "Zorblax here" "ZORBLAX" "see QQX-12" "QQX-1 at start"; do
  printf '%s\n' "$line" | scan_text "$TMP/fp" >/dev/null || fail "stdin: '$line' not flagged"
done
for line in "zorbla x" "AQQX-1" "QQX-a" "# comment" ""; do
  printf '%s\n' "$line" | scan_text "$TMP/fp" >/dev/null && fail "stdin: '$line' flagged"
done
F="$TMP/repo"; git init -q -b main "$F" && cd "$F" || exit 1
git config user.email t@t && git config user.name t
echo clean > a && git add a && git commit -qm "init clean"
scan_tree "$TMP/fp" "$F" >/dev/null && fail "tree: clean tree flagged"
echo "a zorblax note" > new.txt
scan_tree "$TMP/fp" "$F" >/dev/null || fail "tree: untracked file with a term not flagged"
rm new.txt
BASE="$(git rev-parse HEAD)"
echo b > b && git add b && git commit -qm "feat: fixes QQX-7"
HIT="$(git rev-parse HEAD)"
echo c > c && git add c && git commit -qm "feat: clean"
TIP="$(git rev-parse HEAD)"
export AIDEX_PUBLIC_DENYLIST="$TMP/list"
bash "$SELF" --messages "$BASE..$TIP" >/dev/null 2>&1 && fail "messages: term in range not flagged"
bash "$SELF" --messages "$HIT..$TIP" >/dev/null 2>&1 || fail "messages: clean range flagged"
echo "release notes: zorblax" | bash "$SELF" --stdin >/dev/null 2>&1 && fail "stdin mode: term not flagged"
echo "release notes: generic" | bash "$SELF" --stdin >/dev/null 2>&1 || fail "stdin mode: clean text flagged"
# the real hook, fed git's pre-push stdin protocol (a non-main ref, so only this gate applies)
Z=0000000000000000000000000000000000000000
push() { printf 'refs/heads/x %s refs/heads/x %s\n' "$1" "$2" | bash "$ROOT/.githooks/pre-push" origin url >/dev/null 2>&1; }
push "$TIP" "$HIT" || fail "pre-push: clean new commits refused"
push "$TIP" "$BASE" && fail "pre-push: term in a pushed message allowed"
push "$TIP" "$Z" && fail "pre-push: first push with a term allowed"
push "$TIP" 1111111111111111111111111111111111111111 && fail "pre-push: a term over an unfetched remote sha allowed"
AIDEX_PUBLIC_DENYLIST="$TMP/absent" push "$TIP" "$HIT" && fail "pre-push: missing denylist allowed"
AIDEX_PUBLIC_DENYLIST="$TMP/absent" bash "$SELF" --stdin </dev/null >/dev/null 2>&1 && fail "stdin mode: missing denylist passed"
# a list grep cannot read fails closed: a malformed ERE (grep exit 2), no entries, CRLF ends
printf 'zorblax\nfoo(bar\n' > "$TMP/bad"; printf '# only a comment\n\n' > "$TMP/none"; printf 'zorblax\r\n' > "$TMP/crlf"
for m in --stdin --messages; do   # exits 1 and names the list as the cause
  out="$(echo "release notes: zorblax" | AIDEX_PUBLIC_DENYLIST="$TMP/bad" bash "$SELF" $m "$BASE..$TIP" 2>&1)" && fail "$m: malformed list passed"
  [[ "$out" == *"grep cannot read the denylist"* ]] || fail "$m: malformed list not named: $out"
done
AIDEX_PUBLIC_DENYLIST="$TMP/none" bash "$SELF" --messages "$HIT..$TIP" >/dev/null 2>&1 && fail "messages: comments-only list passed"
echo "release notes: generic" | AIDEX_PUBLIC_DENYLIST="$TMP/none" bash "$SELF" --stdin >/dev/null 2>&1 && fail "stdin mode: comments-only list passed"
echo "release notes: zorblax" | AIDEX_PUBLIC_DENYLIST="$TMP/crlf" bash "$SELF" --stdin >/dev/null 2>&1 && fail "stdin mode: CRLF list did not flag its term"
unset AIDEX_PUBLIC_DENYLIST
cd "$ROOT" || exit 1
[[ $FAIL -eq 0 ]] || { echo "$FAIL self-test failure(s)"; exit 1; }

# --- the real list -------------------------------------------------------------------------
[[ -f "$LIST" ]] || { echo "SKIP: no denylist"; exit 0; }
patterns "$LIST" "$TMP/p"
first="$(head -n 1 "$TMP/p")"
[[ -n "$first" ]] || { echo "FAIL: denylist $LIST has no entries"; exit 1; }
# canary: a line built from the first entry (kept a plain literal) must bite both matchers
C="$TMP/canary"; git init -q "$C" && printf 'x %s x\n' "$first" > "$C/canary.txt"
printf 'x %s x\n' "$first" | scan_text "$TMP/p" >/dev/null || { echo "FAIL: canary not flagged by grep"; exit 1; }
scan_tree "$TMP/p" "$C" >/dev/null || { echo "FAIL: canary not flagged by git grep"; exit 1; }
if scan_tree "$TMP/p" "$ROOT"; then echo "FAIL: listed term in the aidex tree (above)"; exit 1; fi
echo "OK: public denylist ($(wc -l < "$TMP/p" | tr -d ' ') terms): self-test, canary, tree clean"
