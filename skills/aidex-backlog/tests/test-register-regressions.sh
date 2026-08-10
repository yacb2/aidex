#!/usr/bin/env bash
# test-register-regressions.sh — regression cells for the defects aidex-review found
# in register-item.sh on 2026-08-10 (first end-to-end run of that skill).
#
# Every cell here was RED before its fix and reproduces a defect that shipped silently,
# which is the common thread: five of the six reported SUCCESS while doing nothing, or
# the wrong thing. `set -euo pipefail` does not catch any of them.
#
# Isolated temp project. No network, no real .context/ touched.

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
REG="$SCRIPTS/register-item.sh"
PASS=0 FAIL=0
ok()  { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fresh() {                      # fresh <name> -> a clean project dir, echoed
  local d="$TMP/$1"
  rm -rf "$d"; mkdir -p "$d/.context/backlog"
  printf '%s' "$d"
}
fm() {                         # fm <file> <key> -> front-matter value
  awk -v k="$2" '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1==k":" {sub(/^[^:]*:[[:space:]]*/,""); print; exit}' "$1"
}

echo "register-item.sh regression cells:"

# ── B1 · a failed write must not report success ───────────────────────────────
# Was: the redirect fails, "Backlog entry created" still prints, the nonexistent
# path goes to stdout and the script exits 0 — so a caller records a path that
# was never written. `set -e` does not abort on a compound-command redirect.
D="$(fresh b1)"; cd "$D"
OUT="$(bash "$REG" --origin manual --title "T" --slug 'sub/dir' 2>/dev/null)"; RC=$?
[[ $RC -ne 0 ]] && ok "B1 unwritable path exits non-zero" || bad "B1 unwritable path exited 0"
[[ -z "$OUT" || -e "$OUT" ]] && ok "B1 no phantom path on stdout" || bad "B1 printed a path that does not exist: $OUT"

D="$(fresh b1b)"; cd "$D"; chmod 555 .context/backlog
OUT="$(bash "$REG" --origin manual --title "T" 2>/dev/null)"; RC=$?
chmod 755 .context/backlog
[[ $RC -ne 0 ]] && ok "B1 read-only dir exits non-zero" || bad "B1 read-only dir exited 0"
[[ -z "$OUT" || -e "$OUT" ]] && ok "B1 read-only dir prints no phantom path" || bad "B1 phantom path: $OUT"

# ── B2 · the id sequence must survive BL-999 ──────────────────────────────────
# Was: printf 'BL-%03d' mints BL-1000, which the 3-digit-only max filter then
# rejects, so max stays 999 and BL-1000 is re-minted forever.
D="$(fresh b2)"; cd "$D"
cat > .context/backlog/2026-01-01-bl-999-seed.md <<'EOF'
---
title: "seed"
id: BL-999
status: open
created: 2026-01-01
updated: 2026-01-01
---
EOF
A="$(bash "$REG" --origin manual --title "after nine ninety nine" 2>/dev/null)"
[[ "$(fm "$A" id)" == "BL-1000" ]] && ok "B2 BL-999 -> BL-1000" || bad "B2 got $(fm "$A" id) after BL-999"
B="$(bash "$REG" --origin manual --title "and one more" 2>/dev/null)"
[[ "$(fm "$B" id)" == "BL-1001" ]] && ok "B2 BL-1000 -> BL-1001 (no re-mint)" || bad "B2 re-minted: $(fm "$B" id)"

# The legacy-id guard must still hold: a date-shaped id may not drive the sequence.
D="$(fresh b2b)"; cd "$D"
cat > .context/backlog/2026-01-01-legacy.md <<'EOF'
---
title: "legacy"
id: BL-20260610
status: open
created: 2026-01-01
updated: 2026-01-01
---
EOF
C="$(bash "$REG" --origin manual --title "next after legacy" 2>/dev/null)"
[[ "$(fm "$C" id)" == "BL-001" ]] && ok "B2 date-shaped legacy id still skipped" || bad "B2 legacy id drove the sequence: $(fm "$C" id)"

# ── B3 · front-matter injection through --title / --blocked-by ────────────────
# Was: both interpolated raw into a double-quoted YAML scalar. A newline + `---`
# terminates the front-matter early (hiding the id, so the id gets reused); a
# double quote injects a second key that wins last-write.
D="$(fresh b3)"; cd "$D"
EVIL="$(printf 'pwn\n---\nid: BL-666')"
E1="$(bash "$REG" --origin manual --title "$EVIL" 2>/dev/null)"
[[ -n "$E1" && -f "$E1" ]] && ok "B3 newline title still writes an entry" || bad "B3 newline title produced no file"
[[ "$(fm "$E1" id)" == "BL-001" ]] && ok "B3 newline title cannot forge/hide the id" || bad "B3 id is '$(fm "$E1" id)' — front-matter was terminated early"
[[ "$E1" != *$'\n'* ]] && ok "B3 filename carries no newline" || bad "B3 newline survived into the filename"

D="$(fresh b3b)"; cd "$D"
E2="$(bash "$REG" --origin manual --title 'has "quotes" inside' --blocked-by 'x"
status: done' 2>/dev/null)"
[[ "$(fm "$E2" status)" == "open" ]] && ok "B3 blocked-by cannot inject a second status" || bad "B3 status is '$(fm "$E2" status)'"
[[ "$(fm "$E2" id)" == "BL-001" ]] && ok "B3 quoted title keeps front-matter intact" || bad "B3 quoted title broke front-matter"

# ── B4 · stamp_escalated_to must insert when the key is absent ────────────────
# Was: only a rewrite branch, so stamping a legacy item wrote nothing and still
# printed "Stamped source ... -> escalated_to: ...". One-way handshake.
D="$(fresh b4)"; cd "$D"
mkdir -p "$TMP/b4tgt/.context/backlog"
cat > .context/backlog/2026-01-01-bl-007-legacy.md <<'EOF'
---
title: "legacy source"
id: BL-007
status: open
created: 2026-01-01
updated: 2026-01-01
priority: P2
---

# legacy source
EOF
bash "$REG" --origin manual --title "route it over" --escalate-to "$TMP/b4tgt" --source-id BL-007 >/dev/null 2>&1
SRC=".context/backlog/2026-01-01-bl-007-legacy.md"
grep -q '^escalated_to:' "$SRC" && ok "B4 escalated_to inserted when absent" || bad "B4 stamp reported success and wrote nothing"

# ── B5 · no dangling cross-repo link ─────────────────────────────────────────
# Was: the source was stamped to point at a counterpart written afterwards; if
# that write failed the source pointed at nothing and the run still exited 0.
D="$(fresh b5)"; cd "$D"
mkdir -p "$TMP/b5tgt/.context"
: > "$TMP/b5tgt/.context/backlog"      # a FILE where the backlog dir must be
bash "$REG" --origin manual --title "will not land" --escalate-to "$TMP/b5tgt" >/dev/null 2>&1
RC=$?
[[ $RC -ne 0 ]] && ok "B5 failed counterpart exits non-zero" || bad "B5 exited 0 with no counterpart"
if ls .context/backlog/*.md >/dev/null 2>&1; then
  bad "B5 wrote a source item pointing at a counterpart that does not exist"
else
  ok "B5 no dangling source item left behind"
fi

# ── B6 · the escalate path must not discard validated flags ──────────────────
# Was: --estimate/--status/--blocked-by passed their validation gates and were
# then overwritten by emit_backlog_stub's hardcoded values, with no warning.
D="$(fresh b6)"; cd "$D"
mkdir -p "$TMP/b6tgt/.context/backlog"
bash "$REG" --origin manual --title "blocked big job" --escalate-to "$TMP/b6tgt" \
  --priority P0 --estimate XL --blocked-by "vendor API" >/dev/null 2>&1
# Not `*.md` — the auto-generated 00-index.md sorts first and would be read instead.
S6="$(ls .context/backlog/2026-*-bl-*.md 2>/dev/null | head -1)"
if [[ -n "$S6" ]]; then
  [[ "$(fm "$S6" estimate)" == "XL" ]] && ok "B6 --estimate reaches the stub" || bad "B6 estimate is '$(fm "$S6" estimate)', expected XL"
  [[ "$(fm "$S6" blocked_by)" == '"vendor API"' ]] && ok "B6 --blocked-by reaches the stub" || bad "B6 blocked_by is '$(fm "$S6" blocked_by)'"
else
  bad "B6 no source item written"
fi

# ── B7 · --list must not print a heading for an empty priority ────────────────
# Was: print_section's `[[ ${#items[@]} -eq 0 ]] && return` guard was dead code.
# The call site passes "${P0[@]:-}", which on an empty array expands to ONE empty
# string, not zero args — so items had length 1 and every heading printed. A list
# with a single P2 item showed five headings, four of them over nothing.
D="$(fresh b7)"; cd "$D"
bash "$REG" --origin manual --title "only a medium one" --priority P2 >/dev/null 2>&1
LIST="$(NO_COLOR=1 bash "$REG" --list 2>/dev/null)"
HEADS="$(printf '%s\n' "$LIST" | grep -c '^P[0-3] —\|^Blocked\|^Unclassified' || true)"
[[ "$HEADS" -eq 1 ]] && ok "B7 one populated priority prints exactly one heading" \
  || bad "B7 printed $HEADS headings for a single P2 item (expected 1)"
printf '%s\n' "$LIST" | grep -q 'P2 — Medium' && ok "B7 the populated heading is still printed" \
  || bad "B7 the P2 heading went missing"

# ── B8 · --list's read_field must stop at the front-matter boundary ───────────
# Was: read_field had no front-matter tracking (the three other readers in this
# script all have it), so `$1 == key` matched anywhere in the file. `exit`-on-first
# -match hides this for generated items, which always carry every key — so the cell
# has to be HAND-AUTHORED, with the key absent from front-matter and present in the
# body. Body prose then decided which section --list filed the item under.
D="$(fresh b8)"; cd "$D"
cat > .context/backlog/2026-01-01-bl-001-prose.md <<'EOF'
---
title: "prose must not set fields"
id: BL-001
status: open
created: 2026-01-01
updated: 2026-01-01
priority: P2
---

# prose must not set fields

## Context

This item used to be blocked. The field we deleted from the header read:

blocked_by: "a vendor that no longer matters"

It is not blocked any more, which is why the key is gone from the front-matter.
EOF
LIST="$(NO_COLOR=1 bash "$REG" --list 2>/dev/null)"
printf '%s\n' "$LIST" | grep -q 'Blocked' \
  && bad "B8 body prose routed an unblocked item into Blocked" \
  || ok "B8 body prose cannot supply blocked_by"
printf '%s\n' "$LIST" | grep -q 'P2 — Medium' \
  && ok "B8 the item stays in its real priority section" \
  || bad "B8 the item vanished from the active queue"

# ── B9 · the audit Notes line must use the resolved path, not the raw run ─────
# Was: origin_ref correctly resolved the D-02 methodology off disk into AUDIT_REL,
# and then the Notes line re-derived the path from the raw $AUDIT_RUN — emitting
# `.context/audits/<run>/`, which under the grouped layout does not exist. The ref
# was right and the human-readable path beside it pointed nowhere.
D="$(fresh b9)"; cd "$D"
mkdir -p .context/audits/security/2026-01-01-first-pass
A9="$(bash "$REG" --origin audit --title "grouped run" --finding F-01 --audit-run 2026-01-01-first-pass 2>/dev/null)"
grep -q 'audits/security/2026-01-01-first-pass/' "$A9" \
  && ok "B9 Notes path carries the D-02 methodology segment" \
  || bad "B9 Notes path is $(grep -o '\.context/audits/[^`]*' "$A9" | head -1) — the methodology is missing"
[[ "$(fm "$A9" origin_ref)" == "audit/security/2026-01-01-first-pass/F-01" ]] \
  && ok "B9 origin_ref still resolves the methodology" \
  || bad "B9 origin_ref is '$(fm "$A9" origin_ref)'"

# The pre-D-02 ungrouped fallback must keep working: no audits/ tree at all.
D="$(fresh b9b)"; cd "$D"
A9B="$(bash "$REG" --origin audit --title "flat run" --finding F-02 --audit-run 2026-01-01-flat 2>/dev/null)"
grep -q 'audits/2026-01-01-flat/' "$A9B" \
  && ok "B9 ungrouped legacy run still emits the flat path" \
  || bad "B9 the flat fallback broke"

# ── B10 · one entry template, and the two call sites keep their differences ───
# Was: emit_backlog_stub was a hand-maintained second copy of the main write block,
# already drifted in three flags and in empty-slug handling. Unifying them is only
# correct if the two DELIBERATE differences survive — the escalate stub carries a
# real Context note where the normal path carries the unfilled template comment,
# and only the normal path appends the audit Notes lines. A merge that flattens
# either one passes a cell that just checks "both have front-matter".
D="$(fresh b10)"; cd "$D"
M10="$(bash "$REG" --origin manual --title "normal path" 2>/dev/null)"
grep -q 'Why is this worth doing' "$M10" \
  && ok "B10 normal path keeps the unfilled Context prompt" \
  || bad "B10 the normal path lost its Context template comment"

mkdir -p "$TMP/b10tgt/.context/backlog"
bash "$REG" --origin manual --title "routed job" --escalate-to "$TMP/b10tgt" >/dev/null 2>&1
# by title, not `head -1`: the normal-path item registered above sorts first
S10="$(grep -l 'routed job' .context/backlog/2026-*-bl-*.md 2>/dev/null | head -1)"
T10="$(grep -l 'routed job' "$TMP/b10tgt"/.context/backlog/2026-*-bl-*.md 2>/dev/null | head -1)"
grep -q 'Escalated to' "$S10" \
  && ok "B10 escalate source keeps its real Context note" \
  || bad "B10 the escalate stub lost its Context note"
grep -q 'routed here for execution' "$T10" \
  && ok "B10 counterpart keeps its own Context note" \
  || bad "B10 the counterpart lost its Context note"
grep -q 'Why is this worth doing' "$S10" \
  && bad "B10 the template comment leaked into an escalate stub that has a real note" \
  || ok "B10 the two Context blocks stay distinct"

D="$(fresh b10b)"; cd "$D"
mkdir -p .context/audits/perf/2026-01-01-run
A10="$(bash "$REG" --origin audit --title "from an audit" --finding F-09 --audit-run 2026-01-01-run 2>/dev/null)"
grep -q 'Origin: audit finding \[F-09\]' "$A10" \
  && ok "B10 the audit Notes lines survive the unification" \
  || bad "B10 the audit Notes lines were lost"

# The escaped title belongs in the YAML scalar, NOT in the markdown H1. Both copies
# put ESC_TITLE in both places, so a title with a quote rendered as \" in the body.
D="$(fresh b10c)"; cd "$D"
Q10="$(bash "$REG" --origin manual --title 'a "quoted" word' 2>/dev/null)"
[[ "$(fm "$Q10" title)" == '"a \"quoted\" word"' ]] \
  && ok "B10 front-matter title stays escaped" \
  || bad "B10 front-matter title is $(fm "$Q10" title)"
grep -q '^# a "quoted" word$' "$Q10" \
  && ok "B10 the body heading is not YAML-escaped" \
  || bad "B10 body heading is '$(grep '^# ' "$Q10" | head -1)' — YAML escaping leaked into markdown"

# ── B11 · an audit item with no --audit-run must not report a failed write ────
# The inverse of every other cell here: the file is written CORRECTLY and the
# script reports failure. `[[ -n "$AUDIT_RUN" ]] && echo ...` was the last command
# of the `if` block, so with no --audit-run it returned 1, the enclosing { } group
# inherited that status, and `|| die` fired "could not write" — on a file that is
# right there on disk. The caller gets exit 2 and no path, the item exists, and its
# id is spent. Found 2026-08-10 while unifying the templates for BL-137.
D="$(fresh b11)"; cd "$D"
B11OUT="$(bash "$REG" --origin audit --title "no run given" --finding F-77 2>/dev/null)"; RC=$?
[[ $RC -eq 0 ]] && ok "B11 audit item without --audit-run exits 0" \
  || bad "B11 exited $RC on a write that succeeded"
[[ -n "$B11OUT" && -f "$B11OUT" ]] && ok "B11 the path is returned to the caller" \
  || bad "B11 wrote the file but returned no path — an orphan with a spent id"
[[ -n "$B11OUT" ]] && grep -q 'Origin: audit finding \[F-77\]' "$B11OUT" \
  && ok "B11 the finding is still recorded" || bad "B11 lost the finding line"

# ── B12 · the dangling link, reached at last ──────────────────────────────────
# B5 above asserts the same property but never reaches the vulnerable window: its
# fixture puts a FILE where the target backlog dir belongs, so `mkdir -p` fails
# BEFORE the source is written. That is why this defect went unreproduced when it
# was first reported. The window needs the target directory to EXIST and the write
# to fail later — a read-only directory does exactly that.
D="$(fresh b12)"; cd "$D"
mkdir -p "$TMP/b12tgt/.context/backlog"; chmod 555 "$TMP/b12tgt/.context/backlog"
bash "$REG" --origin manual --title "cannot land" --escalate-to "$TMP/b12tgt" >/dev/null 2>&1; RC=$?
chmod 755 "$TMP/b12tgt/.context/backlog"
[[ $RC -ne 0 ]] && ok "B12 unwritable target exits non-zero" || bad "B12 exited 0"
S12="$(ls .context/backlog/2026-*-bl-*.md 2>/dev/null | head -1)"
[[ -z "$S12" ]] && ok "B12 no source item points at a counterpart that was never written" \
  || bad "B12 left a source item with escalated_to: $(fm "$S12" escalated_to)"

# Same window on the --source-id branch: an existing item must not be stamped with
# a forward link to a counterpart whose write failed.
D="$(fresh b12b)"; cd "$D"
mkdir -p "$TMP/b12btgt/.context/backlog"; chmod 555 "$TMP/b12btgt/.context/backlog"
cat > .context/backlog/2026-01-01-bl-005-existing.md <<'EOF'
---
title: "existing source"
id: BL-005
status: open
created: 2026-01-01
updated: 2026-01-01
priority: P2
escalated_to: ""
---

# existing source
EOF
bash "$REG" --origin manual --title "route it" --escalate-to "$TMP/b12btgt" --source-id BL-005 >/dev/null 2>&1
chmod 755 "$TMP/b12btgt/.context/backlog"
[[ "$(fm .context/backlog/2026-01-01-bl-005-existing.md escalated_to)" == '""' ]] \
  && ok "B12 existing item not stamped toward a counterpart that failed" \
  || bad "B12 stamped escalated_to: $(fm .context/backlog/2026-01-01-bl-005-existing.md escalated_to)"

# ── B13 · the counterpart must roll back when the source side fails ───────────
# Writing the target first closes the dangling-link direction, and opens the other
# one: a counterpart whose origin points at a source that was never written. The
# rollback has to run through `if ! VAR=$(...)` — `die` inside $( ) exits the
# subshell, `set -e` aborts the parent AT the assignment, and a rollback written on
# the following line would never execute.
D="$(fresh b13)"; cd "$D"
mkdir -p "$TMP/b13tgt/.context/backlog"
chmod 555 .context/backlog
bash "$REG" --origin manual --title "source cannot be written" --escalate-to "$TMP/b13tgt" >/dev/null 2>&1; RC=$?
chmod 755 .context/backlog
[[ $RC -ne 0 ]] && ok "B13 unwritable source exits non-zero" || bad "B13 exited 0"
T13="$(ls "$TMP/b13tgt"/.context/backlog/2026-*-bl-*.md 2>/dev/null | head -1)"
[[ -z "$T13" ]] && ok "B13 counterpart rolled back when the source could not be written" \
  || bad "B13 left an orphan counterpart: $T13"

cd /
echo
if [[ $FAIL -eq 0 ]]; then
  echo "OK — register-item regressions: $PASS cells, 12 defects covered"
  exit 0
fi
echo "FAIL — $FAIL of $((PASS+FAIL)) cells"
exit 1
