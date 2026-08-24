#!/usr/bin/env bash
# normalize-language.sh — report backlog items whose body reads Spanish-dominant
# (D-04: knowledge artifacts are English; only communications/ are exempt).
#
# REPORTS, never rewrites. Translating an item's prose is a human or assisted
# step: an automatic rewrite of someone's recorded reasoning is the one thing a
# sweep must not do, and a mistranslated Acceptance is worse than a Spanish one.
#
# NO second detector (BL-226). The Spanish-dominance rule lives once, in
# validate.py's check_body_language; this filters that validator's JSON for the
# `body-language-not-english` rule scoped to the backlog. A private copy of the
# stopword heuristic would drift from the canon exactly the way BL-097's did.
#
# Note the standing severity question: the rule is a `warning`, so validate.py's
# own exit code never fails on it (BL-227). This script exits 1 on any reported
# item so a caller can gate on the backlog slice specifically.
#
# Usage: normalize-language.sh [<path-to-.context>]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$(cd "$SCRIPT_DIR/../../aidex-conventions/scripts" && pwd -P)/_lib.sh"

VALIDATOR="$SCRIPT_DIR/../../aidex-conventions/scripts/validate.py"
[[ -f "$VALIDATOR" ]] || { printf 'error: validator not found at %s\n' "$VALIDATOR" >&2; exit 2; }

CONTEXT_DIR="${1:-}"
if [[ -z "$CONTEXT_DIR" ]]; then
  CONTEXT_DIR="$(find_project_root)/.context"
fi
[[ -d "$CONTEXT_DIR" ]] || { printf 'error: no .context/ at %s\n' "$CONTEXT_DIR" >&2; exit 2; }

python3 "$VALIDATOR" --type backlog --json "$CONTEXT_DIR" \
  | python3 -c "
import json, sys

data = json.load(sys.stdin)
# The rule is defined as a warning today, but read every severity bucket: if
# BL-227 promotes it, the same findings move to 'violations' and a warnings-only
# reader would go silently empty on a stricter validator.
findings = [f for bucket in ('violations', 'warnings', 'info')
            for f in data.get(bucket, [])
            if f.get('rule') == 'body-language-not-english']
scanned = data.get('summary', {}).get('files_scanned', 0)
waived = data.get('summary', {}).get('waived', 0)

if not findings:
    print('normalize-language: no Spanish-dominant backlog bodies '
          '(%d scanned, %d waived)' % (scanned, waived))
    sys.exit(0)

print('normalize-language: %d backlog item(s) read Spanish-dominant (D-04)'
      % len(findings))
for f in findings:
    print('  ' + str(f.get('file')))
    print('    ' + str(f.get('message')))
print('')
print('Rewrite each body in English by hand or with assistance, then re-run.')
print('This script never rewrites prose.')
sys.exit(1)
"
