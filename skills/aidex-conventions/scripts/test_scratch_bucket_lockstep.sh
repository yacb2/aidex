#!/usr/bin/env bash
# Scratch-bucket lockstep guard: skills/ directives vs the `_tmp/` canon.
#
# Regression this locks (BL-084, 2026-07-24):
#   claudemd-conventions.md's "One bucket, one name" rule read as an absolute — no second
#   scratch location, ever — while aidex-workflow instructed the agent to generate the
#   disposable `.workflow.js` into the session scratchpad. Both sides are aidex-owned, so
#   an agent following the suite hit a flat contradiction with no stated winner.
#
# The invariant is two-sided, and neither side alone is checkable:
#   (1) if any skill directs output to a session scratchpad, the canon must ADMIT that
#       bucket — otherwise the suite contradicts itself;
#   (2) if the canon carries the exemption, some skill must USE it — otherwise it is a
#       dead licence that widens the rule for nothing.
#
# Run with: bash skills/aidex-conventions/scripts/test_scratch_bucket_lockstep.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd -P)"
CANON="$SCRIPT_DIR/../references/claudemd-conventions.md"

failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$CANON" ]] || { echo "FAIL: canon not found at $CANON"; exit 1; }

# The "Scratch Output" section body — the rule under test, not the whole file.
SECTION="$(awk '/^## Scratch Output/{f=1;next} /^## /{f=0} f' "$CANON")"
[[ -n "$SECTION" ]] || { echo "FAIL: could not extract the Scratch Output section from $CANON"; exit 1; }

# Does the canon admit a harness-supplied session scratchpad as a legal destination?
canon_admits=0
grep -qiE 'session scratchpad' <<<"$SECTION" && canon_admits=1

# Which skills instruct writing into one?
users="$(grep -rliE 'session scratchpad' "$REPO_ROOT/skills" --include='*.md' 2>/dev/null \
  | grep -v '/references/claudemd-conventions\.md$' | sort)"

# ---------- (1) a directive with no licence is a self-contradiction ----------
if [[ -n "$users" && "$canon_admits" -eq 0 ]]; then
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    fail "(1) ${f#"$REPO_ROOT/"} directs output to a session scratchpad, but the Scratch Output canon admits no bucket other than _tmp/"
  done <<<"$users"
fi

# ---------- (2) a licence nobody uses is dead canon ----------
if [[ -z "$users" && "$canon_admits" -eq 1 ]]; then
  fail "(2) the Scratch Output canon carves out the session scratchpad, but no skill directs anything there — drop the exemption rather than widening the rule for nothing"
fi

# ---------- (3) the carve-out must stay bounded, not blanket ----------
# It is a licence for files whose lifetime the HARNESS owns. Without that boundary the
# exemption swallows the one-bucket rule it is an exception to.
if [[ "$canon_admits" -eq 1 ]]; then
  grep -qiE 'session-scoped|harness' <<<"$SECTION" \
    || fail "(3) the session-scratchpad carve-out states no boundary (harness-owned / session-scoped) — as written it licenses any second bucket"
  grep -qE '_tmp/' <<<"$SECTION" \
    || fail "(3) the Scratch Output section no longer names _tmp/ as the default destination"
fi

if [[ "$failures" -eq 0 ]]; then
  n="$(grep -c . <<<"$users" 2>/dev/null || echo 0)"
  echo "OK — scratch buckets in lockstep: canon admits session scratchpad=$canon_admits, skills using it=$n"
  exit 0
fi
exit 1
