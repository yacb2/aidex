#!/usr/bin/env bash
# The contract-defect gate (LOOP-006). Four lines, fixed order:
#
#   classes: K/N   red: R/N   green: G/N   corpus: C/T
#
# Registry: tests/fixtures/defect-classes/<slug>/{original,rebuilt}.html, one
# folder per class; the checks are scripts/dash/contract_defects.py. The corpus
# is goal-gate's private sample, read from AIDEX_SPEC_CORPUS (unset: the line is
# `corpus: 0/unknown`). The registry is private too: AIDEX_DEFECT_REGISTRY
# (unset: `classes: 0/unknown`). Read defect_gate.py for each count.
#
#   export AIDEX_SPEC_CORPUS=/abs/path/to/the/corpus
#   bash skills/artifact/tests/defect-gate.sh [--verbose]
#
# Exit 0 only when every numerator equals its denominator.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/defect_gate.py" "$@"
