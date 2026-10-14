#!/usr/bin/env bash
# escalate-finding-to-loop.sh — escalate an audit finding to an loop loop-spec.
#
# Use ONLY when the finding is bulk + machine-checkable (lint / contrast /
# type-clean / remove-all-X). Single fixes and ideas go to the backlog
# (escalate-finding.sh). Never auto-loop.
#
# Usage: escalate-finding-to-loop.sh <finding-id> [--loop] [--dry-run]
#   <finding-id> may be qualified as <methodology>/<id> (e.g. ux/F-1); a bare id
#   held by more than one methodology's inventory is refused, naming each.
#   --loop      accepted and ignored (the dispatcher passes it through)
#   --dry-run   print what would happen; scaffold nothing, mutate nothing
#
# Exit: 0 escalated; 2 refused before scaffolding (unknown or ambiguous id, done or dropped
#   row, unusable lock dir, escalation lock held by another run); 4 the loop spec was
#   scaffolded but its row could not be marked (the message names the spec; mark the row
#   by hand, do not rerun).

set -euo pipefail
. "$(dirname "$0")/_lib.sh"

# Parse args: strip the dispatched "escalate" token and the "--loop" flag,
# detect --dry-run, keep the finding id as the lone positional.
DRY_RUN=0
FINDING_ID=""
for arg in "$@"; do
  case "$arg" in
    escalate|--loop) ;;                 # dispatcher tokens — ignore
    --dry-run) DRY_RUN=1 ;;
    -*) die "unknown flag: $arg" ;;
    *) [[ -z "$FINDING_ID" ]] && FINDING_ID="$arg" || die "unexpected extra argument: $arg" ;;
  esac
done

if [[ -z "$FINDING_ID" ]]; then
  cat <<EOF >&2
Usage: /aidex:audit escalate <finding-id> --loop [--dry-run]

Escalate a bulk, machine-checkable finding to an loop loop-spec.
For single fixes and ideas, omit --loop (escalates to the backlog instead).

Example:
  /aidex:audit escalate A11Y-02-1 --loop
EOF
  exit 2
fi

ROOT="$(find_project_root)"
AUDITS_DIR="$ROOT/.context/audits"
# Canon layout: the finding lives in some audits/<methodology>/00-inventory.md
# (legacy root boards still accepted read-only).
INVENTORY="$(find_inventory_for_id "$AUDITS_DIR" "$FINDING_ID")" || { [[ $? -eq 2 ]] && exit 2
  die "finding $FINDING_ID not found in any audits/<methodology>/00-inventory.md (or legacy root inventory)"; }
FINDING_ID="${FINDING_ID#*/}"  # the inventory is resolved; everything below takes the bare id

METHODOLOGY=""
INV_PARENT="$(dirname "$INVENTORY")"
[[ "$INV_PARENT" != "$AUDITS_DIR" ]] && METHODOLOGY="$(basename "$INV_PARENT")"

AUDIT_RUN="$(find_audit_run "$INV_PARENT" "$FINDING_ID")"

# origin_ref: canon audit/<methodology>/<run>/<id>; legacy audit/<run>/<id>.
RUN_REF="$AUDIT_RUN"
[[ -n "$METHODOLOGY" ]] && RUN_REF="$METHODOLOGY/$AUDIT_RUN"
ORIGIN_REF="audit/$RUN_REF/$FINDING_ID"

# Extract Summary (cell 5) and Severity (cell 7) for the finding row.
ROW_DATA="$(extract_finding_row "$INVENTORY" "$FINDING_ID")"
SUMMARY="${ROW_DATA%%$'\t'*}"
SEVERITY="${ROW_DATA##*$'\t'}"
[[ "$SEVERITY" == "$ROW_DATA" ]] && SEVERITY=""  # no tab → no severity extracted

HAVE_SUMMARY=1
if [[ -z "$SUMMARY" ]]; then
  warn "could not extract Summary for $FINDING_ID — using an ID-based slug and a placeholder goal. Check the row's status column carries a base status (open, doing, done, dropped) or a legacy value."
  HAVE_SUMMARY=0
fi

# Derive a kebab-case slug: <finding-id>-<first words of summary>. Fall back to
# id-only when the summary is unavailable.
ID_SLUG="$(slugify "$FINDING_ID")"
SUMMARY_SLUG=""
if [[ "$HAVE_SUMMARY" -eq 1 ]]; then
  FIRST_WORDS="$(printf '%s' "$SUMMARY" | awk '{n=(NF<6?NF:6); for(i=1;i<=n;i++) printf "%s%s", (i>1?" ":""), $i}')"
  SUMMARY_SLUG="$(slugify "$FIRST_WORDS")"
fi
if [[ -n "$SUMMARY_SLUG" ]]; then
  SLUG="${ID_SLUG}-${SUMMARY_SLUG}"
else
  SLUG="$ID_SLUG"
fi
is_valid_slug "$SLUG" || die "could not derive a valid slug from finding id '$FINDING_ID'"

# Build the prefill text injected into the scaffolded loop-spec.
GOAL_TEXT="$SUMMARY"
[[ "$HAVE_SUMMARY" -eq 1 ]] || GOAL_TEXT="Resolve audit finding $FINDING_ID (summary unavailable — describe the desired end state)."
PROV_TEXT="_Escalated from audit finding ${FINDING_ID} (run ${AUDIT_RUN}${SEVERITY:+, severity ${SEVERITY}})._"
GATE_TEXT="**TODO (operator):** write the exact machine-checkable gate for this finding — the concrete command that must exit 0 (e.g. a lint/contrast/type-clean check). The loop must NOT run until this is a real pass/fail signal, not prose."

# The project escalation lock escalate-finding.sh holds (same path, fd 8), kept to exit:
# the checks, the scaffold and the mark below run under it, so a concurrent loop or
# backlog escalation of the same id waits and is then refused as done (BL-779). The dry
# run writes nothing and takes no lock.
if [[ "$DRY_RUN" -eq 0 ]]; then
  LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/aidex/escalation-log"
  LOG="$LOG_DIR/$(printf '%s' "$ROOT" | path_digest)"
  mkdir -p "$LOG_DIR" || die "cannot create $LOG_DIR; nothing was escalated"
  lock_take "$LOG.flock" 10 8 || die "could not take the escalation lock $LOG.flock (held by another escalation); nothing was escalated"
fi

# Refuse before scaffolding what the mark would refuse after it (an unusable lock
# directory, a row it cannot rewrite), so a refusal leaves no orphan loop spec (BL-779);
# before the dry run too, which previews the same escalation.
inventory_lock_path "$INVENTORY" > /dev/null || exit 2
finding_row_markable "$INVENTORY" "$FINDING_ID" || case $? in
  4) die "finding $FINDING_ID is already done (escalated); nothing was escalated" ;;
  5) die "finding $FINDING_ID was dropped (won't fix); reopen its row (status open) first if you want to escalate it; nothing was escalated" ;;
  *) die "finding $FINDING_ID's row in $INVENTORY cannot be marked escalated (a comment on the row, a status outside open/doing/done/dropped and the legacy words, or fewer than 9 columns): fix the row first; nothing was escalated" ;;
esac

if [[ "$DRY_RUN" -eq 1 ]]; then
  WOULD_BE="$ROOT/.context/loops/$(today_iso)-$SLUG.md"
  info "[dry-run] escalate $FINDING_ID --loop"
  log  "  loop-spec     : $WOULD_BE"
  log  "  Goal          : $GOAL_TEXT"
  log  "  provenance    : $PROV_TEXT"
  log  "  Stop condition: (operator supplies the exact gate)"
  log  "  loop-spec fm  : origin_ref: $ORIGIN_REF"
  log  "  inventory row : status -> done, Escalated To -> loop/$(today_iso)-$SLUG"
  log  ""
  log  "[dry-run] nothing written."
  exit 0
fi

# Delegate scaffolding to loop. Resolve its script path.
require_sibling_script NEWLOOP loop new-loop-spec.sh "$ROOT"

info "Scaffolding loop-spec for $FINDING_ID via loop"
LOOP_FILE="$("$NEWLOOP" new "$SLUG")"

if [[ -z "$LOOP_FILE" || ! -f "$LOOP_FILE" ]]; then
  die "loop did not return a valid loop-spec path"
fi

# Prefill the generated loop-spec: inject Goal + provenance + a gate TODO right
# after their section headings (instructional comments are left in place). The temp
# file sits beside the spec (atomic rename) and takes its mode (cp -p): mktemp's 0600
# must not replace it (BL-779).
TMP="$(mktemp "$LOOP_FILE.XXXXXX")"
cp -p "$LOOP_FILE" "$TMP"
awk -v goal="$GOAL_TEXT" -v prov="$PROV_TEXT" -v gate="$GATE_TEXT" '
  /^## Goal$/ { print; print ""; print goal; print ""; print prov; next }
  /^## Stop condition \(the gate\)$/ { print; print ""; print gate; next }
  { print }
' "$LOOP_FILE" > "$TMP"
mv "$TMP" "$LOOP_FILE"

# Back-link (canon forward+back invariant): the loop-spec front-matter carries
# origin_ref pointing at the finding. The template never writes one, so insert it
# before the closing front-matter delimiter.
TMP2="$(mktemp "$LOOP_FILE.XXXXXX")"
cp -p "$LOOP_FILE" "$TMP2"
awk -v ref="$ORIGIN_REF" '
  /^---[[:space:]]*$/ { c++; if (c == 2) print "origin_ref: " ref }
  { print }
' "$LOOP_FILE" > "$TMP2" && mv "$TMP2" "$LOOP_FILE"

# Canon cross-ref MARKER (D-03), never a markdown relative link.
MARKER="loop/$(basename "$LOOP_FILE" .md)"
# The row was checked markable above, under the escalation lock; a mark that still fails
# (the row edited by hand meanwhile) exits 4 (scaffolded, not marked) naming the spec, so
# a rerun does not scaffold a second spec.
mark_row_escalated "$INVENTORY" "$FINDING_ID" "$MARKER" \
  || { err "error: loop-spec $LOOP_FILE was scaffolded for $FINDING_ID, but its row in $INVENTORY was not marked: set it to done with Escalated To $MARKER by hand, or delete the spec; do not rerun (it would scaffold a second spec)"; exit 4; }

ok "$FINDING_ID escalated to loop-spec"
printf '  loop-spec    : %s\n' "$LOOP_FILE" >&2
printf '  inventory row: status -> done, Escalated To -> %s\n' "$MARKER" >&2
cat >&2 <<EOF

Next:
  1. Open the loop-spec and write the Stop condition (the exact machine gate).
  2. Choose an engine (see loop references/01-loop-engines.md).
  3. Validate: /aidex:audit validate
EOF
