#!/usr/bin/env bash
# test-escalation.sh — escalation writes CANON cross-refs (rebuild 2026-07-02):
#   - Escalated To cell = <type>/<filename> MARKER (never a markdown relative link)
#   - backlog entry origin_ref = audit/<methodology>/<run>/<finding-id>
#   - row flips to base vocab: done + ISO dates
#   - --loop path: loop-spec front-matter gains the origin_ref back-link
#
# Runs the real sibling scripts (backlog register, loop scaffold)
# from the repo checkout. Run with: bash skills/audit/tests/test-escalation.sh

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export XDG_STATE_HOME="$TMP/state"  # the escalation log must not leak into the real home
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"  # inventory lock files are kept, never removed
mkdir -p "$TMP/.context/audits/ux/2026-06-01-first-pass" "$TMP/.context/backlog" "$TMP/.context/loops"
cd "$TMP"
A=".context/audits"
TODAY="$(date +%F)"

cat > "$A/ux/00-inventory.md" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Token stored in URL | open | P1 | 2026-06-01 | — | — |
| F-2 | gap | a11y | Contrast below AA across app | open | P2 | 2026-06-01 | — | — |
EOF
echo "# m" > "$A/ux/00-methodology.md"; echo "# c" > "$A/ux/00-changelog.md"
printf -- '---\ntitle: "UX first pass"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\nmethodology: ux\n---\n' > "$A/ux/2026-06-01-first-pass/index.md"
printf '# Findings\n\n- **F-1** token\n- **F-2** contrast\n' > "$A/ux/2026-06-01-first-pass/findings.md"

# --- escalate to backlog ---
bash "$SCRIPTS/escalate-finding.sh" F-1 >/dev/null 2>&1 || fail "escalate F-1 exited non-zero"
BL_FILE="$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index | sed -n 1p)"
[[ -n "$BL_FILE" ]] || fail "no backlog entry created"
if [[ -n "$BL_FILE" ]]; then
  grep -q '^origin_ref: audit/ux/2026-06-01-first-pass/F-1' "$BL_FILE" \
    || fail "backlog origin_ref: expected audit/ux/2026-06-01-first-pass/F-1, got: $(grep '^origin_ref' "$BL_FILE")"
fi
row="$(grep '| F-1 ' "$A/ux/00-inventory.md")"
printf '%s' "$row" | grep >/dev/null '| done |' || fail "row status should be done, row: $row"
printf '%s' "$row" | grep >/dev/null -E 'backlog/[a-z0-9][a-z0-9-]*' || fail "Escalated To should carry a backlog/<filename> marker, row: $row"
if printf '%s' "$row" | grep >/dev/null '](' ; then fail "Escalated To must be a MARKER, not a markdown link: $row"; fi
if printf '%s' "$row" | grep >/dev/null -E '\| [0-9]{8} \|'; then fail "row carries legacy YYYYMMDD date: $row"; fi
# the marker must resolve per the conventions validator (cross-ref lookup)
MARKER="$(printf '%s' "$row" | grep -oE 'backlog/[a-z0-9][a-z0-9._-]*' | sed -n 1p)"
CAND="${MARKER#backlog/}"
[[ -f ".context/backlog/$CAND" || -f ".context/backlog/$CAND.md" ]] || fail "marker $MARKER does not resolve to the created file"

# --- escalate to loop-spec (--loop): back-link in front-matter ---
bash "$SCRIPTS/escalate-finding-to-loop.sh" F-2 --loop >/dev/null 2>&1 || fail "escalate --loop F-2 exited non-zero"
LOOP_FILE="$(ls .context/loops/*.md 2>/dev/null | grep -v STATE | sed -n 1p)"
[[ -n "$LOOP_FILE" ]] || fail "no loop-spec created"
if [[ -n "$LOOP_FILE" ]]; then
  grep -q '^origin_ref: audit/ux/2026-06-01-first-pass/F-2' "$LOOP_FILE" \
    || fail "loop-spec front-matter lacks the origin_ref back-link, got: $(grep '^origin_ref' "$LOOP_FILE" || echo '(none)')"
fi
row2="$(grep '| F-2 ' "$A/ux/00-inventory.md")"
printf '%s' "$row2" | grep >/dev/null '| done |' || fail "F-2 status should be done, row: $row2"
printf '%s' "$row2" | grep >/dev/null -E 'loop/[a-z0-9][a-z0-9._-]*' || fail "F-2 Escalated To should carry a loop/<filename> marker, row: $row2"
if printf '%s' "$row2" | grep >/dev/null '](' ; then fail "F-2 Escalated To must be a MARKER, not a markdown link: $row2"; fi

# --- the escalated tree still validates clean ---
bash "$SCRIPTS/validate-audit.sh" "$A" >/dev/null 2>&1 || fail "escalated tree should validate clean"

# Each block below gets its own project root: escalate-finding.sh refuses a second
# single escalation within 10 min of the last one in the same project.
new_project() { # <name> -> creates $TMP/<name>/.context/audits and cds into it
  mkdir -p "$TMP/$1/.context/audits" "$TMP/$1/.context/backlog" "$TMP/$1/.context/loops"
  cd "$TMP/$1" || exit 1
}
row_of() { grep "^| $2 |" "$1"; }

# --- audit-c03: ids are methodology-scoped; a bare id held by two inventories is
# refused, and <methodology>/<id> picks one ---
new_project c03
for m in a11y ux; do
  mkdir -p "$A/$m/2026-06-01-run"
  printf '| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |\n|---|---|---|---|---|---|---|---|---|\n| F-001 | bug | app | %s finding summary | open | P1 | 2026-06-01 | — | — |\n' "$m" > "$A/$m/00-inventory.md"
  printf '# Findings\n\n- **F-001** %s\n' "$m" > "$A/$m/2026-06-01-run/findings.md"
done
out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -ne 0 ]] || fail "c03: a bare id in two inventories should be refused, got rc 0"
[[ "$out" == *"a11y/00-inventory.md"* && "$out" == *"ux/00-inventory.md"* ]] \
  || fail "c03: the refusal should name both inventories, got: $out"
[[ "$out" != *"not found"* ]] || fail "c03: an ambiguous id is not a missing one, got: $out"
row_of "$A/a11y/00-inventory.md" F-001 | grep >/dev/null '| open |' || fail "c03: refused escalation touched the a11y row"
row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| open |' || fail "c03: refused escalation touched the ux row"
[[ -z "$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index)" ]] || fail "c03: refused escalation created a backlog entry"
out="$(bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop --dry-run 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"ux/00-inventory.md"* ]] || fail "c03: --loop should refuse a bare ambiguous id too, rc $rc: $out"
bash "$SCRIPTS/escalate-finding.sh" ux/F-001 >/dev/null 2>&1 || fail "c03: ux/F-001 should escalate"
row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "c03: ux/F-001 should mark the ux row done: $(row_of "$A/ux/00-inventory.md" F-001)"
row_of "$A/a11y/00-inventory.md" F-001 | grep >/dev/null '| open |' || fail "c03: ux/F-001 must not touch the a11y row"
BL_FILE="$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index | sed -n 1p)"
[[ -n "$BL_FILE" ]] && grep -q '^origin_ref: audit/ux/2026-06-01-run/F-001$' "$BL_FILE" \
  || fail "c03: backlog origin_ref should be audit/ux/2026-06-01-run/F-001, got: $(grep '^origin_ref' "$BL_FILE" 2>/dev/null)"
bash "$SCRIPTS/escalate-finding-to-loop.sh" a11y/F-001 --loop >/dev/null 2>&1 || fail "c03: a11y/F-001 --loop should escalate"
row_of "$A/a11y/00-inventory.md" F-001 | grep >/dev/null -E '\| done \| P1 \| 2026-06-01, [0-9-]+ \| loop/' \
  || fail "c03: a11y/F-001 --loop should mark the a11y row: $(row_of "$A/a11y/00-inventory.md" F-001)"
LOOP_FILE="$(ls .context/loops/*.md 2>/dev/null | grep -v STATE | sed -n 1p)"
[[ -n "$LOOP_FILE" ]] && grep -q '^origin_ref: audit/a11y/2026-06-01-run/F-001$' "$LOOP_FILE" \
  || fail "c03: loop origin_ref should be audit/a11y/2026-06-01-run/F-001, got: $(grep '^origin_ref' "$LOOP_FILE" 2>/dev/null)"

# --- audit-c01: a cell carrying the markdown escape \| is one cell (validate-audit's
# convention) for extract_finding_row, mark_row_escalated and the status pre-check ---
new_project c01
mkdir -p "$A/ux"
INV="$A/ux/00-inventory.md"
cat > "$INV" <<'EOF'
| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| F-1 | bug | auth | Login \| open redirect | open | P1 | 2026-06-01 | — | — |
| F-2 | bug | auth | Grep a\|b pattern | done | P2 | 2026-06-01 | backlog/x | — |
EOF
got="$( . "$SCRIPTS/_lib.sh"; extract_finding_row "$INV" F-1 )"
[[ "$got" == 'Login \| open redirect'$'\t''P1' ]] || fail "c01: extract_finding_row should return the whole summary and P1, got: $got"
( . "$SCRIPTS/_lib.sh"; mark_row_escalated "$INV" F-1 backlog/bl-1 )
want="| F-1 | bug | auth | Login \\| open redirect | done | P1 | 2026-06-01, $TODAY | backlog/bl-1 | — |"
[[ "$(row_of "$INV" F-1)" == "$want" ]] || fail "c01: mark_row_escalated row, want: $want got: $(row_of "$INV" F-1)"
out="$(bash "$SCRIPTS/escalate-finding.sh" F-2 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"already done"* ]] || fail "c01: a done row with \\| in its summary should be refused as already done, rc $rc: $out"
[[ -z "$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index)" ]] || fail "c01: the done row was escalated again (backlog entry created)"

# --- audit-c06: find_audit_run matches the id as a whole token, never a substring ---
new_project c06
R="$A/sec"
mkdir -p "$R/2026-02-01-x" "$R/2026-03-01-b" "$R/2026-04-01-z"
printf '# Findings\n\n- **BUG-01-10** other\n' > "$R/2026-02-01-x/findings.md"
printf '# Findings\n\n- **BUG-01-1** this one\n' > "$R/2026-03-01-b/findings.md"
printf '# Findings\n\n*None yet.*\n' > "$R/2026-04-01-z/findings.md"
got="$( . "$SCRIPTS/_lib.sh"; find_audit_run "$R" BUG-01-1 )"
[[ "$got" == "2026-03-01-b" ]] || fail "c06: BUG-01-1 was recorded by 2026-03-01-b, got: $got"
got="$( . "$SCRIPTS/_lib.sh"; find_audit_run "$R" BUG-01-9 )"
[[ "$got" == "2026-04-01-z" ]] || fail "c06: an unrecorded id should fall back to the newest run, got: $got"

# --- audit-c40: two concurrent escalations on one inventory both land, mode kept ---
new_project c40
mkdir -p "$A/ux"
INV="$A/ux/00-inventory.md"
lost=0
for i in 1 2 3 4 5; do
  printf '| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |\n|---|---|---|---|---|---|---|---|---|\n| F-1 | bug | a | one | open | P1 | 2026-06-01 | — | — |\n| F-2 | bug | a | two | open | P1 | 2026-06-01 | — | — |\n' > "$INV"
  chmod 644 "$INV"
  ( . "$SCRIPTS/_lib.sh"; mark_row_escalated "$INV" F-1 backlog/bl-1 ) &
  ( . "$SCRIPTS/_lib.sh"; mark_row_escalated "$INV" F-2 backlog/bl-2 ) &
  wait
  [[ "$(grep -c '| done |' "$INV")" == 2 ]] || lost=$((lost + 1))
done
[[ $lost -eq 0 ]] || fail "c40: $lost of 5 concurrent pairs lost an update"
mode="$(stat -c %a "$INV" 2>/dev/null || stat -f %Lp "$INV")"  # GNU first: BSD -f is filesystem status on GNU
[[ "$mode" == 644 ]] || fail "c40: inventory mode should stay 644, got $mode"

BOARD_HEAD='| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |\n|---|---|---|---|---|---|---|---|---|\n'
board() { # <file> <id>... -> a 9-column board with one open row per id
  local f="$1"; shift; mkdir -p "$(dirname "$f")"; printf "$BOARD_HEAD" > "$f"
  for id in "$@"; do printf '| %s | bug | app | %s summary | open | P1 | 2026-06-01 | — | — |\n' "$id" "$id" >> "$f"; done
}
backlog_count() { ls .context/backlog/*.md 2>/dev/null | grep -vc 00-index; }

# --- both legacy root boards are ONE board (validate-audit prefers 00-inventory.md):
# a unique id there is not ambiguous ---
new_project roots
board "$A/00-inventory.md" F-001
board "$A/INVENTORY.md" F-001
out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "roots: F-001 on the two legacy root boards should escalate, rc $rc: $out"
row_of "$A/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "roots: 00-inventory.md F-001 row should be done: $(row_of "$A/00-inventory.md" F-001)"
[[ "$(backlog_count)" == 1 ]] || fail "roots: expected exactly one backlog file, got $(backlog_count)"
# half-migrated: the id lives only in the legacy INVENTORY.md beside a 00-inventory.md
new_project roots-half
board "$A/00-inventory.md" F-009
board "$A/INVENTORY.md" F-001
out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "roots-half: F-001 only in INVENTORY.md should escalate, rc $rc: $out"
row_of "$A/INVENTORY.md" F-001 | grep >/dev/null '| done |' || fail "roots-half: INVENTORY.md F-001 row should be done: $(row_of "$A/INVENTORY.md" F-001)"
[[ "$(backlog_count)" == 1 ]] || fail "roots-half: expected exactly one backlog file, got $(backlog_count)"
new_project roots-legacy
board "$A/INVENTORY.md" F-001
got="$( . "$SCRIPTS/_lib.sh"; find_inventory_for_id "$A" F-001 2>&1 )"
[[ "$got" == "$A/INVENTORY.md" ]] || fail "roots-legacy: a lone INVENTORY.md should resolve, got: $got"

# --- the inventory lock is a kernel lock (lock_take in conventions/_lib.sh): a killed
# holder never blocks, a live one is waited for and never taken over. The old mkdir lock
# took over by age and lost escalations (two waiters both removed it; a future mtime
# deleted a live lock: wl-review-r2 B1, bkb-review-r1 F1). Its DIRECTORY, named
# aidex-inv.<digest>.lock directly in TMPDIR, may be left by a run of the old code, or be
# held by one still in flight. The new lock lives in the per-user directory
# and must neither wedge on that directory nor remove it (an old run relies on it).
# lib_digest: the library's own path_digest (shasum, else sha256sum, else cksum), never a
# hand copy, so the test names the lock the code names on any host
lib_digest() { ( . "$SCRIPTS/_lib.sh"; path_digest ); }
# inv_key <inventory> [digest-cmd] -> the 16-char digest of the inventory's real path
inv_key() { printf '%s' "$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")" | ${2:-lib_digest} | cut -c1-16; }
# inv_name <tmpdir> <inventory> [digest-cmd] -> the lock name without its suffix, in the
# per-user lock directory under <tmpdir> (created 0700 here when missing, as the code does)
inv_name() { mkdir -m 700 "$1/aidex.locks.$EUID" 2>/dev/null; printf '%s/aidex.locks.%s/aidex-inv.%s' "$1" "$EUID" "$(inv_key "$2" "${3:-}")"; }
# old_name <tmpdir> <inventory> [digest-cmd] -> where the old mkdir lock lived, without `.lock`
old_name() { printf '%s/aidex-inv.%s' "$1" "$(inv_key "$2" "${3:-}")"; }
# hold <lockfile> <seconds> [log] — a perl flock holder in the background (HPID); returns
# once it holds the lock, appends "released" to <log> as it lets go. The fifo is opened
# first so a holder that dies early ends the read instead of hanging it.
hold() {
  local fifo="$TMP/hold.$RANDOM"; mkfifo "$fifo"
  perl -MFcntl=:flock -e 'my ($lock, $fifo, $secs, $log) = @ARGV;
    open(R, ">", $fifo) or die; open(H, ">>", $lock) or die; flock(H, LOCK_EX) or die;
    print R "held\n"; close R; sleep $secs;
    if ($log) { open(L, ">>", $log); print L "released\n"; close L }' "$1" "$fifo" "$2" "${3:-}" &
  HPID=$!; read -r _ < "$fifo"; rm -f "$fifo"
}
killhold() { kill -9 "$HPID" 2>/dev/null; { wait "$HPID"; } 2>/dev/null; }

# a killed holder and an aged old-style lock dir: ten escalations at once all land
new_project stale
LOCKDIR="$TMP/stale-tmp"; mkdir -p "$LOCKDIR"
INV="$A/ux/00-inventory.md"; mkdir -p "$A/ux"; L="$(inv_name "$LOCKDIR" "$INV")"; O="$(old_name "$LOCKDIR" "$INV")"
errs="$TMP/stale.err"; : > "$errs"; lost=0
for r in 1 2 3 4 5; do
  board "$INV" F-1 F-2 F-3 F-4 F-5 F-6 F-7 F-8 F-9 F-10
  rm -rf "$O.lock"; mkdir "$O.lock"; touch -t 202601010000 "$O.lock"
  hold "$L.flock" 600
  for i in 1 2 3 4 5 6 7 8 9 10; do
    ( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$INV" "F-$i" "backlog/bl-$i" || echo "rc $? on F-$i" >&2 ) 2>>"$errs" &
  done
  sleep 0.3; killhold; wait
  [[ "$(grep -c '| done |' "$INV")" == 10 ]] || lost=$((lost + 1))
done
[[ $lost -eq 0 ]] || fail "stale: $lost of 5 rounds lost an escalation behind a killed holder and an old lock dir"
[[ ! -s "$errs" ]] || fail "stale: every escalation should exit 0 with no takeover, stderr: $(sort "$errs" | uniq -c | sed -n 1,5p)"
[[ -d "$O.lock" ]] || fail "stale: the aged old lock dir is not ours to remove"

# a future-dated old-style lock dir is not a lock: it is neither waited for nor removed
new_project future
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/future-tmp"; mkdir -p "$LOCKDIR"; L="$(inv_name "$LOCKDIR" "$A/ux/00-inventory.md")"
O="$(old_name "$LOCKDIR" "$A/ux/00-inventory.md")"; mkdir "$O.lock"; touch -t 203001010000 "$O.lock"
hold "$L.flock" 600; killhold
out="$(TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "future: a killed holder should not block the escalation, rc $rc: $out"
row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "future: F-001 row should be done"
[[ "$(backlog_count)" == 1 ]] || fail "future: expected exactly one backlog file, got $(backlog_count)"
[[ "$out" != *"taking over"* ]] || fail "future: nothing is taken over any more: $out"
[[ -d "$O.lock" ]] || fail "future: the future-dated old lock dir is not ours to remove"

# a fresh old-style lock dir (an old-code run in flight) does not hold the write up
new_project leftover
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/leftover-tmp"; mkdir -p "$LOCKDIR"; O="$(old_name "$LOCKDIR" "$A/ux/00-inventory.md")"
mkdir "$O.lock"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
[[ $rc -eq 0 && -z "$out" ]] || fail "leftover: an old lock dir should not affect the write, rc $rc: $out"
row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "leftover: F-001 row should be done"
[[ -d "$O.lock" ]] || fail "leftover: the old lock dir is not ours to remove"

# GNU coreutils: `stat -f` is filesystem status (prints a block, exits 1) and shasum may
# be missing. Stubs emulate that host. An aged old-style WINDOW lock dir (the mkdir lock
# escalate-finding.sh had before lock_take) is ignored, not taken over or removed; the
# inventory lock must be named by the next digest.
new_project gnu
board "$A/ux/00-inventory.md" F-001
STUB="$TMP/gnu-bin"; mkdir -p "$STUB"
cat > "$STUB/stat" <<'STUBEOF'
#!/bin/sh
case "$1" in
  -f) printf '  File: "%s"\n    ID: 1 Namelen: 255 Type: apfs\n' "$3"; exit 1 ;;
  -c) /usr/bin/stat -c "$2" "$3" 2>/dev/null && exit 0   # a GNU host: the real form
      [ "$2" = "%Y" ] && exec /usr/bin/stat -f %m "$3"; exit 1 ;;
esac
exec /usr/bin/stat "$@"
STUBEOF
printf '#!/bin/sh\nexit 127\n' > "$STUB/shasum"
chmod +x "$STUB/stat" "$STUB/shasum"
# with shasum gone, lock and log names come from the next digest on the host
digest() { PATH="$STUB:$PATH" lib_digest; }
LOCKDIR="$TMP/gnu-tmp"; mkdir -p "$LOCKDIR"
L="$(inv_name "$LOCKDIR" "$A/ux/00-inventory.md" digest)"
O="$(old_name "$LOCKDIR" "$A/ux/00-inventory.md" digest)"; mkdir "$O.lock"; touch -t 202601010000 "$O.lock"
WLOCK="$XDG_STATE_HOME/aidex/escalation-log/$(printf '%s' "$(pwd -P)" | digest).lock"
mkdir -p "$WLOCK"; touch -t 202601010000 "$WLOCK"
out="$(PATH="$STUB:$PATH" TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 && "$out" != *"taking over"* ]] || fail "gnu: an aged old-style window lock dir under GNU stat and no shasum should not hold the escalation up, rc $rc: $out"
[[ -d "$WLOCK" ]] || fail "gnu: the old-style window lock dir is not ours to remove"
row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "gnu: F-001 row should be done"
[[ "$(backlog_count)" == 1 ]] || fail "gnu: expected exactly one backlog file, got $(backlog_count)"
[[ -f "$L.flock" ]] || fail "gnu: the inventory lock should be named by the no-shasum digest ($L.flock): $(ls "$(dirname "$L")")"

# a LIVE holder is waited for, never taken over: the write lands after it lets go
new_project busy
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/busy-tmp"; mkdir -p "$LOCKDIR"; L="$(inv_name "$LOCKDIR" "$A/ux/00-inventory.md")"
log="$TMP/busy.log"
hold "$L.flock" 2 "$log"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; rc=0; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 || rc=$?; echo written >> "$log"; exit $rc )"; rc=$?
{ wait "$HPID"; } 2>/dev/null
[[ $rc -eq 0 ]] && row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "busy: the row should be marked once the holder lets go, rc $rc: $out"
[[ "$(tr '\n' ' ' < "$log")" == "released written " ]] || fail "busy: the write should land after the live holder exits, order: $(tr '\n' ' ' < "$log")"
[[ "$out" != *"taking over"* ]] || fail "busy: a live lock must not be taken over: $out"
# nothing in the inventory lock path removes a lock or judges one by age (T6)
[[ "$(sed -n '/^mark_row_escalated()/,/^}/p' "$SCRIPTS/_lib.sh" | grep -cE 'rmdir|unlink|rm [^"]*"\$lock|stat |taking over')" == 0 ]] \
  || fail "busy: mark_row_escalated still removes or ages a lock"

# a lock that cannot be taken refuses the write: rc 2, the inventory named, nothing written
new_project lockedout
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/lockedout-tmp"; mkdir -p "$LOCKDIR"; L="$(inv_name "$LOCKDIR" "$A/ux/00-inventory.md")"
mkdir "$L.flock"; before="$(cksum < "$A/ux/00-inventory.md")"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
[[ $rc -eq 2 && "$out" == *"could not lock $A/ux/00-inventory.md"* ]] || fail "lockedout: should refuse with rc 2 naming the inventory, rc $rc: $out"
[[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "lockedout: the inventory was written without the lock"
[[ "$(ls "$A/ux")" == 00-inventory.md ]] || fail "lockedout: a temp file was left: $(ls "$A/ux" | tr '\n' ' ')"

# a write that fails under the lock reports it and leaves the board as it was
new_project rofail
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/rofail-tmp"; mkdir -p "$LOCKDIR"
before="$(cksum < "$A/ux/00-inventory.md")"; chmod 555 "$A/ux"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
chmod 755 "$A/ux"
[[ $rc -ne 0 ]] || fail "rofail: a failed write (no temp file possible) should not exit 0: $out"
[[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "rofail: the board changed"

# the lock lives in a per-user directory, never the shared temp namespace (/tmp on Linux,
# where another user could plant a symlink at a guessable name): created 0700 if missing
new_project lockdir
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/lockdir-tmp"; mkdir -p "$LOCKDIR"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
mode="$(stat -c %a "$LOCKDIR/aidex.locks.$EUID" 2>/dev/null || stat -f %Lp "$LOCKDIR/aidex.locks.$EUID" 2>/dev/null)"
[[ $rc -eq 0 && "$mode" == 700 ]] || fail "lockdir: the lock directory should be created 0700, rc $rc mode '$mode': $out"
[[ -f "$(inv_name "$LOCKDIR" "$A/ux/00-inventory.md").flock" ]] || fail "lockdir: the lock file should sit in the per-user directory: $(ls -R "$LOCKDIR")"
# a symlink planted where that directory goes is refused: rc 2, the inventory untouched
new_project lockdir-sym
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/lockdir-sym-tmp"; mkdir -p "$LOCKDIR" "$TMP/elsewhere"
ln -s "$TMP/elsewhere" "$LOCKDIR/aidex.locks.$EUID"
before="$(cksum < "$A/ux/00-inventory.md")"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
[[ $rc -eq 2 && "$out" == *"$LOCKDIR/aidex.locks.$EUID"* ]] || fail "lockdir-sym: a symlinked lock directory should be refused with rc 2 naming it, rc $rc: $out"
[[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "lockdir-sym: the inventory was written"
[[ -z "$(ls "$TMP/elsewhere")" ]] || fail "lockdir-sym: a lock was created through the symlink: $(ls "$TMP/elsewhere")"
# a regular file where that directory goes is refused by the directory check itself (not
# later, by lock_take failing to open a path under a file): rc 2, the inventory untouched
new_project lockdir-file
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/lockdir-file-tmp"; mkdir -p "$LOCKDIR"; : > "$LOCKDIR/aidex.locks.$EUID"
before="$(cksum < "$A/ux/00-inventory.md")"
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
[[ $rc -eq 2 && "$out" == *"lock directory"* ]] || fail "lockdir-file: a file at the lock directory should be refused by the directory check, rc $rc: $out"
[[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "lockdir-file: the inventory was written"

# --- the methodology part of a qualified id is a folder name, never a path ---
new_project qual
board "$A/00-inventory.md" F-001
board ".context/00-inventory.md" F-001
board "$A/ux/00-inventory.md" F-001 ''   # a blank-id open row: "ux/" must not match it
for q in ./F-001 ../F-001 /F-001 ux/x/F-001 ux/; do
  out="$(bash "$SCRIPTS/escalate-finding-to-loop.sh" "$q" --loop --dry-run 2>&1)"; rc=$?
  [[ $rc -eq 2 && "$out" == *"is not <methodology>/<id>"* && "$out" != *"origin_ref:"* ]] \
    || fail "qual: $q should be refused as not <methodology>/<id>, rc $rc: $out"
done

# --- the id is matched literally (F-1.2 is not F-102), and archive / methodology /
# deferred folders hold no live board (validate-audit skips them) ---
new_project literal
board "$A/ux/00-inventory.md" F-1.2 F-001
board "$A/a11y/00-inventory.md" F-102
for d in _archive methodology _deferred; do board "$A/$d/00-inventory.md" F-001; done
got="$( . "$SCRIPTS/_lib.sh"; find_inventory_for_id "$A" F-1.2 2>&1 )"
[[ "$got" == "$A/ux/00-inventory.md" ]] || fail "literal: F-1.2 should resolve to ux only, got: $got"
got="$( . "$SCRIPTS/_lib.sh"; find_inventory_for_id "$A" F-001 2>&1 )"
[[ "$got" == "$A/ux/00-inventory.md" ]] || fail "literal: _archive/methodology/_deferred boards must be skipped, got: $got"

# --- audit-c02: a missing or off-canon severity escalates at the documented P2 default
# (bash 3.2 under set -u: an empty priority array was an unbound variable) ---
for sev in '—' 'High'; do
  new_project "c02-$sev"
  mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | Sev %s | open | %s | 2026-06-01 | — | — |\n' "$sev" "$sev" > "$A/ux/00-inventory.md"
  out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
  [[ $rc -eq 0 && "$out" == *"will default to P2"* ]] || fail "c02: severity '$sev' should escalate at P2, rc $rc: $out"
  BL_FILE="$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index | sed -n 1p)"
  [[ -n "$BL_FILE" ]] && grep -q '^priority: P2$' "$BL_FILE" || fail "c02: severity '$sev': the backlog item should carry priority P2: $(grep '^priority' "$BL_FILE" 2>/dev/null)"
  row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| done |' || fail "c02: severity '$sev': the row should be done"
done

# --- audit-c27: a row the mark cannot rewrite (comment on the row, `Open` capitalised, a
# short row, a status that only CONTAINS a canon word) is refused BEFORE anything is
# filed: no backlog item, row byte-identical ---
for r in '| F-001 | bug | app | Commented | open | P2 | 2026-06-01 | — | seen <!-- recheck --> |' \
         '| F-001 | bug | app | Ticked | done ✓ | P2 | 2026-06-01 | backlog/2026-06-01-old | — |' \
         '| F-001 | bug | app | Capital | Open | P2 | 2026-06-01 | — | — |' \
         '| F-001 | bug | app | Short | open | P2 |'; do
  i=$(( ${i:-0} + 1 )); new_project "c27-$i"
  mkdir -p "$A/ux"; printf "$BOARD_HEAD"'%s\n' "$r" > "$A/ux/00-inventory.md"
  before="$(cksum < "$A/ux/00-inventory.md")"
  out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
  [[ $rc -eq 2 && "$out" == *"cannot be marked escalated"* && "$out" == *"nothing was escalated"* ]] \
    || fail "c27: an unmarkable row should be refused with rc 2 before filing ($r), rc $rc: $out"
  [[ "$(backlog_count)" == 0 ]] || fail "c27: a backlog item was filed for an unmarkable row ($r)"
  [[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "c27: the refused row was written ($r)"
done

# --- audit-c23: every status the vocabulary maps to done (done, legacy escalated and
# closed: audit-conventions.md §Status map) is refused as already escalated ---
for st in escalated closed; do
  new_project "c23-$st"
  mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | Old | %s | P2 | 2026-06-01 | backlog/2026-06-01-old | — |\n' "$st" > "$A/ux/00-inventory.md"
  before="$(cksum < "$A/ux/00-inventory.md")"
  out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
  [[ $rc -eq 2 && "$out" == *"already done"* ]] || fail "c23: a '$st' row should be refused as already done, rc $rc: $out"
  [[ "$(backlog_count)" == 0 ]] || fail "c23: a '$st' row was escalated again"
  [[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "c23: the '$st' row was rewritten"
done
# the done check reads the row the mark selects: a commented-out `open` row with the
# same id above the live `done` row must not let the escalation through
new_project c23-comment
mkdir -p "$A/ux"
printf "$BOARD_HEAD"'<!--\n| F-001 | bug | app | Old | open | P2 | 2026-06-01 | — | — |\n-->\n| F-001 | bug | app | Old | done | P2 | 2026-06-01 | backlog/2026-06-01-old | — |\n' > "$A/ux/00-inventory.md"
before="$(cksum < "$A/ux/00-inventory.md")"
out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 2 && "$out" == *"already done"* ]] || fail "c23-comment: a done row under a commented-out open row should be refused as already done, rc $rc: $out"
[[ "$(backlog_count)" == 0 ]] || fail "c23-comment: the done row was escalated again"
[[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "c23-comment: the board was rewritten"

# --- BL-779 (escalate-finding.sh half): a lock directory someone else planted is refused
# BEFORE the backlog item is filed, so a retry never leaves an orphan item ---
new_project lockdir-orphan
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/lockdir-orphan-tmp"; mkdir -p "$LOCKDIR" "$TMP/elsewhere-orphan"
ln -s "$TMP/elsewhere-orphan" "$LOCKDIR/aidex.locks.$EUID"
for try in 1 2; do
  out="$(TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
  [[ $rc -eq 2 && "$out" == *"$LOCKDIR/aidex.locks.$EUID"* ]] || fail "lockdir-orphan: try $try should be refused with rc 2 naming the lock dir, rc $rc: $out"
done
[[ "$(backlog_count)" == 0 ]] || fail "lockdir-orphan: a refused escalation filed $(backlog_count) orphan backlog item(s)"
row_of "$A/ux/00-inventory.md" F-001 | grep >/dev/null '| open |' || fail "lockdir-orphan: the row should stay open"

# --- BL-779 (escalate-finding-to-loop.sh half): an unusable lock directory or a row the
# mark cannot rewrite is refused BEFORE the loop spec is scaffolded: rc 2, no spec ---
for c in sym comment; do
  new_project "loop-pre-$c"
  LOCKDIR="$TMP/loop-pre-$c-tmp"; mkdir -p "$LOCKDIR"
  if [[ $c == sym ]]; then
    board "$A/ux/00-inventory.md" F-001
    mkdir -p "$TMP/elsewhere-loop"; ln -s "$TMP/elsewhere-loop" "$LOCKDIR/aidex.locks.$EUID"; want="$LOCKDIR/aidex.locks.$EUID"
  else
    mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | C | open | P2 | 2026-06-01 | — | seen <!-- x --> |\n' > "$A/ux/00-inventory.md"; want="cannot be marked escalated"
  fi
  before="$(cksum < "$A/ux/00-inventory.md")"
  out="$(TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop 2>&1)"; rc=$?
  [[ $rc -eq 2 && "$out" == *"$want"* ]] || fail "loop-pre-$c: should refuse with rc 2 naming '$want' before scaffolding, rc $rc: $out"
  [[ -z "$(ls .context/loops/*.md 2>/dev/null)" ]] || fail "loop-pre-$c: a loop spec was scaffolded: $(ls .context/loops)"
  [[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "loop-pre-$c: the inventory was written"
done

# --- Q17: a `dropped` row (a won't-fix verdict) is refused by both escalations, before
# anything is filed or scaffolded; the verdict is never overwritten with done ---
for c in backlog loop; do
  new_project "dropped-$c"
  mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | Wontfix | dropped | P2 | 2026-06-01 | — | — |\n' > "$A/ux/00-inventory.md"
  before="$(cksum < "$A/ux/00-inventory.md")"
  if [[ $c == backlog ]]; then out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
  else out="$(bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop 2>&1)"; rc=$?; fi
  [[ $rc -eq 2 && "$out" == *"was dropped (won't fix)"* && "$out" == *"nothing was escalated"* ]] \
    || fail "dropped-$c: a dropped row should be refused with rc 2, rc $rc: $out"
  [[ "$(backlog_count)" == 0 ]] || fail "dropped-$c: a backlog item was filed for a dropped row"
  [[ -z "$(ls .context/loops/*.md 2>/dev/null)" ]] || fail "dropped-$c: a loop spec was scaffolded"
  [[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "dropped-$c: the dropped row was rewritten"
done
# the dry run previews the same escalation, so it refuses the same row
new_project dropped-dry
mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | Wontfix | dropped | P2 | 2026-06-01 | — | — |\n' > "$A/ux/00-inventory.md"
out="$(bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop --dry-run 2>&1)"; rc=$?
[[ $rc -eq 2 && "$out" == *"was dropped (won't fix)"* ]] || fail "dropped-dry: --dry-run on a dropped row should be refused with rc 2, rc $rc: $out"

# mark_row_escalated itself returns 5 on a dropped row: message, nothing written, no temp file left
new_project dropped-mark
mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | Wontfix | dropped | P2 | 2026-06-01 | — | — |\n' > "$A/ux/00-inventory.md"
INV="$A/ux/00-inventory.md"; before="$(cksum < "$INV")"
out="$( . "$SCRIPTS/_lib.sh"; mark_row_escalated "$INV" F-001 backlog/bl-1 2>&1 )"; rc=$?
[[ $rc -eq 5 && "$out" == *"was dropped"* ]] || fail "dropped-mark: mark_row_escalated should return 5 naming 'was dropped', rc $rc: $out"
[[ "$(cksum < "$INV")" == "$before" ]] || fail "dropped-mark: the dropped row was rewritten"
[[ -z "$(ls "$A"/ux/00-inventory.md.* 2>/dev/null)" ]] || fail "dropped-mark: a temp file was left: $(ls "$A"/ux)"

# --- audit-c28: --loop refuses a row that is already done and keeps its backlog marker ---
new_project loop-done
mkdir -p "$A/ux"; printf "$BOARD_HEAD"'| F-001 | bug | app | Old | done | P2 | 2026-06-01 | backlog/2026-06-01-old | — |\n' > "$A/ux/00-inventory.md"
before="$(cksum < "$A/ux/00-inventory.md")"
out="$(bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop 2>&1)"; rc=$?
[[ $rc -eq 2 && "$out" == *"already done"* && "$out" == *"nothing was escalated"* ]] || fail "loop-done: a done row should be refused with rc 2, rc $rc: $out"
[[ -z "$(ls .context/loops/*.md 2>/dev/null)" ]] || fail "loop-done: a loop spec was scaffolded"
[[ "$(cksum < "$A/ux/00-inventory.md")" == "$before" ]] || fail "loop-done: the backlog marker was replaced"

# --- BL-797: a mark that fails AFTER the loop spec was scaffolded (the row changed between
# the pre-check and the mark) exits 4 naming the spec, as escalate-finding.sh does ---
new_project loop-mark-fails
board "$A/ux/00-inventory.md" F-001
SK="$TMP/loop-mark-fails-skills"; mkdir -p "$SK"
cp -R "$SCRIPTS/../../audit" "$SCRIPTS/../../loop" "$SCRIPTS/../../conventions" "$SK/"
mv "$SK/loop/scripts/new-loop-spec.sh" "$SK/loop/scripts/real-new-loop-spec.sh"
cat > "$SK/loop/scripts/new-loop-spec.sh" <<WRAP
#!/usr/bin/env bash
f="\$("$SK/loop/scripts/real-new-loop-spec.sh" "\$@")" || exit \$?
sed -i.bak 's/| open |/| dropped |/' "$TMP/loop-mark-fails/$A/ux/00-inventory.md" && rm -f "$TMP/loop-mark-fails/$A/ux/00-inventory.md.bak"
printf '%s\n' "\$f"
WRAP
chmod +x "$SK/loop/scripts/new-loop-spec.sh"
out="$(bash "$SK/audit/scripts/escalate-finding-to-loop.sh" F-001 --loop 2>&1)"; rc=$?
LOOP_FILE="$(ls .context/loops/*.md 2>/dev/null | grep -v STATE | sed -n 1p)"
[[ -n "$LOOP_FILE" ]] || fail "loop-mark-fails: the wrapper did not scaffold a spec"
[[ $rc -eq 4 && "$out" == *"$LOOP_FILE"* && "$out" == *"was not marked"* ]] \
  || fail "loop-mark-fails: a mark failing after the scaffold should exit 4 naming the spec ($LOOP_FILE), rc $rc: $out"

# --- BL-779: the loop spec takes the umask mode of a created file, never mktemp's 0600;
# concurrent escalations of one id (loop x loop, loop x backlog) are serialised by the
# project escalation lock: one lands, the other is refused as done, nothing orphaned ---
modeof() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }  # GNU first, as c40
new_project loop-mode
board "$A/ux/00-inventory.md" F-001
( umask 022; bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop >/dev/null 2>&1 ) || fail "loop-mode: escalate --loop exited non-zero"
( umask 022; : > "$TMP/loop-mode-ref" )
LOOP_FILE="$(ls .context/loops/*.md 2>/dev/null | sed -n 1p)"
[[ -n "$LOOP_FILE" && "$(modeof "$LOOP_FILE")" == "$(modeof "$TMP/loop-mode-ref")" ]] \
  || fail "loop-mode: the loop spec should have mode $(modeof "$TMP/loop-mode-ref") (umask 022), got $( [[ -n "$LOOP_FILE" ]] && modeof "$LOOP_FILE")"
for c in loop backlog; do
  new_project "loop-race-$c"
  board "$A/ux/00-inventory.md" F-001
  bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop >"$TMP/race-$c-a.out" 2>&1 & pa=$!
  if [[ $c == loop ]]; then bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop >"$TMP/race-$c-b.out" 2>&1 & pb=$!
  else bash "$SCRIPTS/escalate-finding.sh" F-001 >"$TMP/race-$c-b.out" 2>&1 & pb=$!; fi
  wait $pa; ra=$?; wait $pb; rb=$?
  out="$(cat "$TMP/race-$c-a.out" "$TMP/race-$c-b.out")"
  n="$(( $(ls .context/loops/*.md 2>/dev/null | wc -l) + $(backlog_count) ))"
  [[ ( "$ra $rb" == "0 2" || "$ra $rb" == "2 0" ) && "$out" == *"already done"* && "$out" != *"was not marked"* && $n -eq 1 ]] \
    || fail "loop-race-$c: one run should land and the other be refused as done (rc 2), one spec or item in all; rc $ra and $rb, $n written: $out"
done
# two ids at once: both land, and the lock keeps their LOOP ids distinct
new_project loop-race-ids
board "$A/ux/00-inventory.md" F-001 F-002
bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop >"$TMP/race-ids-a.out" 2>&1 & pa=$!
bash "$SCRIPTS/escalate-finding-to-loop.sh" F-002 --loop >"$TMP/race-ids-b.out" 2>&1 & pb=$!
wait $pa; ra=$?; wait $pb; rb=$?
ids="$(sed -n 's/^id: *//p' .context/loops/*.md 2>/dev/null | sort -u | tr '\n' ' ')"
[[ "$ra $rb" == "0 0" && "$(printf '%s' "$ids" | wc -w | tr -d ' ')" == 2 ]] \
  || fail "loop-race-ids: two ids escalated at once should both land with distinct LOOP ids; rc $ra and $rb, ids: $ids"

# --- BL-799: the lock name does not depend on CDPATH ---
new_project cdpath
mkdir -p "$A/ux" "$TMP/cdpath-decoy/.context/audits/ux"; board "$A/ux/00-inventory.md" F-001
plain="$( . "$SCRIPTS/_lib.sh"; inventory_lock_path ".context/audits/ux/00-inventory.md" )"
viacd="$( . "$SCRIPTS/_lib.sh"; CDPATH="$TMP/cdpath-decoy" inventory_lock_path ".context/audits/ux/00-inventory.md" )"
[[ -n "$plain" && "$plain" == "$viacd" ]] || fail "cdpath: a set CDPATH changed the lock path: [$plain] vs [$viacd]"

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon markers, methodology-scoped origin_ref, loop back-link, base vocab + ISO, qualified ids, escaped pipes, whole-token runs, concurrent marks, per-user 0700 lock dir, symlinked lock dir refused"
