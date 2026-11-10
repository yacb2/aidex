#!/usr/bin/env bash
# test-close-item-split.sh — BL-646: in a split workspace close-item --sweep refuses a sha that
# lives only on a linked-worktree branch of the sub-repo, says closures are post-merge and names
# the branch (it used to say "run from the worktree", which cannot work there); after the merge
# into the sub-repo main the same close is accepted. Layer: script, temp fixtures only.
set -uo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
# Pinned dates: every sha below is the same on every run, so the crafted clash further down
# either always exists or always fails loudly.
G() { GIT_AUTHOR_DATE="1700000000 +0000" GIT_COMMITTER_DATE="1700000000 +0000" git -c user.email=t@t -c user.name=t "$@"; }

W="$TMP/ws"; S="$W/code"
mkdir -p "$S" "$W/.context/backlog"
G -C "$S" init -q -b main; echo a > "$S/a"; G -C "$S" add a; G -C "$S" commit -qm base
G -C "$W" init -q -b main; echo "code/" > "$W/.gitignore"
G -C "$S" worktree add -q -b sweep "$TMP/wt"
echo b > "$TMP/wt/b"; G -C "$TMP/wt" add b; G -C "$TMP/wt" commit -qm feat
SHA="$(G -C "$TMP/wt" rev-parse HEAD)"
cat > "$W/.context/backlog/bl-001-x.md" <<'ITEM'
---
title: "x"
id: BL-001
status: open
created: 2026-10-02
updated: 2026-10-02
priority: P3
type: improvement
surface: internal
commits: ""
---

# x

## Acceptance
- it works

## Verification
| kind | what | proof |
|---|---|---|
| test | it works | ran |
ITEM
G -C "$W" add -A; G -C "$W" commit -qm ws

echo "close-item split workspace:"
OUT="$(cd "$W" && NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-001 --sweep --no-index --commit "$SHA" 2>&1)"; RC=$?
[[ $RC -ne 0 ]] && ok "unmerged branch sha is refused" || bad "accepted unmerged sha"
[[ "$OUT" == *"branch sweep"* && "$OUT" == *"not yet merged"* ]] && ok "message names the branch and not-yet-merged" || bad "no branch naming: $OUT"
[[ "$OUT" == *"after the merge"* && "$OUT" == *"merge sha"* ]] && ok "message says close post-merge citing the merge sha" || bad "no post-merge guidance: $OUT"
[[ "$OUT" != *"Running from inside the worktree"* ]] && ok "no run-from-worktree advice" || bad "still says run from worktree: $OUT"

G -C "$S" merge -q --no-ff sweep -m merge
MSHA="$(G -C "$S" rev-parse HEAD)"
OUT="$(cd "$W" && NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-001 --sweep --no-index --commit "$MSHA" 2>&1)"; RC=$?
[[ $RC -eq 0 ]] && ok "merge sha accepted after the merge" || bad "merge sha refused ($RC): $OUT"
[[ -f "$W/.context/backlog/_archive/bl-001-x.md" ]] && ok "item archived" || bad "item not archived"

# A ref is checked by its FULL sha, never its abbreviation (BL-926): the root is searched
# first, and a root commit sharing the abbreviation accepted an unmerged branch of code/.
# A 4-hex abbreviation (core.abbrev=4) and a crafted commit make the clash cheap.
G -C "$S" config core.abbrev 4
WS_FULL="$(G -C "$W" rev-parse HEAD)"
CLASH="$(python3 - "$WS_FULL" "$MSHA" "$(G -C "$S" rev-parse 'HEAD^{tree}')" "$(G -C "$S" cat-file --batch-all-objects --batch-check='%(objectname)')" <<'PY'
import hashlib, sys
want, parent, tree, taken = sys.argv[1][:4], sys.argv[2], sys.argv[3], {o[:4] for o in sys.argv[4].split()}
for n in range(0 if want in taken else 10**7):
    body = ("tree %s\nparent %s\nauthor t <t@t> 1700000000 +0000\ncommitter t <t@t> 1700000000 +0000\n\nfeat %d\n" % (tree, parent, n)).encode()
    if hashlib.sha1(b"commit %d\0" % len(body) + body).hexdigest()[:4] == want:
        sys.stdout.buffer.write(body); break
PY
)"
if [[ -z "$CLASH" ]]; then
  bad "fixture: no commit of code/ could be crafted to abbreviate to the root HEAD's ${WS_FULL:0:4} (that prefix is already taken in code/): change the pinned dates"
else
  G -C "$S" branch feat "$(printf '%s\n' "$CLASH" | G -C "$S" hash-object -t commit -w --stdin)"
  sed 's/^id: BL-001$/id: BL-002/' "$W/.context/backlog/_archive/bl-001-x.md" | sed 's/^status: .*/status: open/' > "$W/.context/backlog/bl-002-x.md"
  OUT="$(cd "$S" && NO_COLOR=1 bash "$SCRIPTS/close-item.sh" BL-002 --no-index --commit feat 2>&1)"; RC=$?
  [[ $RC -eq 2 && -f "$W/.context/backlog/bl-002-x.md" && "$OUT" == *"not on the current branch"* ]] \
    && ok "an unmerged ref of code/ whose abbreviation names the root HEAD is refused" || bad "abbreviation clash accepted ($RC): $OUT"
fi

echo "$PASS ok, $FAIL failed"; [[ $FAIL -eq 0 ]]
