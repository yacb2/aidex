#!/usr/bin/env bash
# The LOOP-008 invariant gate. Seven lines, fixed order (see invariant_gate.py):
#   catalog: N / corpus: X/Y / generated: G/G / rounds: R/R / mutations: M/M /
#   galleries: U/U / hunts-clean: K
# corpus is measured now; the other five are stubs that print zero until their unit lands.
# Exit 0 only when every line is green. Needs Playwright and the private spec corpus
# (AIDEX_SPEC_CORPUS, else the workspace default). --verbose names failing pages on stderr.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$HERE/invariant_gate.py" "$@"
