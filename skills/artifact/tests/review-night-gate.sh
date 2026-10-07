#!/usr/bin/env bash
# LOOP-010's gate (artifact module review). Five lines, one fixed order, every run:
#
#   partitions: N/4     partitions A-D whose correctness AND simplify runs both left
#                       a `RAN` marker row in the ledger. Inferred from markers, never
#                       from findings: a lens that found nothing and a lens that never
#                       ran look the same in the findings.
#   confirmed: R/C      CONFIRMED rows that are resolved, over all CONFIRMED rows.
#                       Resolved means, per action: `fixed` — the ref commit is in
#                       HEAD's history and touches a tests/ path; `applied` — the ref
#                       commit is in HEAD's history; `filed` — the ref BL id has a file
#                       under the workspace's .context/backlog/ and the note column
#                       carries the reason. Anything else is unresolved.
#   simplify: S applied, net source LOC D
#                       D sums `git show --numstat` over the applied commits, only
#                       paths under skills/artifact/, skills/ui-contract/ or agents/
#                       and outside any tests/ directory.
#   bl-710: done|pending|failing
#                       done when skills/conventions/scripts/test_skill_budget.sh
#                       passes and lists ui-contract under 5000 tokens, AND
#                       skills/ui-contract/tests/test-gallery-rules-owner.sh exists
#                       and passes.
#   canon-load: T0 -> T1
#                       artifact-sonnet's reading set in tokens (bytes/4): references
#                       03 and 04 whole plus reference 02 from `## Route S` to the next
#                       `## ` heading outside a code fence, at the base commit (T0) and
#                       at HEAD (T1). `unknown` when a file or the heading is missing.
#
# Exit 0 only when partitions is 4/4, R equals C, bl-710 is done, no ledger row is
# malformed and T1 < T0. Exit 2, with one stderr line and nothing on stdout, when the
# ledger cannot be found or its header is wrong.
#
# THE LEDGER IS NOT IN THIS REPO. It lives in the private workspace at
# .context/research/2026-10-07-artifact-module-review/ledger.tsv; the gate finds it
# from AIDEX_REVIEW_LEDGER, else by walking up from the repo's top level. Columns,
# tab-separated: partition lens id file_line verdict severity action ref note.
#
#   bash skills/artifact/tests/review-night-gate.sh             # the five lines
#   bash skills/artifact/tests/review-night-gate.sh --verbose   # + unresolved rows
#   bash skills/artifact/tests/review-night-gate.sh --base REF  # another T0 commit
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/review_night_gate.py" "$@"
