#!/usr/bin/env bash
# test-orphan-sweep-all.sh — `orphan-sweep.sh --all`, the machine-wide report-only
# listing (BL-810, BL-811). Layer: script-level with a PATH docker shim that answers
# from fixture text and logs every argv; no daemon is ever contacted.
#
# Protects: a compose project is a candidate orphan only when every one of its
# containers carries a working_dir label and none of those directories exists; nothing
# else is mentioned; the listing never prints a removal command; every docker call is a
# read; the summary the session-start hook reads.
#
# Run with: bash skills/worktree/tests/test-orphan-sweep-all.sh

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT="$HERE/../scripts/orphan-sweep.sh"

PASS=0; FAIL=0
pass() { echo "  PASS  $*"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $*"; FAIL=$((FAIL + 1)); }
has()  { if grep -Fq -- "$2" <<< "$out"; then pass "$1"; else fail "$1: missing '$2' in: $out"; fi; }
hasnt(){ if grep -Fq -- "$2" <<< "$out"; then fail "$1: unexpected '$2' in: $out"; else pass "$1"; fi; }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
H="$TMP/home"; P="$H/p"
mkdir -p "$P/shop_ws" "$P/lab" "$H/elsewhere" "$H/moved" "$H/.claude"
# shop_ws is the live main checkout. Its worktrees, made the way worktree.sh makes them:
#   feat  live at a custom location, on a branch that is not its slug;
#   plain live, moved with a plain `mv` (its containers keep the old working_dir);
#   gone  deleted with `rm -rf`.
git -C "$P/shop_ws" init -q && git -C "$P/shop_ws" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init \
  && git -C "$P/shop_ws" worktree add -q -b fix/other-name "$H/elsewhere/shop_ws-wt-feat" \
  && git -C "$P/shop_ws" worktree add -q -b plain "$P/shop_ws-wt-plain" \
  && printf 'COMPOSE_PROJECT_NAME=shop_ws-wt-plain\n' > "$P/shop_ws-wt-plain/.env" \
  && mv "$P/shop_ws-wt-plain" "$H/moved/shop_ws-wt-plain" \
  && git -C "$P/shop_ws" worktree add -q -b gone "$P/shop_ws-wt-gone" \
  && rm -rf "$P/shop_ws-wt-gone"
[[ -d "$H/elsewhere/shop_ws-wt-feat" && -f "$H/moved/shop_ws-wt-plain/.env" && ! -e "$P/shop_ws-wt-plain" && ! -e "$P/shop_ws-wt-gone" ]] \
  || { echo "fixture setup failed"; exit 1; }

T=$'\t'
# ps -a: project, working_dir, state.
cat > "$TMP/ps" <<EOF
shop_ws${T}$P/shop_ws${T}running
shop_ws${T}$P/shop_ws${T}exited
shop_ws-wt-feat${T}$H/elsewhere/shop_ws-wt-feat${T}exited
shop_ws-wt-plain${T}$P/shop_ws-wt-plain${T}exited
shop_ws-wt-gone${T}$P/shop_ws-wt-gone${T}exited
shop_ws-wt-gone${T}$P/shop_ws-wt-gone${T}created
labsync-check${T}$P/lab${T}exited
bpsync-check${T}$P/bpsync${T}exited
halflabel${T}$P/halfgone${T}exited
halflabel${T}${T}exited
splitdir${T}$P/splitgone${T}exited
splitdir${T}$P/lab${T}exited
ci${T}/workspace${T}exited
${T}${T}running
EOF
# volume ls: name, project.
cat > "$TMP/volumes" <<EOF
shop_ws_pgdata${T}shop_ws
shop_ws-wt-feat_pgdata${T}shop_ws-wt-feat
shop_ws-wt-plain_pgdata${T}shop_ws-wt-plain
shop_ws-wt-gone_pgdata${T}shop_ws-wt-gone
media_cache${T}shop_ws-wt-gone
bpsync-check_pgdata${T}bpsync-check
halflabel_pg${T}halflabel
postgres_bo_data${T}af_backoffice
abc123hash${T}
EOF

mkdir -p "$TMP/bin"
cat > "$TMP/bin/docker" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DLOG"
case "$1 ${2:-}" in
  "info "*) exit "${INFO_RC:-0}" ;;
  "ps -a") cat "$FIX/ps" ;;
  "volume ls") cat "$FIX/volumes" ;;
  *) exit 0 ;;
esac
SHIM
chmod +x "$TMP/bin/docker"
DLOG="$TMP/dlog"

run() { ( cd "$TMP" && HOME="$H" FIX="$TMP" DLOG="$DLOG" PATH="$TMP/bin:$PATH" bash "$SCRIPT" --all "$@" 2>&1 ); }

echo "== candidates: every container labelled, no working_dir exists =="
: > "$DLOG"
out="$(run --write-summary)"; code=$?
[[ $code -eq 0 ]] && pass "--all exits 0" || fail "--all exit $code"
hasnt "live main checkout not mentioned" "shop_ws "
hasnt "live main checkout's volume not mentioned" "shop_ws_pgdata"
hasnt "live worktree at a custom location (branch != slug) not mentioned" "shop_ws-wt-feat"
has   "deleted worktree is a candidate" "CANDIDATE ORPHAN shop_ws-wt-gone"
has   "candidate: its working_dir is printed" "$P/shop_ws-wt-gone"
has   "candidate: its container count is printed" "2 container(s)"
has   "candidate: its volumes are attached, not removable" "volume shop_ws-wt-gone_pgdata attached to shop_ws-wt-gone"
has   "candidate: a fixed-name volume is attached too" "volume media_cache attached to shop_ws-wt-gone"
has   "worktree moved with a plain mv is a candidate (the documented limit)" "CANDIDATE ORPHAN shop_ws-wt-plain"
hasnt "non -wt- project whose dir exists not mentioned" "labsync-check"
has   "non -wt- project whose dir is gone is a candidate" "CANDIDATE ORPHAN bpsync-check"
hasnt "a container without the working_dir label: project not judged, not mentioned" "halflabel"
hasnt "one working_dir still present: project not mentioned" "splitdir"
hasnt "working_dir outside \$HOME (devcontainer, unmounted disk) not mentioned" "CANDIDATE ORPHAN ci"
hasnt "volume-only project (no container) not mentioned" "af_backoffice"
hasnt "unlabelled volume not mentioned" "abc123hash"
n="$(grep -c '^  verify by hand before removing anything$' <<< "$out")"
[[ "$n" -eq 3 ]] && pass "one verify line per candidate" || fail "verify lines: $n, expected 3"

echo "== the listing never prints a removal command =="
for verb in "docker rm" "rmi" "volume rm" "network rm" "compose -p" "down" "prune" "rm -"; do
  hasnt "no '$verb' in the listing" "$verb"
done

echo "== report-only: every docker call is a read =="
bad="$(grep -vE '^(info|ps -a|volume ls)( |$)' "$DLOG")"
[[ -z "$bad" ]] && pass "no other verb reached docker ($(wc -l < "$DLOG" | tr -d ' ') calls)" || fail "unexpected docker call(s): $bad"

echo "== summary for the session-start hook =="
S="$H/.claude/tmp/docker-orphans/summary"
out="$(cat "$S" 2>&1)"
has   "status ok" "status=ok"
has   "three candidates" "candidates=3"
has   "candidate names" "candidate_projects=bpsync-check shop_ws-wt-gone shop_ws-wt-plain"
hasnt "the summary carries no command" "docker "

echo "== docker not running =="
: > "$DLOG"
out="$( ( cd "$TMP" && HOME="$H" FIX="$TMP" DLOG="$DLOG" INFO_RC=1 PATH="$TMP/bin:$PATH" bash "$SCRIPT" --all --write-summary 2>&1 ) )"; code=$?
[[ $code -eq 0 ]] && pass "daemon down: exit 0" || fail "daemon down: exit $code"
has   "daemon down: degraded note" "docker daemon unreachable"
hasnt "daemon down: no candidate" "CANDIDATE"
[[ "$(cat "$DLOG")" == info ]] && pass "daemon down: no call after info" || fail "daemon down: calls after info: $(cat "$DLOG")"
grep -q '^candidates=3$' "$S" && pass "daemon down: the last good summary is kept" || fail "daemon down: summary: $(cat "$S")"

echo "== an incomplete inventory judges nothing =="
cat > "$TMP/bin/docker" <<'SHIM'
#!/usr/bin/env bash
case "$1 ${2:-}" in "info "*) exit 0 ;; "ps -a") exit 1 ;; *) exit 0 ;; esac
SHIM
out="$(run --write-summary)"
hasnt "ps failure: no candidate" "CANDIDATE"
grep -q '^candidates=3$' "$S" && pass "ps failure: the last good summary is kept" || fail "ps failure: summary: $(cat "$S")"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
