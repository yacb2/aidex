#!/usr/bin/env bash
# The staged personal agents in docs/agents/ preload skills that exist.
#
# Code-writing agents get the testing core by `skills:` preload, not by a copy of it in
# their body (plan 2026-09-25-testing-canon-delivery, phase 4). A preloaded skill that is
# not installed is skipped SILENTLY by Claude Code — the agent starts without the core and
# nothing says so. So a renamed or misspelled entry would ship an agent that looks wired
# and is not. This test makes that loud:
#
#   1. every `skills:` entry in docs/agents/*.md names a skill shipped under skills/
#      (bare `name` or `aidex:name`; any other namespace is not ours to guarantee);
#   2. impl-opus, bugfix-opus and review-diff-opus preload `testing` — dropping it removes
#      the only channel that puts the core in that agent's context before its first test
#      write. (bugfix-opus does not preload `bugfix`: its body carries RED→GREEN, and the
#      skill's main-session steps would conflict with it.)
#
# The front-matter reader must not end a block list early: a comment or blank line
# between two items, or a flow list wrapped over several lines, would otherwise hide
# every entry after it from check 1. The self-check at the bottom runs this test on a
# fixture of exactly that shape and expects it to fail.
#
# Run with: bash tests/test-staged-agents-preload.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
AGENTS="${STAGED_AGENTS_DIR:-$ROOT/docs/agents}"
fail=0
err() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

# Print one skill entry per line from a file's front-matter `skills:` key, in either
# YAML form: a flow list `skills: [a, b]` (possibly wrapped over several lines) or a
# block list of `  - a` lines, where comment and blank lines do not end the list.
skills_of() {
  awk '
    function emit(v,   n, a, i) { gsub(/[][]/, "", v); n = split(v, a, ","); for (i = 1; i <= n; i++) print a[i] }
    NR==1 && $0!="---" { exit }
    NR>1 && $0=="---"  { exit }
    NR>1 {
      line = $0; sub(/[[:space:]]+#.*$/, "", line)
      if (inflow) { flow = flow " " line; if (line ~ /\]/) { emit(flow); inflow = 0 }; next }
      if (inlist) {
        if (line ~ /^[[:space:]]*(#.*)?$/) next
        if (line ~ /^[[:space:]]*-/) { sub(/^[[:space:]]*-[[:space:]]*/, "", line); print line; next }
        inlist = 0
      }
      if (line ~ /^skills:/) {
        v = line; sub(/^skills:[[:space:]]*/, "", v)
        if (v == "") inlist = 1
        else if (v ~ /^\[/ && v !~ /\]/) { inflow = 1; flow = v }
        else emit(v)
      }
    }' "$1" | sed -e 's/^[[:space:]"'\'']*//' -e 's/[[:space:]"'\'']*$//' | grep -v '^$'
}

files=()
for f in "$AGENTS"/*.md; do
  [ -e "$f" ] || continue
  [ "${f##*/}" = README.md ] && continue
  files+=("$f")
done
[ "${#files[@]}" -gt 0 ] || err "no staged agent definitions under ${AGENTS#$ROOT/}"

# ---------- 1. every preloaded skill is shipped ----------
for f in ${files[@]+"${files[@]}"}; do
  while IFS= read -r s; do
    case "$s" in
      aidex:*) name="${s#aidex:}" ;;
      *:*)     err "${f#$ROOT/} preloads \"$s\" — not an aidex skill, nothing here ships it"; continue ;;
      *)       name="$s" ;;
    esac
    [ -f "$ROOT/skills/$name/SKILL.md" ] \
      || err "${f#$ROOT/} preloads \"$s\" but skills/$name/SKILL.md does not exist (it would be skipped silently)"
  done < <(skills_of "$f")
done

# ---------- 2. the code-writing agents and the reviewer carry their preloads ----------
require() {  # $1 = agent file stem, rest = skill names it must preload
  local stem="$1"; shift
  local f="$AGENTS/$stem.md"
  [ -f "$f" ] || { err "missing staged agent ${f#$ROOT/}"; return; }
  local have; have="$(skills_of "$f" | sed 's/^aidex://')"
  for want in "$@"; do
    grep -qxF -- "$want" <<<"$have" || err "${f#$ROOT/} does not preload \"$want\""
  done
}
require impl-opus testing
require bugfix-opus testing
require review-diff-opus testing

# ---------- self-check: the reader sees entries a comment or a wrapped list would hide ----------
if [ -z "${STAGED_AGENTS_DIR:-}" ]; then
  fx="$(mktemp -d)"; trap 'rm -rf "$fx"' EXIT
  printf -- '---\nname: impl-opus\nskills:\n  - aidex:testing\n  # the next one is misspelled\n\n  - aidex:tesitng\n---\n' > "$fx/impl-opus.md"
  printf -- '---\nname: bugfix-opus\nskills: [aidex:testing,\n  aidex:bugfx]\n---\n' > "$fx/bugfix-opus.md"
  printf -- '---\nname: review-diff-opus\nskills: [aidex:testing]\n---\n' > "$fx/review-diff-opus.md"
  fx_out="$(STAGED_AGENTS_DIR="$fx" bash "${BASH_SOURCE[0]}" 2>&1)" \
    && err "self-check: a misspelled entry after a comment in a block list passed"
  grep -qF 'tesitng' <<<"$fx_out" || err "self-check: an entry after a comment line was not read: $fx_out"
  grep -qF 'bugfx' <<<"$fx_out"   || err "self-check: an entry on a wrapped flow-list line was not read: $fx_out"
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: ${#files[@]} staged agents preload only shipped skills; impl/bugfix/review-diff carry testing; the reader survives comments and wrapped lists"
  exit 0
fi
exit 1
