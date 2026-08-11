#!/usr/bin/env bash
# test-d02-layout.sh — the docs on the live migration path describe the layout the
# scaffolder actually produces.
#
# D-02 moved the boards under `audits/<methodology>/` and renamed them to the 00- form
# (b9d690e, 2026-07-02). 05-migration-guide.md last changed 2026-06-17 and still told
# the migrator that `/aidex-audit new` creates INVENTORY.md, METHODOLOGY.md,
# CHANGELOG.md and methodology/<type>.md at the audits root -- none of which the script
# has produced since. SKILL.md mandates reading this file before accepting any migration
# move, so it is a live instruction, not archived prose: its own Step 1 creates a
# directory nothing writes to, which validate-audit.sh then reports as a methodology
# folder with three missing boards.
#
# 01-principles.md and 02-id-conventions.md joined the list once they stopped restating
# audit-conventions.md wholesale. Both are on the critical path: SKILL.md sends the
# auditor to 02 before writing the first finding id and to 01 for "the full text" of the
# principles, so a drifted copy there is read before the first row is written.
# 04-playbooks.md joined them for the same reason: SKILL.md sends the auditor here to
# choose an audit type, so it is read before every methodology is scaffolded, and it was
# still telling that reader to write into CHANGELOG.md and into a `methodology/` folder.
#
# migrate-audit.sh's "Next steps:" heredoc joined the list as a block, not as a file: it
# is the only instruction the detection path hands a caller (the script executes nothing),
# while the rest of the script names the pre-D-02 boards on purpose, because detecting
# them is its job.
#
# Run: bash skills/aidex-audit/tests/test-d02-layout.sh
# Exit: 0 if every checked file is on the canon layout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES=(
  "$SCRIPT_DIR/../references/05-migration-guide.md"
  "$SCRIPT_DIR/../references/01-principles.md"
  "$SCRIPT_DIR/../references/02-id-conventions.md"
  "$SCRIPT_DIR/../references/04-playbooks.md"
)
# Files that describe CURRENT canon and never a legacy source, so the stricter rules
# below apply to them and not to the migration guide, whose whole subject is the layout
# being migrated from.
CANON_FILES=(
  "$SCRIPT_DIR/../references/01-principles.md"
  "$SCRIPT_DIR/../references/02-id-conventions.md"
  "$SCRIPT_DIR/../references/04-playbooks.md"
)

PASS=0
FAIL=0

check() {  # <label> <matches>
  if [[ -z "$2" ]]; then
    printf '  ok: %s\n' "$1"; PASS=$((PASS+1))
  else
    printf '  FAIL: %s\n' "$1"; FAIL=$((FAIL+1))
    printf '    %s\n' "$2"
  fi
}

# The layout rules apply to instructions, not only to markdown. migrate-audit.sh prints
# the manual-migration steps from a heredoc; extract that block to a file so the same
# checks read it, and leave the surrounding detection code (which legitimately names
# INVENTORY.md, METHODOLOGY.md and CHANGELOG.md) alone.
BLOCK_DIR="$(mktemp -d)"
trap 'rm -rf "$BLOCK_DIR"' EXIT
HELP_BLOCK="$BLOCK_DIR/migrate-audit.sh--next-steps-block"
awk '/^[[:space:]]*cat <<.?EOF.?$/{p=1;next} p&&/^EOF$/{exit} p' \
  "$SCRIPT_DIR/../scripts/migrate-audit.sh" > "$HELP_BLOCK"
FILES+=("$HELP_BLOCK")

# An empty extraction passes every check below vacuously, which is how a guard goes green
# on a file it never read. Anchor on a sentence the block keeps whatever the steps say.
check "migrate-audit.sh--next-steps-block: extracted, not empty" \
      "$(grep -q 'This script only detects candidates' "$HELP_BLOCK" \
         || printf 'block empty or delimiter changed: %s' "$HELP_BLOCK")"

for f in "${FILES[@]}"; do
  rel="$(basename "$f")"

  # The pre-D-02 root boards. Every mention in these files is a DESTINATION -- what to
  # create, what to write into, what to tick off afterwards -- so there is no
  # legacy-source reading under which an uppercase board name here is correct. The
  # legacy names this guide legitimately carries name folders in `.context/plans/`.
  check "$rel: names no pre-D-02 root board" \
        "$(grep -nE '\b(INVENTORY|METHODOLOGY|CHANGELOG)\.md' "$f")"

  # `audits/methodology/` was never written to by anything; validate-audit.sh reads any
  # directory under audits/ as a methodology folder, so creating it manufactures three
  # audit-methodology-missing-board violations out of a documented setup step.
  check "$rel: creates no audits/methodology directory" \
        "$(grep -n 'audits/methodology' "$f")"

  # Run folders are ISO-dated (D-01). YYYYMMDD survives only where it names the legacy
  # folder being migrated FROM, which is always under `.context/plans/`.
  check "$rel: dates audit destinations ISO, not YYYYMMDD" \
        "$(grep -n 'audits/YYYYMMDD' "$f")"

  # D-02: the segment directly under audits/ is the METHODOLOGY, never the run. A move to
  # `audits/<name>` lands the run where none of the three boards exist, so it has no
  # lifecycle and validate-audit.sh reports it. `<type>` is the same segment under the
  # scaffolder's own name for it -- new-audit.sh:102-103 sets METHODOLOGY from TYPE (or
  # from the slug for `custom`) -- so it is spelled out here rather than tightened away.
  check "$rel: audit destinations are grouped by methodology" \
        "$(grep -nE 'audits/<[a-zA-Z_-]+>' "$f" | grep -vE 'audits/<(methodology|type)>')"
done

for f in "${CANON_FILES[@]}"; do
  rel="$(basename "$f")"

  # D-01 is ISO. These files gave backlog and plan identity as YYYYMMDD-<slug>, a format
  # rules/aidex-conventions.md bans outright.
  check "$rel: dates are ISO (D-01)" "$(grep -n 'YYYYMMDD' "$f")"

  # 03-lifecycle.md declares open/doing/done/dropped and marks the rest legacy
  # read-only. A principles file presenting the legacy chain as THE state list is read
  # before a status is ever set.
  check "$rel: presents no legacy status as current" \
        "$(grep -nE '`triaged`|`in-progress`|`closed`' "$f")"

  # Cross-references are <type>/<filename> markers (D-03); 03-lifecycle.md says
  # "never a relative markdown link", and the escalation example was one.
  check "$rel: cross-references are markers, not relative links" \
        "$(grep -nE '\[(backlog|plans?|decisions?)/[^]]*\]\(' "$f")"

  # audit-conventions.md: "the methodology folder is the namespace". Scoping ids to the
  # project forbids what canon permits -- ux/ structured while security/ is global.
  check "$rel: scopes ids to the methodology, not the project" \
        "$(grep -niE 'per project|within a project|one per project' "$f")"

  # `First Seen` was dropped from the board in BL-057; the first element of Audit Runs
  # is where first-seen lives now.
  check "$rel: does not justify a rule by a dropped column" \
        "$(grep -n 'First Seen' "$f")"
done

printf '\nd02 layout: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
