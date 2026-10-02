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
G() { git -c user.email=t@t -c user.name=t "$@"; }

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

echo "$PASS ok, $FAIL failed"; [[ $FAIL -eq 0 ]]
