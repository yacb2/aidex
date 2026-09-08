#!/usr/bin/env bash
# test-git-file-worktree-sites.sh — a linked worktree's .git is a FILE, and the three
# scripts that tested it with isdir() went silently half-blind there.
#
# BL-344 fixed the same predicate in memory-sweep.py (a325986). BL-351 is the census:
# detect-resolved.py:95 and archive-sweep.py:218 set repo=None, disabling commit
# verification and status-drift detection with no message; root-litter-sweep.py:110
# `continue`d, so a stray repo sited in a worktree was never reported. All three
# degraded silently, which is what hid it.
#
# Fixture: a REAL linked worktree (`git worktree add`), so the .git file is the one git
# actually writes, not a hand-made lookalike.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
S="$HERE/../skills"
FAILURES=0
fail() { printf 'FAIL: %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'ok: %s\n' "$*"; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

MAIN="$TMP/main"
mkdir -p "$MAIN"
git -C "$MAIN" init -q -b main
git -C "$MAIN" config user.email t@t; git -C "$MAIN" config user.name t
echo one > "$MAIN/f.txt"; git -C "$MAIN" add -A; git -C "$MAIN" commit -qm "first"
SHA="$(git -C "$MAIN" rev-parse HEAD)"
WT="$TMP/wt"
git -C "$MAIN" worktree add -q -b side "$WT"
[[ -f "$WT/.git" ]] || { echo "FIXTURE BROKEN: $WT/.git is not a file"; exit 1; }

mk_item() {  # mk_item <dir> <name> <status> <body>
  mkdir -p "$1"
  cat > "$1/$2" <<ITEM
---
title: "an item"
id: BL-001
status: $3
created: 2026-01-01
updated: 2026-01-01
priority: P2
type: task
estimate: XS
commits: "$SHA"
---

# an item

$4
ITEM
}

# --- detect-resolved.py: cited commits must be VERIFIED inside a worktree -----------
CTX="$WT/.context"
mk_item "$CTX/backlog" "2026-01-01-bl-001-a.md" open "Fixed in $SHA — see f.txt"
out="$(python3 "$S/aidex-backlog/scripts/detect-resolved.py" "$CTX" 2>&1)"; rc=$?
# The run must SUCCEED first. On this test's first draft the flag was `--context`, which
# detect-resolved does not take: argparse exited 2, the usage text contained no note, and
# the "no note" branch below read as a PASS. A green assertion over a run that never
# happened is the one failure this whole item is about.
[[ $rc -eq 0 ]] || fail "detect-resolved did not run at all (exit $rc): $out"
case "$out" in
  *"no git repo above .context/"*)
    fail "detect-resolved silently dropped commit verification in a worktree: $out" ;;
  *) pass "detect-resolved verifies cited commits when .git is a file" ;;
esac

# --- archive-sweep.py: status drift needs git, and git is there ---------------------
J="$TMP/as.json"
python3 "$S/aidex-conventions/scripts/archive-sweep.py" "$CTX" --json "$J" >/dev/null 2>&1
drift=0
if [[ -s "$J" ]]; then
  drift="$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["status_drift"]))' "$J")"
else
  fail "archive-sweep wrote no json at all — the run did not happen"
fi
if [[ "$drift" -gt 0 ]]; then
  pass "archive-sweep detects status drift when .git is a file ($drift row)"
else
  fail "archive-sweep found no status drift in a worktree — its git half was disabled"
fi

# --- root-litter-sweep.py: a stray repo sited in a worktree is still a repo ---------
ROOT="$TMP/projects"; mkdir -p "$ROOT"
git -C "$MAIN" worktree add -q -b stray "$ROOT/stray-clone"
out="$(python3 "$S/aidex/scripts/root-litter-sweep.py" --root "$ROOT" 2>&1)"
case "$out" in
  *stray-clone*) pass "root-litter-sweep reports a stray repo whose .git is a file" ;;
  *) fail "root-litter-sweep skipped a worktree-sited stray repo entirely: $out" ;;
esac

# The gate must have seen a real worktree, not an empty run.
git -C "$MAIN" worktree list | grep -qc . || fail "no worktree was created"

if [[ $FAILURES -gt 0 ]]; then printf '\n%d check(s) failed\n' "$FAILURES"; exit 1; fi
printf '\nOK — .git-as-a-file: detect-resolved, archive-sweep and root-litter-sweep all keep their git half in a linked worktree\n'
