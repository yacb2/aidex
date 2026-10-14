#!/usr/bin/env bash
# test-worktree-multi.sh — lifecycle test for worktree-multi.sh in a temp
# split-git workspace fixture (two repos + an unversioned wrapper file):
# create -> assert worktrees/branch/links -> remove -> assert clean + refusal
# behavior on dirty trees is git's own (not exercised destructively here).
#
# Run with: bash skills/worktree/scripts/test-worktree-multi.sh

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/worktree-multi.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fixture: split-git workspace — root has NO .git; two participant repos; wrapper file.
WS="$TMP/ws"
mkdir -p "$WS/backend" "$WS/frontend"
for r in backend frontend; do
  git -C "$WS/$r" init -q
  git -C "$WS/$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
done
echo "services: {}" > "$WS/docker-compose.yml"

cd "$WS"
DEST="$TMP/ws-wt-feat-x"

# --- create ---
out="$(bash "$SCRIPT" create --slug feat-x --branch feat/x \
  --repo backend --repo frontend --link docker-compose.yml --dest "$DEST" 2>/dev/null)"
[[ "$out" == "$DEST" ]] || fail "create: expected dest path on stdout, got: $out"
[[ -f "$DEST/backend/.git" && -f "$DEST/frontend/.git" ]] || fail "create: missing worktree .git markers"
b1="$(git -C "$DEST/backend" branch --show-current)"
b2="$(git -C "$DEST/frontend" branch --show-current)"
[[ "$b1" == "feat/x" && "$b2" == "feat/x" ]] || fail "create: expected branch feat/x in both, got $b1 / $b2"
[[ -L "$DEST/docker-compose.yml" ]] || fail "create: wrapper symlink missing"
n_wt="$(git -C "$WS/backend" worktree list | wc -l | tr -d ' ')"
[[ "$n_wt" == "2" ]] || fail "create: backend should have 2 worktrees (main + wt), got $n_wt"

# --- create refuses existing dest ---
if bash "$SCRIPT" create --slug feat-x --branch feat/x --repo backend --dest "$DEST" >/dev/null 2>&1; then
  fail "create: should refuse an existing destination"
fi

# --- create validates participants before mutating ---
if bash "$SCRIPT" create --slug feat-y --branch feat/y --repo nonexistent --dest "$TMP/ws-wt-feat-y" >/dev/null 2>&1; then
  fail "create: should refuse a nonexistent participant"
fi
[[ ! -e "$TMP/ws-wt-feat-y" ]] || fail "create: failed validation must not leave a dest behind"

# --- the direct-invocation warning points at a command that exists ---
# It printed `worktree.sh create|remove`, which worktree.sh rejects with usage (exit 2).
for pair in create:new remove:down; do
  c="${pair%%:*}" want="${pair#*:}"
  sub="$(bash "$SCRIPT" "$c" 2>&1 >/dev/null | sed -n 's/.*Use instead: *worktree\.sh \([a-z]*\).*/\1/p')"
  [[ "$sub" == "$want" ]] || fail "warning on direct $c suggests 'worktree.sh $sub', want 'worktree.sh $want'"
done

# --- remove ---
bash "$SCRIPT" remove --slug feat-x --dest "$DEST" >/dev/null 2>&1 || fail "remove: exited non-zero"
[[ ! -e "$DEST" ]] || fail "remove: dest still exists"
n_wt="$(git -C "$WS/backend" worktree list | wc -l | tr -d ' ')"
[[ "$n_wt" == "1" ]] || fail "remove: backend should be back to 1 worktree, got $n_wt"

# =====================================================================
# Teardown coupling on remove.
#
# Regression (field-observed 2026-07-25): `remove` deleted the directory and
# only *printed* the teardown as a next step. Skipping it stranded the Docker
# stack, and with <dest> gone nothing could attribute those resources to a
# worktree again — an orphaned network survived that way for two days while
# untagged 3GB build layers piled up behind it.
#
# Docker is stubbed via PATH; the stub reports the worktree's stack as present
# until the recorded teardown runs and drops the marker file.
# =====================================================================

mkdir -p "$TMP/bin" "$WS/_scripts" "$WS/.context/worktrees"
cat > "$TMP/bin/docker" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "info") exit 0 ;;
  *"ps -a"*) [[ -e "$TMP/torn" ]] || echo ws-wt-feat-t ;;
  *"network inspect"*) echo 0 ;;
  *) : ;;
esac
FAKE
chmod +x "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH"

cat > "$WS/_scripts/down.sh" <<DOWN
#!/usr/bin/env bash
echo "torn:\$1" >> "$TMP/teardown.log"
touch "$TMP/torn"
DOWN
chmod +x "$WS/_scripts/down.sh"

mk_doc() {  # mk_doc <worktree_down-value>
  cat > "$WS/.context/worktrees/00-index.md" <<DOC
---
title: "t"
worktree_up: ""
worktree_down: "$1"
---
## Procedure
## Usage log
DOC
}

DEST_T="$TMP/ws-wt-feat-t"

# --- refuses when resources exist but no teardown is recorded ---
mk_doc ""
bash "$SCRIPT" create --slug feat-t --branch feat/t --repo backend --dest "$DEST_T" >/dev/null 2>&1
if refusal="$(bash "$SCRIPT" remove --slug feat-t --dest "$DEST_T" 2>&1)"; then
  fail "remove: must refuse when Docker resources exist and no worktree_down is recorded"
fi
# The sweep also exits 1 on an image it could not judge (BL-774); the refusal must
# not send that case to --skip-teardown, which would strand the unjudged image.
grep -q "could not be judged" <<<"$refusal" \
  || fail "remove: the refusal does not cover a sweep that could not judge a resource: $refusal"
[[ -d "$DEST_T" ]] || fail "remove: a refused teardown must NOT have removed the directory"

# --- runs the recorded teardown, substituting <slug>, before removing ---
mk_doc "_scripts/down.sh <slug>"
bash "$SCRIPT" remove --slug feat-t --dest "$DEST_T" >/dev/null 2>&1 || fail "remove: exited non-zero with a valid teardown"
[[ -f "$TMP/teardown.log" ]] || fail "remove: recorded teardown was never executed"
grep -q '^torn:feat-t$' "$TMP/teardown.log" 2>/dev/null || fail "remove: teardown ran without the <slug> substituted (got: $(cat "$TMP/teardown.log" 2>/dev/null))"
[[ ! -e "$DEST_T" ]] || fail "remove: dest still exists after a successful teardown"

# --- --skip-teardown removes the dir without touching Docker ---
rm -f "$TMP/torn" "$TMP/teardown.log"
DEST_S="$TMP/ws-wt-feat-s"
bash "$SCRIPT" create --slug feat-s --branch feat/s --repo backend --dest "$DEST_S" >/dev/null 2>&1
bash "$SCRIPT" remove --slug feat-s --dest "$DEST_S" --skip-teardown >/dev/null 2>&1 || fail "remove --skip-teardown: exited non-zero"
[[ ! -e "$DEST_S" ]] || fail "remove --skip-teardown: dest still exists"
[[ ! -f "$TMP/teardown.log" ]] || fail "remove --skip-teardown: must not run the teardown"

# --- a dirty participant refuses the WHOLE removal, before any worktree goes ---
# git refuses one dirty worktree at a time, so a dirty frontend used to leave backend
# already removed: a half worktree that `up` never rebuilds.
DEST_D="$TMP/ws-wt-feat-d"
bash "$SCRIPT" create --slug feat-d --branch feat/d --repo backend --repo frontend --dest "$DEST_D" >/dev/null 2>&1
echo wip > "$DEST_D/frontend/wip.txt"
bash "$SCRIPT" remove --slug feat-d --dest "$DEST_D" --skip-teardown >/dev/null 2>&1 \
  && fail "remove: must refuse while a participant holds uncommitted work"
[[ -f "$DEST_D/backend/.git" ]] || fail "remove: a dirty frontend must leave backend in place, not half-remove the worktree"
rm -f "$DEST_D/frontend/wip.txt"
bash "$SCRIPT" remove --slug feat-d --dest "$DEST_D" --skip-teardown >/dev/null 2>&1 || fail "remove: clean after the refusal, it must succeed"

# --- a DIRECTORY --copy entry is removed too ---
# `create` copies with cp -R, but remove ran `rm -f`, which fails on a directory and
# aborted the removal under set -e after the participants were already gone.
mkdir -p "$WS/vendor"; echo v > "$WS/vendor/lib.txt"
DEST_V="$TMP/ws-wt-feat-v"
bash "$SCRIPT" create --slug feat-v --branch feat/v --repo backend --copy vendor --dest "$DEST_V" >/dev/null 2>&1
[[ -f "$DEST_V/vendor/lib.txt" ]] || fail "copy dir: create did not copy vendor/"
bash "$SCRIPT" remove --slug feat-v --dest "$DEST_V" --skip-teardown --copy vendor >/dev/null 2>&1 \
  || fail "copy dir: remove must complete with a directory --copy entry"
[[ ! -e "$DEST_V" ]] || fail "copy dir: dest still exists after remove"

# =====================================================================
# BL-634: the base is stated, never the ambient checkout. A root checkout sitting
# on feat/x (1 commit over main) used to weld every new branch to feat/x.
# Layer: shell integration, because the decision lives in git arguments.
# =====================================================================
WT_SH="$(dirname "$SCRIPT")/worktree.sh"
PR="$TMP/bproj"
mkdir -p "$PR/.context/worktrees"
git -C "$PR" init -q -b main
git -C "$PR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
git -C "$PR" checkout -q -b feat/x
git -C "$PR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat work"
echo 'WT_PARTICIPANTS="."' > "$PR/.context/worktrees/config.env"
main_tip="$(git -C "$PR" rev-parse main)"; feat_tip="$(git -C "$PR" rev-parse feat/x)"

( cd "$PR" && bash "$WT_SH" new s1 --branch b1 --no-infra >/dev/null 2>&1 ) || fail "base: default new failed"
[[ "$(git -C "$PR" rev-parse b1 2>/dev/null)" == "$main_tip" ]] \
  || fail "base: without --base the branch must fork from main's tip, not the checked-out feat/x"
( cd "$PR" && bash "$WT_SH" down s1 --delete-branch >/dev/null 2>&1 )

out="$( cd "$PR" && bash "$WT_SH" new s2 --branch b2 --base feat/x --no-infra 2>&1 )" || fail "base: --base new failed -- $out"
[[ "$(git -C "$PR" rev-parse b2 2>/dev/null)" == "$feat_tip" ]] || fail "base: --base feat/x must fork from feat/x"
grep -q 'base feat/x (+1 over main)' <<<"$out" || fail "base: report must say 'base feat/x (+1 over main)' -- $out"
( cd "$PR" && bash "$WT_SH" down s2 --delete-branch >/dev/null 2>&1 )

out="$( cd "$PR" && bash "$WT_SH" new --help 2>&1 )"; rc=$?
[[ "$rc" == 0 ]] || fail "help: 'new --help' must exit 0, got $rc"
grep -q 'worktree.sh new' <<<"$out" || fail "help: usage text missing -- $out"

# worktree-multi.sh honours --base too (the layer that runs `worktree add`).
( cd "$PR" && bash "$SCRIPT" create --slug m1 --branch bm1 --base HEAD~1 --repo . --dest "$TMP/bproj-wt-m1" >/dev/null 2>&1 ) \
  || fail "base: multi create --base failed"
[[ "$(git -C "$PR" rev-parse bm1 2>/dev/null)" == "$main_tip" ]] || fail "base: multi --base HEAD~1 must fork from main"

# --- BL-634 round 2 ---
# F1: with a remote, the default base is LOCAL main (owner repos run ahead of origin)
# and no upstream tracking is set.
git clone -q --bare "$PR" "$TMP/borigin.git"
git -C "$PR" remote add origin "$TMP/borigin.git"
git -C "$PR" fetch -q origin
git -C "$PR" remote set-head origin main >/dev/null
git -C "$PR" checkout -q main
git -C "$PR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local ahead of origin"
git -C "$PR" checkout -q feat/x
local_main="$(git -C "$PR" rev-parse main)"
( cd "$PR" && bash "$WT_SH" new s4 --branch b4 --no-infra >/dev/null 2>&1 ) || fail "origin: default new failed"
[[ "$(git -C "$PR" rev-parse b4 2>/dev/null)" == "$local_main" ]] || fail "origin: default base must be LOCAL main, not origin/main"
git -C "$PR" rev-parse --verify --quiet 'b4@{upstream}' >/dev/null 2>&1 && fail "origin: the new branch must not track origin/main"
( cd "$PR" && bash "$WT_SH" down s4 --delete-branch >/dev/null 2>&1 )

# F2: --base with an already existing branch is refused, nothing is created.
git -C "$PR" branch b3 main
( cd "$PR" && bash "$WT_SH" new s3 --branch b3 --base feat/x --no-infra >/dev/null 2>&1 ) && fail "base: --base with an existing branch must be refused"
[[ "$(git -C "$PR" rev-parse b3)" == "$local_main" ]] || fail "base: refused --base must leave b3 unchanged"
[[ ! -e "$TMP/bproj-wt-s3" ]] || fail "base: refused --base must create nothing"

# A root checkout's bookkeeping excludes land in the MAIN repo's shared info/exclude
# (info/ is a common-dir path), and every create appended them again: after two
# root-participant creates, each line must appear once.
PX="$TMP/xproj"
mkdir -p "$PX" && git -C "$PX" init -q -b main
git -C "$PX" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
for s in x1 x2; do
  ( cd "$PX" && AIDEX_WT_INTERNAL=1 bash "$SCRIPT" create --slug "$s" --branch "b$s" --repo . --dest "$TMP/xproj-wt-$s" >/dev/null 2>&1 ) \
    || fail "exclude: root create $s failed"
done
n_ex="$(grep -cx '\.wt-slot' "$PX/.git/info/exclude" 2>/dev/null)"
[[ "$n_ex" == 1 ]] || fail "exclude: .wt-slot appears $n_ex times in the shared info/exclude, want 1"

# Old runs left a bare `.env` and one bookkeeping block per create in the shared
# info/exclude (dashboard_template_ws has 13). The next create migrates them, but ONLY
# inside those blocks (BL-770). Golden file, written by hand: block 1 absorbs the other
# blocks (`/sub/` from block 2), every user line stays in place and in order (a `.env`
# that is the SECOND in its block, `!keep.log` before `*.log`), a user section with no
# blank line before the next block is not swallowed, and the block ends with a blank.
PM="$TMP/mproj"
mkdir -p "$PM" && git -C "$PM" init -q -b main
git -C "$PM" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
H='# aidex worktree bookkeeping (worktree.sh)'
EXM="$PM/.git/info/exclude"
cat > "$EXM" <<EOT
# user rules
.env
*.log

$H
.wt-slot
.wt-branch
.env

$H
.wt-slot
.wt-branch
.env
/sub/
# my own
keep-me
$H
.wt-slot
.wt-branch
.env

# case A
*.o
$H
.wt-slot
.wt-branch
/.env
.env
secrets.txt

$H
.wt-slot
.wt-branch
.env
!keep.log
*.log
EOT
cat > "$TMP/mproj.golden" <<EOT
# user rules
.env
*.log

$H
.wt-slot
.wt-branch
/.env
/sub/

# my own
keep-me
# case A
*.o
.env
secrets.txt
!keep.log
*.log
EOT
( cd "$PM" && AIDEX_WT_INTERNAL=1 bash "$SCRIPT" create --slug m1 --branch bm1 --repo . --dest "$TMP/mproj-wt-m1" >/dev/null 2>&1 ) \
  || fail "migrate: root create m1 failed"
diff -u "$TMP/mproj.golden" "$EXM" >"$TMP/mproj.diff" 2>&1 \
  || fail "migrate: exclude differs from the golden file: $(tr '\n' '|' < "$TMP/mproj.diff")"
sum1="$(cksum < "$EXM")"
( cd "$PM" && AIDEX_WT_INTERNAL=1 bash "$SCRIPT" create --slug m2 --branch bm2 --repo . --dest "$TMP/mproj-wt-m2" >/dev/null 2>&1 ) \
  || fail "migrate: root create m2 failed"
[[ "$(cksum < "$EXM")" == "$sum1" ]] || fail "migrate: a second create must leave the exclude file byte-identical"
[[ -z "$(ls "$PM/.git/info" | grep -v '^exclude$')" ]] || fail "migrate: a temp file was left in info/"

# A block that lacks a wanted line gets it INSIDE the block, not appended after the
# user's rules that follow it (BL-770): `.wt-branch` must land before the blank line.
PN="$TMP/wproj"
mkdir -p "$PN" && git -C "$PN" init -q -b main
git -C "$PN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
cat > "$PN/.git/info/exclude" <<EOT
$H
.wt-slot
/.env
*.log
EOT
cat > "$TMP/wproj.golden" <<EOT
$H
.wt-slot
/.env
.wt-branch

*.log
EOT
( cd "$PN" && AIDEX_WT_INTERNAL=1 bash "$SCRIPT" create --slug w1 --branch bw1 --repo . --dest "$TMP/wproj-wt-w1" >/dev/null 2>&1 ) \
  || fail "migrate-missing: root create w1 failed"
diff -u "$TMP/wproj.golden" "$PN/.git/info/exclude" >"$TMP/wproj.diff" 2>&1 \
  || fail "migrate-missing: exclude differs from the golden file: $(tr '\n' '|' < "$TMP/wproj.diff")"

# With no --base, no origin/HEAD and no main/master, create forked from the
# ambient checkout (feature-x), first silently, then with a warning. A wrong base
# is expensive to undo, so it refuses and asks for --base (owner, 2026-10-12 Q4),
# before anything exists: `backend` comes first and has a main, `pd` has none.
mkdir -p "$WS/pd"
git -C "$WS/pd" init -q -b develop
git -C "$WS/pd" -c user.email=t@t -c user.name=t commit -q --allow-empty -m d0
git -C "$WS/pd" checkout -q -b feature-x
git -C "$WS/pd" -c user.email=t@t -c user.name=t commit -q --allow-empty -m fx1
err="$( cd "$WS" && AIDEX_WT_INTERNAL=1 bash "$SCRIPT" create --slug d1 --branch bd1 --repo backend --repo pd --dest "$TMP/ws-wt-d1" 2>&1 >/dev/null )"; rc=$?
[[ "$rc" -eq 2 ]] || fail "base: create with no --base and no default branch must exit 2, got $rc -- $err"
grep -q 'pd: no default branch.*pass --base' <<<"$err" || fail "base: the refusal must name the repo and ask for --base -- $err"
grep -q 'or create bd1 in pd first (git -C pd branch bd1 <commit>)' <<<"$err" \
  || fail "base: the refusal must also offer creating the branch in pd -- $err"
[[ ! -e "$TMP/ws-wt-d1" ]] || fail "base: a refused create left $TMP/ws-wt-d1"
git -C "$WS/backend" show-ref --verify --quiet refs/heads/bd1 && fail "base: a refused create made branch bd1 in backend"
git -C "$WS/pd" show-ref --verify --quiet refs/heads/bd1 && fail "base: a refused create made branch bd1 in pd"
# An existing branch needs no base: it is used at its own tip.
git -C "$WS/pd" branch -q bd2 feature-x
( cd "$WS" && AIDEX_WT_INTERNAL=1 bash "$SCRIPT" create --slug d2 --branch bd2 --repo pd --dest "$TMP/ws-wt-d2" >/dev/null 2>&1 ) \
  || fail "base: an existing branch with no default branch must still be created"

# worktree-c22: worktree.sh's own `base ...` line must name what multi forks from.
# (a) No origin/HEAD and no local main, only origin/main: multi forks from
#     origin/main, but worktree.sh fell back to the ambient branch and reported
#     "base feature-y" -- a wrong base, stated as fact.
# (b) Nothing names a default: the report must say the base is the current
#     checkout, not present the ambient branch as a chosen base.
PO="$TMP/oproj"
git init -q -b main "$TMP/oup"
git -C "$TMP/oup" -c user.email=t@t -c user.name=t commit -q --allow-empty -m o0
git clone -q "$TMP/oup" "$PO"
mkdir -p "$PO/.context/worktrees"; echo 'WT_PARTICIPANTS="."' > "$PO/.context/worktrees/config.env"
git -C "$PO" checkout -q -b feature-y
git -C "$PO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m fy1
git -C "$PO" branch -q -D main; git -C "$PO" remote set-head origin -d
out="$( cd "$PO" && bash "$WT_SH" new c22a --branch bc22a --no-infra 2>&1 )" || fail "c22: origin-only new failed -- $out"
[[ "$(git -C "$PO" rev-parse bc22a 2>/dev/null)" == "$(git -C "$PO" rev-parse origin/main)" ]] \
  || fail "c22 fixture: multi must fork bc22a from origin/main"
grep -q '^base origin/main ' <<<"$out" || fail "c22: report must name the base actually used, origin/main -- $out"

PN="$TMP/nproj"
git init -q -b develop "$PN"
git -C "$PN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m n0
git -C "$PN" checkout -q -b feature-z
mkdir -p "$PN/.context/worktrees"; echo 'WT_PARTICIPANTS="."' > "$PN/.context/worktrees/config.env"
# Q4: nothing names a default and no --base: `new` refuses before anything exists.
out="$( cd "$PN" && bash "$WT_SH" new c22b --branch bc22b --no-infra 2>&1 )"; rc=$?
[[ "$rc" -eq 2 ]] || fail "Q4: new with no --base and no default branch must exit 2, got $rc -- $out"
grep -q 'no default branch.*pass --base' <<<"$out" || fail "Q4: the refusal must ask for --base -- $out"
grep -q 'or create bc22b in \. first (git -C \. branch bc22b <commit>)' <<<"$out" \
  || fail "Q4: the refusal must also offer creating the branch -- $out"
[[ ! -e "$TMP/nproj-wt-c22b" ]] || fail "Q4: a refused new left $TMP/nproj-wt-c22b"
git -C "$PN" show-ref --verify --quiet refs/heads/bc22b && fail "Q4: a refused new made branch bc22b"
# Q4 (r2 F2): every participant, not only the first. `a` has main, `b` only
# develop: `new` reserved a slot, multi refused on b, and the rollback exited 1.
# Refused up front instead, naming b, with no slot claim, no dir, no branch in a.
PQ="$TMP/q4proj"
mkdir -p "$PQ/.context/worktrees"
printf 'WT_PARTICIPANTS="a b"\nWT_PORT_VARS="DB_PORT=6700"\n' > "$PQ/.context/worktrees/config.env"
git init -q -b main "$PQ/a"; git -C "$PQ/a" -c user.email=t@t -c user.name=t commit -q --allow-empty -m a0
git init -q -b develop "$PQ/b"; git -C "$PQ/b" -c user.email=t@t -c user.name=t commit -q --allow-empty -m b0
QBIN="$TMP/q4bin"; mkdir -p "$QBIN" "$TMP/q4slots"; printf '#!/bin/sh\nexit 0\n' > "$QBIN/docker"; chmod +x "$QBIN/docker"
out="$( cd "$PQ" && TMPDIR="$TMP/q4slots" PATH="$QBIN:$PATH" bash "$WT_SH" new q4m --branch feat/q4m 2>&1 )"; rc=$?
[[ "$rc" -eq 2 ]] || fail "Q4 multi: new must refuse a second participant with no default branch, exit 2, got $rc -- $out"
grep -q 'b: no default branch.*pass --base' <<<"$out" || fail "Q4 multi: the refusal must name b and ask for --base -- $out"
grep -q 'or create feat/q4m in b first (git -C b branch feat/q4m <commit>)' <<<"$out" \
  || fail "Q4 multi: the refusal must also offer creating the branch in b -- $out"
[[ -z "$(ls "$TMP/q4slots/aidex-wt-slots-q4proj" 2>/dev/null | grep '^slot-')" ]] || fail "Q4 multi: a slot was reserved before the refusal"
[[ ! -e "$TMP/q4proj-wt-q4m" ]] || fail "Q4 multi: a refused new left $TMP/q4proj-wt-q4m"
git -C "$PQ/a" show-ref --verify --quiet refs/heads/feat/q4m && fail "Q4 multi: a refused new made feat/q4m in a"

# F3: --base is validated in EVERY participant before anything is created.
for r in pa pb; do
  mkdir -p "$WS/$r"
  git -C "$WS/$r" init -q 2>/dev/null
  git -C "$WS/$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i2
done
git -C "$WS/pa" tag t1
err="$( cd "$WS" && bash "$SCRIPT" create --slug v1 --branch bv --base t1 --repo pa --repo pb --dest "$TMP/ws-wt-v1" 2>&1 >/dev/null )" \
  && fail "base: a base missing in one participant must be refused"
grep -q 'base not found in pb' <<<"$err" || fail "base: expected 'base not found in pb' -- $err"
[[ ! -e "$TMP/ws-wt-v1" ]] || fail "base: failed validation must not create the destination"

# A root checkout's TRACKED symlink is the repo's, not a wrapper link: `down` deleted it
# with the wrapper sweep, so the root checkout was dirty and its removal refused
# (aidex_ws, 2026-10-03: .claude/skills/skill-trigger-eval).
PS="$TMP/sproj"
mkdir -p "$PS/.context/worktrees" "$PS/.claude/skills"
git -C "$PS" init -q -b main
ln -s /nonexistent/target "$PS/.claude/skills/ext-skill"
echo 'WT_PARTICIPANTS="."' > "$PS/.context/worktrees/config.env"
git -C "$PS" add -A
git -C "$PS" -c user.email=t@t -c user.name=t commit -q -m init
( cd "$PS" && bash "$WT_SH" new l1 --branch bl1 --no-infra >/dev/null 2>&1 ) || fail "tracked link: new failed"
out="$( cd "$PS" && bash "$WT_SH" down l1 --delete-branch 2>&1 )" \
  || fail "tracked link: down must remove a root checkout that tracks a symlink -- $out"
[[ ! -e "$TMP/sproj-wt-l1" ]] || fail "tracked link: the root checkout must be gone"
# The slot env file is recognised by its line-1 marker at two sites in worktree-multi.sh:
# the dirty precheck (swept) and the sweep that deletes it. A root checkout whose
# /.env is NOT excluded shows `?? .env`, so both are reached: the generated file is
# removed with the worktree, a project's own .env still blocks it.
# The generator's own line 1, so rewording the writer alone turns this red.
. "$(dirname "$SCRIPT")/wt-env-marker.sh"
PM="$TMP/mkproj"
mkdir -p "$PM/.context/worktrees"
git -C "$PM" init -q -b main
echo 'WT_PARTICIPANTS="."' > "$PM/.context/worktrees/config.env"
git -C "$PM" add -A
git -C "$PM" -c user.email=t@t -c user.name=t commit -q -m init
for m in k1 k2; do
  out="$( cd "$PM" && bash "$WT_SH" new $m --branch b$m --no-infra 2>&1 )" || fail "marker: new $m failed -- $out"
done
_ex="$(git -C "$TMP/mkproj-wt-k1" rev-parse --git-path info/exclude)"
grep -vxF '/.env' "$_ex" > "$TMP/mex" || true; cat "$TMP/mex" > "$_ex"
printf '%s\nK=1\n' "$WT_ENV_MARKER" > "$TMP/mkproj-wt-k1/.env"
printf 'K=2\n' > "$TMP/mkproj-wt-k2/.env"
out="$( cd "$PM" && bash "$WT_SH" down k1 2>&1 )" \
  || fail "marker: a generated slot .env must not block or survive down -- $out"
[[ ! -e "$TMP/mkproj-wt-k1" ]] || fail "marker: the root checkout holding a generated .env must be gone"
out="$( cd "$PM" && bash "$WT_SH" down k2 2>&1 )" \
  && fail "marker: a project's own .env must still block down -- $out"
[[ -e "$TMP/mkproj-wt-k2/.env" ]] || fail "marker: a project's own .env must be left in place"
( cd "$PM" && bash "$WT_SH" down k2 --force >/dev/null 2>&1 )

if [[ "$failures" -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "OK — multi-repo worktree create/refuse/validate/remove lifecycle + teardown coupling"
