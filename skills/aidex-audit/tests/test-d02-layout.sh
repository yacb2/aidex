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
# SITE LIST is deliberately narrow. references/01-principles.md, 02-id-conventions.md
# and 04-playbooks.md carry the same pre-D-02 names and are not fixed here -- they are
# being rewritten under a separate item that decides who owns that prose. Widening this
# list is a one-line change once that lands.
#
# Run: bash skills/aidex-audit/tests/test-d02-layout.sh
# Exit: 0 if every checked file is on the canon layout.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES=("$SCRIPT_DIR/../references/05-migration-guide.md")

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
done

printf '\nd02 layout: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
