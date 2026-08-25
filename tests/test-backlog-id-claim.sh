#!/usr/bin/env bash
# A backlog id must be CLAIMED, not merely read — two sessions cannot mint the same one.
#
# The bug (BL-235, reported 2026-08-25): `next_backlog_id()` was a read-max-then-add-one
# with no mutual exclusion — no flock, no lockfile, no atomic claim of any kind. The scan
# and the eventual file write are separated by the whole body of the run, so two sessions
# in the same `.context/` both see max=N and both mint N+1. `report_duplicate_ids()` exists
# but runs at `--reindex` and only WARNS: the collision was detected after both files
# existed, never prevented, which is exactly what the user observed.
#
# The fix is claim-by-create: minting takes an ID-KEYED marker under `backlog/_claims/`
# with `set -o noclobber` before the run body starts, and the marker counts toward the max.
# It must be id-keyed, not filename-keyed — two sessions registering different titles
# produce different filenames, so a no-clobber on the entry file would let both through.
#
# What this test proves, and what it does not:
#   PROVES  — a claim is as good as a written entry for the purposes of minting; parallel
#             registrations in one `.context/` get distinct ids; a claim is RELEASED when
#             the entry lands, so ids stay contiguous; the escalate-to rollback does not
#             burn an id in the target repo; and the two pre-existing guards survive —
#             the 3-to-5 digit window and `report_duplicate_ids` as the backstop.
#   DOES NOT — fix or test collision mode (b), two INDEPENDENT worktrees each minting
#             from their own `.context/`. No lock can: at mint time the trees genuinely
#             share no state, and the collision only surfaces when the branches merge.
#             Nor does it cover ids minted BY HAND, which is the widest window of all.
#
# Run with: bash tests/test-backlog-id-claim.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/skills/aidex-backlog/scripts/register-item.sh"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

new_project() {  # $1 = name; echoes the backlog dir
  local b="$TMP/$1/.context/backlog"
  mkdir -p "$b"
  printf '%s' "$b"
}
ids_in() {  # every id: value under a backlog dir, sorted
  grep -h '^id:' "$1"/*.md 2>/dev/null | awk '{print $2}' | sort
}

# ---------- (1) a claim counts toward the max, exactly as a written entry does ----------
# The deterministic core of the race: with no mutual exclusion the second session sees
# only written files, so a claim in flight is invisible and it re-mints the same number.
B="$(new_project claimvisible)"
mkdir -p "$B/_claims"
: > "$B/_claims/BL-002"
( cd "$(dirname "$(dirname "$B")")" && bash "$SCRIPT" --origin manual --title "After a claim" \
    --no-index >/dev/null 2>&1 )
got="$(ids_in "$B" | tr '\n' ' ')"
if [[ "$got" != "BL-003 " ]]; then
  fail "(1) an id claimed but not yet written was re-minted: got [$got], expected [BL-003] — a claim in flight must count toward the max or the race is untouched"
fi

# ---------- (2) parallel registrations in one .context/ get distinct ids ----------
# `--no-index` on purpose: regen_index writes 00-index.md with a plain `>` redirect, so
# concurrent runs also race on the INDEX. That is a separate hazard and not BL-235's
# scope; including it here would make this cell test two races at once.
B="$(new_project parallel)"
P="$(dirname "$(dirname "$B")")"
for i in 1 2 3 4 5 6; do
  ( cd "$P" && bash "$SCRIPT" --origin manual --title "Parallel item $i" \
      --slug "parallel-item-$i" --no-index >/dev/null 2>&1 ) &
done
wait
n_files="$(find "$B" -maxdepth 1 -name '*.md' ! -name '00-index.md' | wc -l | tr -d ' ')"
n_ids="$(ids_in "$B" | sort -u | wc -l | tr -d ' ')"
if [[ "$n_files" != 6 ]]; then
  fail "(2) six parallel registrations wrote $n_files entries, not 6 — the fixture is wrong, not the claim"
elif [[ "$n_ids" != 6 ]]; then
  fail "(2) six parallel registrations produced $n_ids DISTINCT ids: $(ids_in "$B" | tr '\n' ' ') — this is the collision the item reports"
fi

# ---------- (3) a claim is released, so ids stay contiguous ----------
# Claim-by-create must not leak: if the marker outlived the write, every registration
# would burn a number and the sequence would advance by two.
B="$(new_project contiguous)"
P="$(dirname "$(dirname "$B")")"
( cd "$P" && bash "$SCRIPT" --origin manual --title "First"  --no-index >/dev/null 2>&1 )
( cd "$P" && bash "$SCRIPT" --origin manual --title "Second" --no-index >/dev/null 2>&1 )
got="$(ids_in "$B" | tr '\n' ' ')"
if [[ "$got" != "BL-001 BL-002 " ]]; then
  fail "(3) two sequential registrations gave [$got], expected [BL-001 BL-002] — a claim that is never released burns an id per item"
fi
# The marker is KEPT on success — it is the ledger. (This assertion is the inverse of
# what it was when claims were released on success: once the sequence became repo-global,
# main's front-matter scan stopped being able to see items written on other branches, so
# the markers are the only shared record of which numbers are spent. Releasing them would
# hand the same number back out.) A claim is released only when NO entry was written —
# cell (4) covers that.
kept="$(find "$B/_claims" -name 'BL-*' 2>/dev/null | wc -l | tr -d ' ')"
[[ "$kept" == 2 ]] || fail "(3b) the ledger holds $kept marker(s) after two registrations, expected 2 — the markers are what a sibling worktree reads"

# ---------- (4) a failed --escalate-to must not burn an id in the TARGET repo ----------
# That path mints in two repos and already rolls the counterpart back on failure; a claim
# taken there has to be released the same way, or every failed handshake costs the other
# repo a number.
SRC="$(new_project esc-src)"; SRCP="$(dirname "$(dirname "$SRC")")"
TGT="$(new_project esc-tgt)"; TGTP="$(dirname "$(dirname "$TGT")")"
# --source-id names an item that does not exist, so the source side fails after the
# target counterpart has been written, and the script rolls the counterpart back.
( cd "$SRCP" && bash "$SCRIPT" --origin manual --title "Escalated" \
    --escalate-to "$TGTP" --source-id BL-999 >/dev/null 2>&1 )
( cd "$TGTP" && bash "$SCRIPT" --origin manual --title "Next target item" \
    --no-index >/dev/null 2>&1 )
got="$(ids_in "$TGT" | tr '\n' ' ')"
if [[ "$got" != "BL-001 " ]]; then
  fail "(4) after a rolled-back escalation the target repo minted [$got], expected [BL-001] — the rollback releases the counterpart file, so it must release its claim too"
fi

# ---------- (5) the 3-to-5 digit window still holds ----------
# A hand-authored date-shaped id (BL-20260610) once pushed the sequence into the millions.
# The claim path recomputes the max, so it has to keep skipping ids outside the window.
B="$(new_project digitwindow)"
P="$(dirname "$(dirname "$B")")"
cat > "$B/2026-01-01-legacy.md" <<'EOF'
---
title: "Legacy hand-authored id"
id: BL-20260610
status: open
created: 2026-01-01
updated: 2026-01-01
priority: P2
type: task
---

Body.
EOF
( cd "$P" && bash "$SCRIPT" --origin manual --title "After legacy" --no-index >/dev/null 2>&1 )
if ! ids_in "$B" | grep -qx "BL-001"; then
  fail "(5) a date-shaped legacy id inflated the sequence: got [$(ids_in "$B" | tr '\n' ' ')] — the 3-to-5 digit window must survive the claim rewrite"
fi

# ---------- (6) report_duplicate_ids survives as the backstop ----------
# The item asks for prevention AND detection, not prevention replacing detection: a
# duplicate that a human hand-authored is still not something the claim can prevent.
B="$(new_project backstop)"
P="$(dirname "$(dirname "$B")")"
for slug in a b; do
  cat > "$B/2026-01-01-hand-$slug.md" <<'EOF'
---
title: "Hand-authored"
id: BL-005
status: open
created: 2026-01-01
updated: 2026-01-01
priority: P2
type: task
---

Body.
EOF
done
out="$( cd "$P" && bash "$SCRIPT" --check-ids 2>&1 )"; rc=$?
if [[ $rc -eq 0 ]] || ! grep -q "duplicate id BL-005" <<<"$out"; then
  fail "(6) --check-ids no longer reports a hand-authored duplicate (rc=$rc): $out"
fi

# ---------- (7) two linked worktrees of one repo do not mint the same id ----------
# The mode BL-235 could not fix and BL-239 closes. It only exists when `.context/` is
# TRACKED — measured 2026-08-25: 13 of 17 projects here track it, and a worktree of those
# gets its own committed `.context/`, so `find_project_root` resolves to the WORKTREE and
# each tree scans a different backlog. (With `.context/` gitignored the worktree has none
# and the resolver already hops to the main tree, which is why aidex never saw this.)
#
# The fix keeps the ID SEQUENCE repo-global while the entry file stays where the session
# is: the claim is taken in the MAIN tree's ledger, so a sibling worktree sees the number
# as spent even though the item lives on a branch it cannot read.
R="$TMP/repo"; mkdir -p "$R"
( cd "$R"
  /usr/bin/git init -q .
  mkdir -p .context/backlog
  printf 'seed
' > .context/backlog/.keep
  /usr/bin/git add -A
  /usr/bin/git -c user.email=t@t -c user.name=t commit -qm init
  /usr/bin/git worktree add -q "$TMP/wt-a" -b branch-a
  /usr/bin/git worktree add -q "$TMP/wt-b" -b branch-b ) >/dev/null 2>&1

if [[ ! -d "$TMP/wt-a/.context/backlog" ]]; then
  fail "(7) the fixture is wrong: a worktree of a repo that TRACKS .context/ must carry its own copy"
else
  ( cd "$TMP/wt-a" && bash "$SCRIPT" --origin manual --title "From worktree A" --no-index >/dev/null 2>&1 )
  ( cd "$TMP/wt-b" && bash "$SCRIPT" --origin manual --title "From worktree B" --no-index >/dev/null 2>&1 )
  id_a="$(grep -h '^id:' "$TMP/wt-a/.context/backlog"/*.md 2>/dev/null | awk '{print $2}')"
  id_b="$(grep -h '^id:' "$TMP/wt-b/.context/backlog"/*.md 2>/dev/null | awk '{print $2}')"
  if [[ -z "$id_a" || -z "$id_b" ]]; then
    fail "(7) a worktree registration wrote no id (a=[$id_a] b=[$id_b])"
  elif [[ "$id_a" == "$id_b" ]]; then
    fail "(7) two worktrees of one repo both minted $id_a — the sequence must be repo-global, not per-checkout"
  fi
  # And the entry itself stays on its own branch, where the session was working.
  [[ -n "$(find "$TMP/wt-a/.context/backlog" -maxdepth 1 -name '*.md' ! -name '00-index.md')" ]]     || fail "(7b) worktree A's item did not land in worktree A — only the id sequence is shared, not the entries"
  # The ledger lives in the MAIN tree, and holds both numbers.
  n_led="$(find "$R/.context/backlog/_claims" -name 'BL-*' 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$n_led" == 2 ]]     || fail "(7c) the main tree's ledger holds $n_led marker(s), expected 2 — it is what makes the sequence repo-global"
fi

# ---------- (8) the ledger is never committed ----------
# 13 of 17 projects track `.context/`, so without this every registration would add an
# empty marker to the diff.
if [[ -d "$R/.context/backlog/_claims" ]]; then
  tracked="$( cd "$R" && /usr/bin/git status --porcelain --untracked-files=all -- .context/backlog/_claims 2>/dev/null | wc -l | tr -d ' ')"
  [[ "$tracked" == 0 ]]     || fail "(8) the claim ledger shows up in git status ($tracked path(s)) — it is machine-local coordination state, not repo content"
fi

if [[ $failures -eq 0 ]]; then
  echo "OK: the id sequence is repo-global — parallel sessions and sibling worktrees never collide, entries stay on their branch, and the digit window and duplicate backstop both survive"
  exit 0
fi
printf '\n%d assertion(s) failed\n' "$failures"
exit 1
