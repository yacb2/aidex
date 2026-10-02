#!/usr/bin/env bash
# test-viewports-key-lockstep.sh — BL-618: the profile key `viewports: desktop` and the
# n/a marker must be named identically by the style template, rubric line 5, the grader's
# step 3 and the handoff instruction in SKILL.md; a rename at one site silently breaks the rest.
#
# Run with: bash skills/artifact/tests/test-viewports-key-lockstep.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$HERE/.."
failures=0
KEY='viewports: desktop'
MARK='n/a (desktop-only profile)'

check() { # file needle label
  grep -qF -- "$2" "$1" || { printf 'FAIL: %s lacks "%s"\n' "$3" "$2"; failures=$((failures + 1)); }
}
check "$SKILL/assets/templates/artifact-style.md.template" "$KEY" template
check "$SKILL/references/05-visual-review.md" "$KEY" rubric
check "$SKILL/references/05-visual-review.md" "$MARK" rubric
check "$SKILL/../../agents/artifact-grader.md" "$KEY" grader
check "$SKILL/../../agents/artifact-grader.md" "$MARK" grader
check "$SKILL/SKILL.md" "$KEY" handoff

[ "$failures" -eq 0 ] && echo "PASS: viewports key lockstep" || { echo "FAILED: $failures"; exit 1; }
