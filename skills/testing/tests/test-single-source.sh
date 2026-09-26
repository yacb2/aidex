#!/usr/bin/env bash
# Single-source guard for the write-time testing core.
#
# The four authoring questions and the "one contract, one owner test" rule are owned
# by skills/testing/SKILL.md. Before 2026-09-25 they were stated in coverage/SKILL.md,
# restated in bugfix step 2 and again in coverage's judgment pass; three copies of one
# rule drift apart, and the reader cannot tell which is current. Every other shipped
# file links to `testing` instead of restating it.
#
# The anchors below are phrases of the core as testing states it. Each anchor must be
# FOUND in testing/SKILL.md — so a rewording there fails this test instead of silently
# turning the outside grep into a no-op — and found NOWHERE else in the shipped tree.
# Matching is case-insensitive over a whitespace-flattened copy, so a re-wrap cannot
# hide a copy.
#
# Second check: coverage's description no longer claims the write-a-test prompts.
# Writing a test is `testing`'s; two descriptions claiming one prompt split the fires.
#
# Run with: bash skills/testing/tests/test-single-source.sh

set -uo pipefail

TESTING="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT="$(cd "$TESTING/../.." && pwd -P)"
OWNER="$TESTING/SKILL.md"
COVERAGE="$ROOT/skills/coverage/SKILL.md"

fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

anchors=(
  "what observable behaviour or contract does it protect"
  "what credible regression turns it red"
  "why does no existing test already catch"
  "no production caller needs"
  "one contract has one owner test"
  "at the layer that owns the failure"
)
trigger_phrases=(
  "write a test for"
  "add a regression test"
)

flatten() { tr '\n' ' ' < "$1" | tr -s ' \t' ' '; }

# ---------- the owner states every anchor ----------
if [ -f "$OWNER" ]; then
  owner_text="$(flatten "$OWNER")"
  for a in "${anchors[@]}"; do
    grep -qiF -- "$a" <<<"$owner_text" || err "owner $OWNER does not state: \"$a\" (reworded? update the anchor)"
  done
else
  err "missing owner: $OWNER"
fi

# ---------- no other shipped file states one ----------
shipped=()
while IFS= read -r f; do shipped+=("$f"); done < <(
  find "$ROOT/skills" "$ROOT/hooks" "$ROOT/docs" "$ROOT/README.md" -type f \
    \( -name '*.md' -o -name '*.sh' -o -name '*.py' -o -name '*.json' -o -name '*.yaml' -o -name '*.template' \) \
    -not -path "$TESTING/*" -not -path "$ROOT/docs/retired/*" 2>/dev/null | sort
)
[ "${#shipped[@]}" -gt 0 ] || err "found no shipped files under $ROOT"

for f in "${shipped[@]}"; do
  text="$(flatten "$f")"
  for a in "${anchors[@]}"; do
    grep -qiF -- "$a" <<<"$text" && err "${f#$ROOT/} restates the testing core (\"$a\") — link to skills/testing/SKILL.md instead"
  done
done

# ---------- coverage's description does not claim the write-a-test prompts ----------
desc="$(awk '/^---[[:space:]]*$/{fm++; next} fm==1' "$COVERAGE" | tr '\n' ' ')"
[ -n "$desc" ] || err "could not read the front-matter of $COVERAGE"
for p in "${trigger_phrases[@]}"; do
  grep -qiF -- "$p" <<<"$desc" && err "coverage description still claims \"$p\" — that prompt is testing's"
done

if [ "$fail" -eq 0 ]; then
  echo "OK — testing core stated once (${#anchors[@]} anchors, ${#shipped[@]} shipped files scanned); coverage claims no write-a-test prompt"
  exit 0
fi
exit 1
