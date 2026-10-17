#!/usr/bin/env bash
# test-builder-reads-fit.sh — the builder must never print a big reference through Bash.
# A Bash result over about 30000 characters is saved to a file and only its first lines are
# shown, so a `cat` of 03-spec-grammar.md (47 KB) or 04-block-vocabulary.md (39 KB) left the
# builder without the rules it was told to read (LOOP-014: 43 of 54 real runs, 10 of 10 bench
# builders). The Read tool shows those files whole.
#
# Layer: reference text — the failure is an agent file that tells the reader to use a tool
# whose output is cut.
#
# Run with: bash skills/artifact/tests/test-builder-reads-fit.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL="$HERE/.."
AGENT="$SKILL/../../agents/artifact-sonnet.md"
LIMIT=30000
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$AGENT" ]] || { echo "FAIL: $AGENT missing"; exit 1; }

# Lines that reach a shell reader: inside any ``` fence (backslash continuations joined) or
# in prose, any line pairing a reader command (cat, sed, head, tail, awk, less, more) with a .md name.
fenced="$(awk '/^```/ { if (infence) { infence=0 } else { infence=1 } next } infence' "$AGENT" | sed -e ':a' -e '/\\$/{N;s/\\\n//;ba' -e '}')"
prose="$(awk '/^```/ { infence = !infence; next } !infence' "$AGENT")"
candidates="$(printf '%s\n%s\n' "$fenced" "$prose" | grep -E '(^|[^A-Za-z])(cat|sed|head|tail|awk|less|more)[[:space:]].*\.md' | sed -E 's/\.spec\.md//g')"

# Any reference file named on such a line must fit: a named file that does not exist is a FAIL
# (a rename must not turn a violation into a quiet pass), a file at the limit or over is a FAIL.
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  path="$(find "$SKILL/references" -name "$name" -type f | head -1)"
  if [[ -z "$path" ]]; then
    fail "artifact-sonnet.md names $name on a shell line but no such reference exists"
    continue
  fi
  size="$(wc -c <"$path" | tr -d ' ')"
  [[ "$size" -ge "$LIMIT" ]] \
    && fail "artifact-sonnet.md prints $name through Bash ($size bytes >= $LIMIT): the result is saved to a file, not shown — use the Read tool"
done < <(grep -oE '[0-9A-Za-z_-]+[A-Za-z0-9_.-]*\.md' <<<"$candidates" | sort -u)

# Step 1 must still name both references (the test cannot pass by deleting the reads).
step1="$(awk '/^## Step 1/{on=1; print; next} on && /^## /{exit} on' "$AGENT")"
[[ -n "$step1" ]] || fail "artifact-sonnet.md has no '## Step 1' heading"
for f in 03-spec-grammar.md 04-block-vocabulary.md; do
  grep -qF -- "$f" <<<"$step1" || fail "Step 1 no longer names $f"
done

# The delegate's hand-back must carry the probe verdict, and the main session may skip its own
# probe only on a clean one (a probe that found defects still prints its SHOT lines).
reply="$(awk '/^## Reply with/{on=1; next} on && /^## /{exit} on' "$AGENT")"
grep -qF -- 'render-probe:' <<<"$reply" || fail "agent '## Reply with' no longer asks for the probe's last line (render-probe: ...)"
skipline="$(grep -F -- "hand-back carries" "$SKILL/SKILL.md")"
grep -qF -- 'render-probe: clean' <<<"$skipline" || fail "SKILL.md probe-skip sentence no longer requires 'render-probe: clean'"

[[ "$failures" -eq 0 ]] && echo "PASS: no reference of 30000 bytes or more is printed through Bash, and Step 1 names both" || { echo "FAILED: $failures"; exit 1; }
