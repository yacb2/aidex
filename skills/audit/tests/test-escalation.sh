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
row_of "$A/a11y/00-inventory.md" F-001 | grep -q '| open |' || fail "c03: refused escalation touched the a11y row"
row_of "$A/ux/00-inventory.md" F-001 | grep -q '| open |' || fail "c03: refused escalation touched the ux row"
[[ -z "$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index)" ]] || fail "c03: refused escalation created a backlog entry"
out="$(bash "$SCRIPTS/escalate-finding-to-loop.sh" F-001 --loop --dry-run 2>&1)"; rc=$?
[[ $rc -ne 0 && "$out" == *"ux/00-inventory.md"* ]] || fail "c03: --loop should refuse a bare ambiguous id too, rc $rc: $out"
bash "$SCRIPTS/escalate-finding.sh" ux/F-001 >/dev/null 2>&1 || fail "c03: ux/F-001 should escalate"
row_of "$A/ux/00-inventory.md" F-001 | grep -q '| done |' || fail "c03: ux/F-001 should mark the ux row done: $(row_of "$A/ux/00-inventory.md" F-001)"
row_of "$A/a11y/00-inventory.md" F-001 | grep -q '| open |' || fail "c03: ux/F-001 must not touch the a11y row"
BL_FILE="$(ls .context/backlog/*.md 2>/dev/null | grep -v 00-index | sed -n 1p)"
[[ -n "$BL_FILE" ]] && grep -q '^origin_ref: audit/ux/2026-06-01-run/F-001$' "$BL_FILE" \
  || fail "c03: backlog origin_ref should be audit/ux/2026-06-01-run/F-001, got: $(grep '^origin_ref' "$BL_FILE" 2>/dev/null)"
bash "$SCRIPTS/escalate-finding-to-loop.sh" a11y/F-001 --loop >/dev/null 2>&1 || fail "c03: a11y/F-001 --loop should escalate"
row_of "$A/a11y/00-inventory.md" F-001 | grep -qE '\| done \| P1 \| 2026-06-01, [0-9-]+ \| loop/' \
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
mode="$(stat -f %Lp "$INV" 2>/dev/null || stat -c %a "$INV")"
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
row_of "$A/00-inventory.md" F-001 | grep -q '| done |' || fail "roots: 00-inventory.md F-001 row should be done: $(row_of "$A/00-inventory.md" F-001)"
[[ "$(backlog_count)" == 1 ]] || fail "roots: expected exactly one backlog file, got $(backlog_count)"
# half-migrated: the id lives only in the legacy INVENTORY.md beside a 00-inventory.md
new_project roots-half
board "$A/00-inventory.md" F-009
board "$A/INVENTORY.md" F-001
out="$(bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "roots-half: F-001 only in INVENTORY.md should escalate, rc $rc: $out"
row_of "$A/INVENTORY.md" F-001 | grep -q '| done |' || fail "roots-half: INVENTORY.md F-001 row should be done: $(row_of "$A/INVENTORY.md" F-001)"
[[ "$(backlog_count)" == 1 ]] || fail "roots-half: expected exactly one backlog file, got $(backlog_count)"
new_project roots-legacy
board "$A/INVENTORY.md" F-001
got="$( . "$SCRIPTS/_lib.sh"; find_inventory_for_id "$A" F-001 2>&1 )"
[[ "$got" == "$A/INVENTORY.md" ]] || fail "roots-legacy: a lone INVENTORY.md should resolve, got: $got"

# --- a stale inventory lock (a killed run) is taken over, not waited out ---
new_project stale
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/stale-tmp"; mkdir -p "$LOCKDIR"
inv_lock() { printf '%s/aidex-inv.%s.lock' "$1" "$(printf '%s' "$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")" | shasum | cut -c1-16)"; }
LOCK="$(inv_lock "$LOCKDIR" "$A/ux/00-inventory.md")"
mkdir "$LOCK"; touch -t 202601010000 "$LOCK"
out="$(TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "stale: a stale inventory lock should be taken over, rc $rc: $out"
row_of "$A/ux/00-inventory.md" F-001 | grep -q '| done |' || fail "stale: F-001 row should be done: $(row_of "$A/ux/00-inventory.md" F-001)"
[[ "$(backlog_count)" == 1 ]] || fail "stale: expected exactly one backlog file, got $(backlog_count)"

# a lock dated in the future (clock skew, touch) is stale too
new_project future
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/future-tmp"; mkdir -p "$LOCKDIR"; LOCK="$(inv_lock "$LOCKDIR" "$A/ux/00-inventory.md")"
mkdir "$LOCK"; touch -t 203001010000 "$LOCK"
out="$(TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "future: a future-dated inventory lock should be taken over, rc $rc: $out"
row_of "$A/ux/00-inventory.md" F-001 | grep -q '| done |' || fail "future: F-001 row should be done"
[[ "$(backlog_count)" == 1 ]] || fail "future: expected exactly one backlog file, got $(backlog_count)"

# GNU coreutils: `stat -f` is filesystem status (prints a block, exits 1) and
# shasum may be missing. Stubs emulate that host; both stale locks (the window
# lock and the inventory lock) must still be taken over.
new_project gnu
board "$A/ux/00-inventory.md" F-001
STUB="$TMP/gnu-bin"; mkdir -p "$STUB"
cat > "$STUB/stat" <<'STUBEOF'
#!/bin/sh
case "$1" in
  -f) printf '  File: "%s"\n    ID: 1 Namelen: 255 Type: apfs\n' "$3"; exit 1 ;;
  -c) [ "$2" = "%Y" ] && exec /usr/bin/stat -f %m "$3"; exit 1 ;;
esac
exec /usr/bin/stat "$@"
STUBEOF
printf '#!/bin/sh\nexit 127\n' > "$STUB/shasum"
chmod +x "$STUB/stat" "$STUB/shasum"
# with shasum gone, lock and log names come from the next digest on the host
digest() { { sha256sum 2>/dev/null || cksum; } | cut -d' ' -f1; }
LOCKDIR="$TMP/gnu-tmp"; mkdir -p "$LOCKDIR"
LOCK="$LOCKDIR/aidex-inv.$(printf '%s' "$(cd "$A/ux" && pwd -P)/00-inventory.md" | digest | cut -c1-16).lock"
mkdir "$LOCK"; touch -t 202601010000 "$LOCK"
WLOCK="$XDG_STATE_HOME/aidex/escalation-log/$(printf '%s' "$(pwd -P)" | digest).lock"
mkdir -p "$WLOCK"; touch -t 202601010000 "$WLOCK"
out="$(PATH="$STUB:$PATH" TMPDIR="$LOCKDIR" bash "$SCRIPTS/escalate-finding.sh" F-001 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "gnu: stale locks under GNU stat and no shasum should be taken over, rc $rc: $out"
row_of "$A/ux/00-inventory.md" F-001 | grep -q '| done |' || fail "gnu: F-001 row should be done"
[[ "$(backlog_count)" == 1 ]] || fail "gnu: expected exactly one backlog file, got $(backlog_count)"

# a FRESH lock is waited for, never taken over
new_project busy
board "$A/ux/00-inventory.md" F-001
LOCKDIR="$TMP/busy-tmp"; mkdir -p "$LOCKDIR"; LOCK="$(inv_lock "$LOCKDIR" "$A/ux/00-inventory.md")"
mkdir "$LOCK"; ( sleep 1; rmdir "$LOCK" ) &
out="$( TMPDIR="$LOCKDIR"; . "$SCRIPTS/_lib.sh"; mark_row_escalated "$A/ux/00-inventory.md" F-001 backlog/bl-1 2>&1 )"; rc=$?
wait
[[ $rc -eq 0 ]] && row_of "$A/ux/00-inventory.md" F-001 | grep -q '| done |' || fail "busy: the row should be marked once the lock is released, rc $rc: $out"
[[ "$out" != *"taking over"* ]] || fail "busy: a fresh lock must not be taken over: $out"

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

if [[ "$failures" -gt 0 ]]; then echo "$failures failure(s)"; exit 1; fi
echo "OK — canon markers, methodology-scoped origin_ref, loop back-link, base vocab + ISO, qualified ids, escaped pipes, whole-token runs, concurrent marks"
