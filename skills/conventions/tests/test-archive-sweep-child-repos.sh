#!/usr/bin/env bash
# archive-sweep.py status drift sees commits that live in child repos (BL-606).
#
# The sweep looked for .git only in the dir holding .context/. In the walkcut_ws layout
# (no root repo, code in walkcut/) that disabled status drift entirely; in the
# planning-repo layout (root repo plus code repos as child dirs) a commit that landed in
# a child repo was never seen. Same defect detect-resolved.py had (BL-603, 65597a1).
#
# Layer: script over a temp fixture with real git repos; the decision is which repos the
# sweep asks, and only real repos can answer.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AS="$HERE/../scripts/archive-sweep.py"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

mk_repo_commit() {  # mk_repo_commit <dir> -> prints HEAD sha
  mkdir -p "$1"
  git -C "$1" init -q
  echo "$1" > "$1/f.txt"  # distinct per repo, or two repos get one identical sha
  git -C "$1" -c user.name=t -c user.email=t@t add f.txt
  git -C "$1" -c user.name=t -c user.email=t@t commit -qm init
  git -C "$1" rev-parse HEAD
}

mk_item() {  # mk_item <ctx> <commits>
  mkdir -p "$1/backlog"
  cat > "$1/backlog/2026-01-01-bl-001-a.md" <<ITEM
---
title: "an item"
id: BL-001
status: open
commits: "$2"
---

# an item
ITEM
}

drift_paths() {  # drift_paths <ctx> -> prints status_drift paths, one per line
  python3 "$AS" "$1" --json "$TMP/out.json" >/dev/null 2>&1 \
    || { echo "RUN-FAILED"; return; }
  python3 -c 'import json,sys
for r in json.load(open(sys.argv[1]))["status_drift"]: print(r["path"])' "$TMP/out.json"
}

# --- layout A: .context/ in a non-git parent, the code repo in a child dir ----------
WS="$TMP/ws-a"
SHA="$(mk_repo_commit "$WS/code")"
mk_item "$WS/.context" "$SHA"
got="$(drift_paths "$WS/.context")"
if [[ "$got" == "backlog/2026-01-01-bl-001-a.md" ]]; then
  pass "non-git parent: a commit in a child repo is seen as landed"
else
  fail "non-git parent: status drift missed the child-repo commit (got: '${got}')"
fi

# --- layout B: root planning repo plus a child code repo; commits in both -----------
WS="$TMP/ws-b"
ROOT_SHA="$(mk_repo_commit "$WS")"
CHILD_SHA="$(mk_repo_commit "$WS/code")"
mk_item "$WS/.context" "$ROOT_SHA $CHILD_SHA"
got="$(drift_paths "$WS/.context")"
if [[ "$got" == "backlog/2026-01-01-bl-001-a.md" ]]; then
  pass "root repo plus child repo: commits are checked in the union of both"
else
  fail "root repo plus child repo: status drift missed a commit (got: '${got}')"
fi

# --- layout C: no repo anywhere, nothing to archive ----------------------------------
# A clean run must not claim "no status drift" when drift was never checked.
WS="$TMP/ws-c"
mk_item "$WS/.context" "abcdef1234567"
out="$(python3 "$AS" "$WS/.context" 2>&1)"
if grep -q "no status drift" <<<"$out" || ! grep -q "status drift was not checked" <<<"$out"; then
  fail "no repo at all: a clean run claims no status drift (got: '${out//$'\n'/ | }')"
else
  pass "no repo at all: a clean run says status drift was not checked"
fi

# --- layout D: a child repo, the cited commit not in it: drift WAS checked ------------
WS="$TMP/ws-d"
mk_repo_commit "$WS/code" >/dev/null
mk_item "$WS/.context" "abcdef1234567"
out="$(python3 "$AS" "$WS/.context" 2>&1)"
if grep -q "no status drift" <<<"$out" && ! grep -q "status drift was not checked" <<<"$out"; then
  pass "child repo, nothing landed: a clean run says no status drift"
else
  fail "child repo, nothing landed: the clean line does not say drift was checked (got: '${out//$'\n'/ | }')"
fi

# --- layout E: the only .git is a dangling worktree pointer: no repo was checked ----
WS="$TMP/ws-e"
mkdir -p "$WS/code"; echo "gitdir: $TMP/nonexistent/wt" > "$WS/code/.git"
mk_item "$WS/.context" "abcdef1234567"
out="$(python3 "$AS" "$WS/.context" 2>&1)"
if grep -q "status drift was not checked" <<<"$out"; then
  pass "dangling child .git: a clean run says status drift was not checked"
else
  fail "dangling child .git: counted as a repo nobody could ask (got: '${out//$'\n'/ | }')"
fi

if [[ $FAILURES -gt 0 ]]; then printf '\n%d check(s) failed\n' "$FAILURES"; exit 1; fi
printf '\nOK: archive-sweep checks status drift in the root repo and every child repo\n'
