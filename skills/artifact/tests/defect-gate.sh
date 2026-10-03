#!/usr/bin/env bash
# The contract-defect gate (LOOP-006). Four lines, fixed order:
#
#   classes: K/N   red: R/N   green: G/N   corpus: C/T
#
# Registry: one folder per class, <slug>/{original*.html, class.md, rebuilt.html},
# private, read from AIDEX_DEFECT_REGISTRY (unset: `classes: 0/unknown`). Source
# classes are scripts/dash/contract_defects.py; render classes are
# render-probe.sh --contract SLUG. The corpus is goal-gate's private sample, read
# from AIDEX_SPEC_CORPUS (unset: `corpus: 0/unknown`): each page's SPEC is built
# with spec_build.py on the current kit into a temp tree that mirrors its
# project's .context/profiles/artifact.md (the project is never written) and the
# built page is
# judged; a spec the builder refuses is a failing page. Read defect_gate.py for
# each count.
#
#   export AIDEX_DEFECT_REGISTRY=/abs/path/to/the/registry
#   export AIDEX_SPEC_CORPUS=/abs/path/to/the/corpus
#   bash skills/artifact/tests/defect-gate.sh [--verbose]
#       # full (the default, the stop condition): built corpus pages pass every source
#       # check, check-artifact.sh, render-probe.sh and every render class
#       # (Playwright via AIDEX_PLAYWRIGHT_DIR)
#   AIDEX_CORPUS_FAST=1 bash skills/artifact/tests/defect-gate.sh
#       # source checks only; the line reads `corpus: C/T (source only)`
#
# Exit 0 only when every numerator equals its denominator.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/defect_gate.py" "$@"
