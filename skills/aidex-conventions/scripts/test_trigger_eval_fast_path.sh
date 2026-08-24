#!/usr/bin/env bash
# test_trigger_eval_fast_path.sh — BL-221 lockstep over the trigger-eval methodology.
#
# WHY THIS EXISTS. Promoting the fast `claude -p` stream-json detector to the
# documented default is only safe while its caveats travel with it, and a caveat
# is exactly what gets trimmed when a section is rewritten for brevity. Three
# things must survive every future edit of that file:
#
#   1. BOTH instruments are named, with the question each one answers. The
#      detector over-reports recall (systematic, skill-dependent, 7%-25%), so a
#      document that promotes it without keeping eval-pty.sh as ground truth
#      turns a fast iteration tool into a source of wrong reported numbers.
#   2. The `~/.claude/**` sensitive-path constraint. A file-marker predicate
#      there scores 0 by predicate DENIAL, not trigger-blindness — the single
#      most misreadable result this instrument can produce.
#   3. §8's safe-parallelism mitigations. Being 17x cheaper is not a licence to
#      fan out; the contamination modes are properties of concurrent sessions,
#      not of the harness, and they cost a 10.5 h run once.
#
# Run with: bash skills/aidex-conventions/scripts/test_trigger_eval_fast_path.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DOC="$SCRIPT_DIR/../references/skill-trigger-eval-methodology.md"
failures=0
need() {  # need "<label>" "<grep -E pattern>"
  if grep -qiE "$2" "$DOC"; then printf '  ok: %s\n' "$1"
  else printf '  FAIL: %s\n' "$1"; failures=$((failures + 1)); fi
}

[[ -f "$DOC" ]] || { printf 'FAIL: methodology not found at %s\n' "$DOC"; exit 1; }

echo "== the fast path is documented =="
need "the stream-json detector has its own section" '^### 3a\.'
need "it names the invocation"                      'output-format stream-json'
need "it names --max-turns 1"                       'max-turns 1'
need "the speed figure is cited"                    '17x'

echo "== both instruments, and which question each answers =="
need "eval-pty.sh is kept as ground truth"          'ground truth'
need "the over-reporting bias is stated"            'over-report'
need "the bias is called systematic"                'systematic'
need "the measured range is given"                  '25%'
need "A/B iteration is routed to the detector"      'variant B better than variant A'

echo "== the constraints survive the promotion =="
need "the sensitive-path guard is stated"           'sensitive-path guard'
need "and named as predicate DENIAL, not blindness" 'predicate.{0,3} denial'
need "frozen snapshot required before a panel"      'frozen snapshot'
need "singleton lock required"                      'singleton lock'
need "UUID watchdog required"                       'uuid watchdog'
need "s8 still applies to the fast path"            '§8 applies unchanged'

echo "== the evidence is locatable =="
need "the LOOP-004 snapshot is cited by path"       '2026-06-17-eval-speedup-182AC4AC'

if (( failures )); then
  printf '\nFAIL — %d requirement(s) missing from the methodology\n' "$failures"
  exit 1
fi
printf '\nOK — trigger-eval fast path documented with its caveats intact\n'
