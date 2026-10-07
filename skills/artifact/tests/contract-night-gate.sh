#!/usr/bin/env bash
# The script-contract-and-refusals night's own gate (LOOP-009 stop condition).
# Five lines, one fixed order, every run; each fails closed (`unknown`, never a pass):
#
#   misuse: M/X          confirmed tool-misuse rows of the census replayed against the
#                        branch scripts (fixtures/misuse-replay/cases.tsv)
#   refusal-split: ...   `done` when every gate-refusal is classified by its check
#   top-refusals: k/K    checks covering >= 60% of refusals that have a passing fix test
#   bench: B -> A        refusals per built page, main vs branch (census/bench/results.tsv)
#   census: rerun ok     census.py then report.py re-run without error (--no-rerun skips)
#
# A refusal-split.tsv row whose check starts with `not-a-refusal:` is classified (it
# counts toward `refusal-split: done`) but is excluded from the top-refusals counter
# and from its 60% denominator; `deliberate` rows stay in both.
#
# Exit 0 only when M == X, the split is done, k == K, both bench arms are measured
# with A <= 0.7*B, and the census rerun is ok. Exit 2, one stderr line and nothing on
# stdout, when the census (env AIDEX_SCRIPT_CENSUS) or calls.tsv/review.tsv is missing.
#
#   bash skills/artifact/tests/contract-night-gate.sh [--verbose] [--no-rerun]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/contract_night_gate.py" "$@"
