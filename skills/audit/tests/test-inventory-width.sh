#!/usr/bin/env bash
# test-inventory-width.sh — the 9-column inventory is canonical; the 11-column one still works.
#
# BL-057 dropped `First Seen` and `Last Updated` because nothing read them. Four consumers
# index inventory cells POSITIONALLY (validate-audit.sh, close-audit.sh, reindex-audits.sh
# and _lib.sh's mark_row_escalated), so the drop shifts `Audit Runs` and `Escalated To` left
# by two. A consumer that missed the shift does not crash — it silently reads the wrong
# column: reindex reads Escalated To as the run list and reports zero runs, the escalation
# mutator overwrites Escalated To with a date. Every failure mode here is quiet, which is
# why both widths get asserted through the real scripts rather than by inspection.
#
# Legacy boards are TOLERATED, not migrated: 11 projects carry their own inventories and a
# forced schema change to someone else's board is not this repo's call.

set -uo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd -P)"
PASS=0 FAIL=0
ok()   { printf '  ok: %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL: %s\n' "$1" >&2; FAIL=$((FAIL+1)); }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export TMPDIR="$TMP/tmp"; mkdir -p "$TMPDIR"  # inventory lock files are kept, never removed

board() {  # board <dir> <width>
  local d="$1" w="$2"
  mkdir -p "$d/.context/audits/ux/2026-06-01-run"
  if [[ "$w" == 9 ]]; then
    cat > "$d/.context/audits/ux/00-inventory.md" <<'EOF'
# UX Audit Inventory

| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|
| UX-01-1 | bug | auth | Token in URL | open | P1 | 2026-06-01-run | — | — |
| UX-01-2 | gap | nav | No breadcrumbs | done | P2 | 2026-06-01-run | backlog/2026-06-01-nav | done: abc1234 |
EOF
  else
    cat > "$d/.context/audits/ux/00-inventory.md" <<'EOF'
# UX Audit Inventory

| ID | Type | Module | Summary | Status | Severity | First Seen | Last Updated | Audit Runs | Escalated To | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| UX-01-1 | bug | auth | Token in URL | open | P1 | 2026-06-01 | 2026-06-01 | 2026-06-01-run | — | — |
| UX-01-2 | gap | nav | No breadcrumbs | done | P2 | 2026-06-01 | 2026-06-01 | 2026-06-01-run | backlog/2026-06-01-nav | done: abc1234 |
EOF
  fi
  printf -- '---\ntitle: "run"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\n---\n\n# Run\n' \
    > "$d/.context/audits/ux/2026-06-01-run/index.md"
  printf -- '---\ntitle: "findings"\nstatus: done\ncreated: 2026-06-01\nupdated: 2026-06-01\n---\n\n# Findings\n\nUX-01-1 UX-01-2\n' \
    > "$d/.context/audits/ux/2026-06-01-run/findings.md"
}

for W in 9 11; do
  echo "== ${W}-column board =="
  D="$TMP/w$W"; board "$D" "$W"
  cd "$D" || exit 1

  # validate: both widths must PARSE. A width it cannot parse is reported as a
  # legacy-schema warning, which is the signal this asserts the absence of.
  OUT="$(bash "$SCRIPTS/validate-audit.sh" 2>&1)"
  check "w$W: validate parses the board (no legacy-schema warning)" \
        '[[ "$OUT" != *"audit-legacy-schema"* ]]'
  # The done row carries an Escalated To marker, so the done-unevidenced rule must
  # stay silent. If Escalated To were read from the wrong column it would fire.
  check "w$W: Escalated To is read from the right column" \
        '[[ "$OUT" != *"audit-lifecycle-done-unevidenced"* ]]'

  # reindex: the roll-up counts findings per run by reading Audit Runs.
  bash "$SCRIPTS/reindex-audits.sh" >/dev/null 2>&1
  IDX="$D/.context/audits/00-index.md"
  check "w$W: reindex found the run" '[[ -f "$IDX" ]] && grep -q "2026-06-01-run" "$IDX"'
  # The roll-up line reads "· <n> open / <n> findings ·". A consumer that reads the
  # wrong column finds no run match at all and prints "0 open / 0 findings" — the
  # exact quiet failure, verified against the pre-BL-057 script.
  check "w$W: reindex counted the findings (1 open / 2), not 0" \
        'grep -q "1 open / 2 findings" "$IDX"'

  # close-audit.sh (run BEFORE the escalation below, which flips UX-01-1 to done) reads Audit Runs to decide which findings are in scope for the run
  # it is closing. Reading the wrong column makes every finding look out of scope, so
  # the unresolved-findings guard goes quiet and a run closes over an open P1.
  # UX-01-1 is `open` and names this run, so the guard MUST fire.
  CLOSE_OUT="$(bash "$SCRIPTS/close-audit.sh" 2026-06-01-run 2>&1)"
  check "w$W: close sees the open in-scope finding via Audit Runs" \
        '[[ "$CLOSE_OUT" == *"UX-01-1"* ]]'

  # mark_row_escalated: writes Audit Runs and Escalated To by index.
  ( . "$SCRIPTS/_lib.sh" >/dev/null 2>&1
    mark_row_escalated "$D/.context/audits/ux/00-inventory.md" UX-01-1 "backlog/2026-08-06-token" )
  ROW="$(grep '^| UX-01-1 ' "$D/.context/audits/ux/00-inventory.md")"
  # Assert the CELL, never the line. With the pre-BL-057 offsets a 9-column row still
  # *contains* the marker — it lands past the final pipe, outside the table entirely —
  # so a substring check on the row passes while the board is corrupt.
  ESC_CELL="$(awk -F'|' '{print (NF>=13 ? $11 : $9)}' <<<"$ROW")"
  RUNS_CELL="$(awk -F'|' '{print (NF>=13 ? $10 : $8)}' <<<"$ROW")"
  check "w$W: the marker is in the Escalated To cell" '[[ "$ESC_CELL" == *"backlog/2026-08-06-token"* ]]'
  check "w$W: the marker did NOT land in Audit Runs" '[[ "$RUNS_CELL" != *"backlog/"* ]]'
  check "w$W: Audit Runs kept the run and gained today" \
        '[[ "$RUNS_CELL" == *"2026-06-01-run"* ]]'
  check "w$W: the row still has its original column count" \
        '[[ "$(tr -cd "|" <<<"$ROW" | wc -c | tr -d " ")" -eq $(( W + 1 )) ]]'
  check "w$W: escalation did not clobber the Summary" '[[ "$ROW" == *"Token in URL"* ]]'
  check "w$W: escalation set the status to done" '[[ "$ROW" == *"| done |"* ]]'

  cd - >/dev/null || exit 1
done

cd "$TMP" || exit 1

# ---------------------------------------------------------------------------
# A pipe inside a Summary cell. Markdown escapes it as `\|`; the parser split on
# the raw character, so the escape shifted every column right by one,
# looks_like_status read the wrong field, and the row was skipped SILENTLY. The
# validator then reported the row's own id as an orphan reference — accusing the
# findings file of citing something the board does in fact carry.
#
# Found while landing the 2026-08-17 code-review run, whose CR-20 summary quotes
# `grep -qE "duplicate|replayed"`. Escaping did not help, so the character was
# removed from the cell as a workaround; this is the fix.
#
# Both halves are asserted, because they fail differently:
#   escaped   -> must parse, exactly like any other row
#   unescaped -> is malformed markdown and cannot parse, but must be REPORTED
#                rather than dropped. A skipped row that nothing mentions is the
#                same lie-by-omission one level up.
# ---------------------------------------------------------------------------
echo "== pipe in a Summary cell =="
pipeboard() {  # pipeboard <dir> <summary-cell>
  local d="$1" summary="$2"
  mkdir -p "$d/.context/audits/ux/2026-06-01-run"
  { printf '# UX Audit Inventory\n\n'
    printf '| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |\n'
    printf '|---|---|---|---|---|---|---|---|---|\n'
    printf '| UX-01-9 | bug | tests | %s | open | P3 | 2026-06-01-run | — | — |\n' "$summary"
  } > "$d/.context/audits/ux/00-inventory.md"
  printf -- '---\ntitle: "run"\nstatus: open\ncreated: 2026-06-01\nupdated: 2026-06-01\n---\n\n# Run\n' \
    > "$d/.context/audits/ux/2026-06-01-run/index.md"
  printf -- '---\ntitle: "findings"\nstatus: open\ncreated: 2026-06-01\nupdated: 2026-06-01\n---\n\n# Findings\n\nUX-01-9\n' \
    > "$d/.context/audits/ux/2026-06-01-run/findings.md"
}

D="$TMP/pipe-esc"; pipeboard "$D" 'the assertion greps "duplicate\|replayed"'
cd "$D" || exit 1
OUT="$(bash "$SCRIPTS/validate-audit.sh" 2>&1)"
check "an escaped pipe in Summary still parses (no orphan accusation)" \
      '[[ "$OUT" != *"audit-orphan-finding-ref"* ]]'
check "the escaped-pipe row is counted, not skipped" \
      '[[ "$OUT" != *"audit-legacy-schema"* ]]'
cd "$TMP" || exit 1

D="$TMP/pipe-raw"; pipeboard "$D" 'the assertion greps "duplicate|replayed"'
cd "$D" || exit 1
OUT_RAW="$(bash "$SCRIPTS/validate-audit.sh" 2>&1)"
# Assert the RULE, not the id: the orphan violation quotes UX-01-9 in its own
# message, so a substring check on the id passes on the unfixed parser — the
# vacuous-assertion shape this run is closing elsewhere.
check "an unescaped pipe is reported as an unparseable row, never dropped" \
      '[[ "$OUT_RAW" == *"audit-inventory-row-unparseable"* ]]'
cd "$TMP" || exit 1

# ---------------------------------------------------------------------------
# The playbooks ship a SECOND copy of the row contract, into the same directory.
#
# new-audit.sh seeds 00-inventory.md and 00-methodology.md side by side, and six
# playbooks carry their own literal example row. d63d71c (BL-057) narrowed the board
# to 9 columns, updated one line of one playbook, and left the rest at 11 — so the
# scaffolder installed a board and an instruction that disagreed about its own shape.
# Nothing looked: this file drives the real consumers, and no test read
# assets/templates/methodology/ at all. Asserting the width against the TEMPLATE
# HEADER rather than a hardcoded 9 is what makes the next schema change fail here.
# ---------------------------------------------------------------------------
echo "== playbook row contract =="
TPL="$(cd "$SCRIPTS/../assets/templates" && pwd -P)"
HDR="$(grep -m1 '^| ID | Type |' "$TPL/00-inventory.md.template")"
CANON=$(( $(tr -cd '|' <<<"$HDR" | wc -c | tr -d ' ') - 1 ))
check "the inventory template header is readable" '[[ "$CANON" -ge 5 ]]'

for pb in "$TPL"/methodology/*.md.template; do
  name="$(basename "$pb" .md.template)"
  # A finding-row example is the one that ends in the run slug — that is the cell the
  # auditor is being told to write, and every playbook that has one writes it this way.
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    n=$(( $(tr -cd '|' <<<"$row" | wc -c | tr -d ' ') - 1 ))
    check "$name: example row is $CANON cells, like the board it is written into" \
          "[[ $n -eq $CANON ]]"
  done < <(grep '^|.*{{DATE}}-<slug>' "$pb")

  # The methodology file lands BESIDE 00-inventory.md (new-audit.sh writes both into
  # $M_DIR), so a `..` in the path leaves the methodology folder, and `INVENTORY.md` is
  # the pre-D-02 root board validate-audit.sh warns on as audit-legacy-root-boards.
  STRAY="$(grep -n 'INVENTORY\.md\|\.\./00-inventory\.md' "$pb")"
  check "$name: names 00-inventory.md, not a board outside its own folder" \
        '[[ -z "$STRAY" ]]'
  [[ -n "$STRAY" ]] && printf '    %s\n' "$STRAY"

  # 03-lifecycle.md declares `triaged`, `in-progress` and `closed` legacy: tooling may
  # READ them off an unmigrated board and must never write one. The agent section below
  # therefore checks writes only. A playbook is neither reader nor migrator — new-audit.sh
  # renders it into <methodology>/00-methodology.md as the instruction the auditor follows
  # — so the stricter rule applies here: a legacy status named at all is one the auditor
  # is told to select on or to write. Selection is the quieter half; retest asked for
  # `triaged` and `in-progress`, and so skipped every finding in `doing`.
  LEGACY_ST="$(grep -nE '`(triaged|in-progress|closed)`' "$pb")"
  check "$name: names only the base status vocabulary" '[[ -z "$LEGACY_ST" ]]'
  [[ -n "$LEGACY_ST" ]] && printf '    %s\n' "$LEGACY_ST"

  # 03-lifecycle.md puts the verification marker (commit SHA, PR link, re-test run) in
  # `Notes`, and `Escalated To` carries D-03 markers only — `backlog/<…>`, `plan/<…>`,
  # `loop/<…>`. There is no `fix:` type in D-03, so a playbook instructing `fix:abc1234`
  # has invented a marker AND put it in the column that reads escalations (retest did,
  # BL-159). This catches the invented form, which is the artifact the defect leaves; a
  # sentence that misroutes the commit without naming a marker is not machine-caught.
  BAD_MARKER="$(grep -nE 'fix:[A-Za-z0-9]' "$pb")"
  check "$name: invents no fix: marker for the Escalated To column" '[[ -z "$BAD_MARKER" ]]'
  [[ -n "$BAD_MARKER" ]] && printf '    %s\n' "$BAD_MARKER"
done

# ---------------------------------------------------------------------------
# The agents are the fifth writer of that row, and the one d63d71c did not bring
# to width. inventory-seeder.md carried an 8-column shape (no Notes) aimed at a
# global INVENTORY.md, so /aidex:audit migrate -- the one path that mass-produces
# rows -- produced them short a column, in a legacy location, with a legacy status.
# An agent that embeds the shape cannot be migrated by editing the template, so the
# assertion is that it embeds none and reads the target board's header instead.
# ---------------------------------------------------------------------------
echo "== agent row contract =="
# Only inventory-seeder writes rows; the other plugin agents legitimately mention CHANGELOG.md.
# A missing file must fail loudly: an empty glob here once made these checks pass vacuously.
SEEDER="$SCRIPTS/../../../agents/inventory-seeder.md"
if [[ ! -f "$SEEDER" ]]; then
  check "agents/inventory-seeder.md exists at the plugin level" 'false'
  SEEDERS=()
else
  SEEDERS=("$SEEDER")
fi
for ag in "${SEEDERS[@]}"; do
  name="$(basename "$ag" .md)"
  EMBED="$(grep -n '^| *ID *|' "$ag")"
  check "$name: embeds no row shape of its own" '[[ -z "$EMBED" ]]'
  [[ -n "$EMBED" ]] && printf '    %s\n' "$EMBED"
  # The pre-D-02 root boards. audit-conventions.md says verbatim that there is no
  # global INVENTORY.md / METHODOLOGY.md / CHANGELOG.md at .context/audits/.
  LEGACY="$(grep -nE '\b(INVENTORY|METHODOLOGY|CHANGELOG)\.md' "$ag")"
  check "$name: names no pre-D-02 root board" '[[ -z "$LEGACY" ]]'
  [[ -n "$LEGACY" ]] && printf '    %s\n' "$LEGACY"
  # 03-lifecycle.md: tooling may READ the legacy statuses and must never write one.
  # A `→ `status`` is a write instruction; a quoted phrase being matched is a read.
  WRITES="$(grep -nE '(→|->) *`(closed|triaged|in-progress)`' "$ag")"
  check "$name: writes only the base status vocabulary" '[[ -z "$WRITES" ]]'
  [[ -n "$WRITES" ]] && printf '    %s\n' "$WRITES"
done

# ---------------------------------------------------------------------------
# Which findings belong to the run being closed or counted (audit-c24, c25, c32).
# close-audit.sh and reindex-audits.sh matched the Audit Runs cell by substring, so a run
# `2026-10-14-foo` also claimed findings of `2026-10-14-foo-bar` and of any same-day run,
# and a row whose Summary carries two escaped pipes (13 raw fields) was read as an
# 11-column row, taking Escalated To for Audit Runs and dropping out of scope.
# ---------------------------------------------------------------------------
echo "== run scope: whole slugs, escaped pipes =="
scopeboard() {  # scopeboard <dir> — two sibling runs, three open rows
  local d="$1"
  mkdir -p "$d/.context/audits/ux/2026-10-14-foo" "$d/.context/audits/ux/2026-10-14-foo-bar"
  { printf '# UX Audit Inventory\n\n'
    printf '| ID | Type | Module | Summary | Status | Severity | Audit Runs | Escalated To | Notes |\n'
    printf '|---|---|---|---|---|---|---|---|---|\n'
    printf '| UX-01-1 | bug | a | other run, slug extends ours | open | P2 | 2026-10-14-foo-bar | — | — |\n'
    printf '| UX-01-2 | bug | a | other run, same day | open | P2 | 2026-10-14-baz | — | — |\n'
    printf '%s\n' "$2"
  } > "$d/.context/audits/ux/00-inventory.md"
  local r
  for r in foo foo-bar; do
    printf -- '---\ntitle: "run-%s"\nstatus: done\ncreated: 2026-10-14\nupdated: 2026-10-14\n---\n\n# Run\n' "$r" \
      > "$d/.context/audits/ux/2026-10-14-$r/index.md"
    printf -- '---\ntitle: "findings"\nstatus: done\ncreated: 2026-10-14\nupdated: 2026-10-14\n---\n\n# Findings\n\nUX-01-1 UX-01-2 UX-01-3 UX-01-4\n' \
      > "$d/.context/audits/ux/2026-10-14-$r/findings.md"
  done
}

D="$TMP/scope-other"; scopeboard "$D" '| UX-01-3 | bug | a | ours, already fixed | fixed | P2 | 2026-10-14-foo | — | — |'
cd "$D" || exit 1
bash "$SCRIPTS/reindex-audits.sh" >/dev/null 2>&1
IDX="$D/.context/audits/00-index.md"
check "reindex: a run whose slug is a prefix of another counts only its own findings (0 open / 1)" \
      'grep "\[run-foo\]" "$IDX" | grep >/dev/null "0 open / 1 findings"'
check "reindex: the longer run counts its own finding (1 open / 1)" \
      'grep "\[run-foo-bar\]" "$IDX" | grep >/dev/null "1 open / 1 findings"'
CLOSE_OUT="$(bash "$SCRIPTS/close-audit.sh" 2026-10-14-foo 2>&1)"; CLOSE_RC=$?
check "close: another run's open findings (slug-prefix, same day) do not block the close" \
      '[[ $CLOSE_RC -eq 0 && -d "$D/.context/audits/ux/_archive/2026-10-14-foo" ]]'
[[ $CLOSE_RC -ne 0 ]] && printf '    %s\n' "$CLOSE_OUT"
cd "$TMP" || exit 1

# 9 columns, escaped pipes in Summary: one escape makes 12 raw fields (read as the narrow
# board), two make 13 (read as the wide one); both are 9-column rows.
D="$TMP/scope-pipes"; scopeboard "$D" '| UX-01-3 | bug | a | greps "a\|b" | open | P2 | 2026-10-14-foo | — | — |
| UX-01-4 | bug | a | greps "a\|b" and "c\|d" | fixed | P2 | 2026-10-14-foo | — | — |'
cd "$D" || exit 1
CLOSE_OUT="$(bash "$SCRIPTS/close-audit.sh" 2026-10-14-foo 2>&1)"; CLOSE_RC=$?
check "close: an open row with one escaped pipe is in scope and blocks" \
      '[[ $CLOSE_RC -ne 0 && "$CLOSE_OUT" == *"UX-01-3"* ]]'
check "close: a fixed row with two escaped pipes is resolved, not listed as unresolved" \
      '[[ "$CLOSE_OUT" != *"UX-01-4"* ]]'
bash "$SCRIPTS/reindex-audits.sh" >/dev/null 2>&1
check "reindex: escaped-pipe rows are counted for their run (1 open / 2)" \
      'grep "\[run-foo\]" "$D/.context/audits/00-index.md" | grep >/dev/null "1 open / 2 findings"'
cd "$TMP" || exit 1

# A bare-date token (legacy rows, escalation) still claims every run of that date.
D="$TMP/scope-bare-date"; scopeboard "$D" '| UX-01-5 | bug | a | bare date | open | P2 | 2026-10-14 | — | — |'
cd "$D" || exit 1
CLOSE_OUT="$(bash "$SCRIPTS/close-audit.sh" 2026-10-14-foo 2>&1)"; CLOSE_RC=$?
check "close: an open row whose Audit Runs is the bare run date blocks and is listed" \
      '[[ $CLOSE_RC -ne 0 && "$CLOSE_OUT" == *"UX-01-5"* ]]'
cd "$TMP" || exit 1

echo
echo "inventory width: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
