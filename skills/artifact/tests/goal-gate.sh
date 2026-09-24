#!/usr/bin/env bash
# The spec-format goal's own gate. Seven lines, one fixed order, every run:
#
#   corpus: N/30      pages of the frozen sample whose spec BUILDS BACK to them
#   escapes: N        converted pages that needed something outside the grammar
#   blind: N/3        Phase 5's blind trial, read from the corpus's blind-trial-log.md
#   figures: C/45     the sample's figures carried on the rung the corpus's
#                     figure-census.md assigns them (1 chart/diagram, 2 graph,
#                     3 figure file), re-derived against pages and specs
#   newly-fail: N     pages whose SOURCE passes check-artifact and whose BUILD
#                     does not
#   ladder: r1 A · r2 B · r3 C   figures ASSIGNED to each rung  (informative)
#   baseline: A -> B  what a page cost before and after, plus the newly-fail
#                     count again                               (informative)
#
# The order is fixed because the loop-spec's evaluator greps these prefixes, and
# a line that goes missing when its phase has not run yet reads exactly like a
# line that passed. `diagrams:` is retired into `figures:` — one census, one
# count.
#
# Exit status: non-zero when `corpus` or `escapes` regress against the corpus's
# `corpus-specs/GATE-FLOOR.json`, when a page that was converted stops matching
# its original, when any figure is not carried on its assigned rung, or when
# `newly-fail` is not 0. `figures` and `newly-fail` gate on completion, not on a
# floor. `blind`, `ladder` and `baseline` never set the exit status. Every count
# fails CLOSED: a blind log the gate cannot parse reads 0/3, a figure census it
# cannot parse — or one that does not record every figure of the sample exactly
# once — reads `figures: 0/unknown` (never `0/0`, which reads as done), and
# `--no-contract` prints `newly-fail: unknown` and exits 1.
#
# THE CORPUS IS NOT IN THIS REPO. It is built from the owner's private pages,
# so it lives outside it, wherever `AIDEX_SPEC_CORPUS` points (an absolute
# directory holding corpus-sample.json, baseline.json, blind-trial-log.md,
# figure-census.md and corpus-specs/ with its GATE-FLOOR.json). Unset, or
# pointing at a directory that lacks any of those, the gate prints ONE line
# on stderr naming what is missing, nothing on stdout, and exits 2 — the same
# standard as `0/unknown`: a count that measured nothing never reads as a pass.
#
# Runs from anywhere — it resolves its own directory, never the cwd:
#
#   export AIDEX_SPEC_CORPUS=/abs/path/to/the/corpus
#   bash skills/artifact/tests/goal-gate.sh              # the seven lines
#   bash skills/artifact/tests/goal-gate.sh --verbose    # + every divergence
#   bash skills/artifact/tests/goal-gate.sh --no-contract  # skip the wrap
#
# `--no-contract` skips wrapping each converted page through `wrap-report.sh`
# into a throwaway directory — the only way to judge a page the way the one
# that ships is judged, about a third of a second per page. Without it
# `newly-fail` is not measured, so the run exits 1: a quick look, never a pass.
# The newly-fail count is the one `corpus:` is blind to: the judge compares ids
# and visible text, so a build can keep every word of a page and still lose the
# structure the contract is about.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/goal_gate.py" "$@"
