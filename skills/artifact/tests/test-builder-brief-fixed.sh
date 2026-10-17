#!/usr/bin/env bash
# test-builder-brief-fixed.sh — the builder brief is a fixed short form, and the main session
# takes a delegate's probe from its manifest, not from pasted SHOT lines.
#
# LOOP-014 iteration 2: the main session spent 20-47 s writing a long builder brief (it loaded
# the delegation guide on 4 of 5 pages) although the agent file already names what to read, how
# to build and probe and what to return. The skill now gives the brief as a fixed form (Q11).
# Same iteration: builder hand-backs carried the run stamp on 2 of 5 pages and the SHOT lines on
# 4 of 5, and the skip-the-probe rule misfired both ways (D14). The manifest carries `run` and
# `written` and is written last, so it is the authority.
#
# Layer: reference text — the failure is a skill or agent file that asks for a long brief, or a
# skip rule that hangs on lines a low-effort agent drops. The time it saves is measured by the
# LOOP-014 bench, not here.
#
# Run with: bash skills/artifact/tests/test-builder-brief-fixed.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_MD="$HERE/../SKILL.md"
AGENT="$HERE/../../../agents/artifact-sonnet.md"
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

[[ -f "$SKILL_MD" ]] || { echo "FAIL: $SKILL_MD missing"; exit 1; }
[[ -f "$AGENT" ]] || { echo "FAIL: $AGENT missing"; exit 1; }

# 1. SKILL.md carries the fixed brief: its own section, one fenced form with every field.
section="$(awk '/^## The builder brief/ { on=1; next } on && /^## / { exit } on' "$SKILL_MD")"
[[ -n "$section" ]] || fail "SKILL.md has no '## The builder brief' section"
form="$(printf '%s\n' "$section" | awk '/^```/ { n++; next } n == 1')"
[[ -n "$form" ]] || fail "the builder brief section has no fenced form"
for field in 'Files to read first:' 'Request:' 'Skill directory:' 'Output:' 'Language:' 'Shots:'; do
  printf '%s\n' "$form" | grep -qF -- "$field" || fail "the fixed brief form lacks '$field'"
done
printf '%s\n' "$form" | grep -qi 'deliberately left alone' || fail "the fixed brief form does not ask for what was left alone"

# 2. The agent's handoff line names the fixed brief, not the long shape.
desc="$(grep -m1 '^description:' "$AGENT")"
printf '%s\n' "$desc" | grep -q 'fixed brief' || fail "agent description does not name the fixed brief"
printf '%s\n' "$desc" | grep -q 'pinned figures, consult items' && fail "agent description still prescribes the long brief shape"

# 3. D14: step 1 of the quality loop takes a delegate's probe from the manifest.
step1="$(awk '/^### The quality loop/ { on=1 } on && /^2\. / { exit } on' "$SKILL_MD")"
printf '%s\n' "$step1" | grep -q 'newer than' || fail "quality-loop step 1 does not compare the manifest with the page's build"
printf '%s\n' "$step1" | grep -q '`written`' || fail "quality-loop step 1 does not take the manifest's written list"
printf '%s\n' "$step1" | grep -q 'carries the manifest path, the `SHOT` lines' && fail "quality-loop step 1 still makes the skip hang on pasted SHOT lines"

if (( failures )); then
  printf '%d failure(s)\n' "$failures"; exit 1
fi
echo "PASS: the builder brief is a fixed form and a delegate's probe is read from its manifest"
