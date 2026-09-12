#!/usr/bin/env bash
# Engine-enum lockstep guard (regression for the 2026-07-12 drift where the
# Workflow engine existed in the 01-loop-engines decision matrix but not in
# the front-matter enum of 02-loop-spec-conventions.md or the template).
#
# Invariants:
#   1. The enum in 02-loop-spec-conventions.md and the template's "One of:"
#      list declare the same engine set.
#   2. Every engine bolded in the decision-matrix table of 01-loop-engines.md
#      normalizes to a token in that enum, and vice versa.
#
# When adding an engine, update in lockstep: the decision matrix, the enum
# line in 02-loop-spec-conventions.md, the template's "One of:" comment, and
# SKILL.md step 4 (the last one is not machine-checked).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONV="$DIR/references/02-loop-spec-conventions.md"
MATRIX="$DIR/references/01-loop-engines.md"
TEMPLATE="$DIR/assets/templates/loop-spec.md.template"
fail=0
err() { echo "FAIL: $*" >&2; fail=1; }

tokens() { tr '|' '\n' | tr -d ' ' | grep -v '^$' | grep -v '^undecided$' | sort -u; }

enum=$(grep -m1 '^engine:' "$CONV" | sed 's/.*#//' | tokens)
[ -n "$enum" ] || { echo "FAIL: could not parse engine enum from $CONV" >&2; exit 1; }

tmpl=$(grep -m1 'One of:' "$TEMPLATE" | sed 's/.*One of: //; s/\..*//' | tokens)
[ -n "$tmpl" ] || { echo "FAIL: could not parse 'One of:' engine list from $TEMPLATE" >&2; exit 1; }

if [ "$enum" != "$tmpl" ]; then
  err "enum mismatch — conventions: [$(echo $enum)] vs template: [$(echo $tmpl)]"
fi

# Bold engine names inside the decision-matrix table -> normalized enum tokens.
matrix_raw=$(awk '/^## Engine decision matrix/{f=1;next} /^## /{f=0} f' "$MATRIX" \
  | grep '^|' | grep -oE '\*\*[^*]+\*\*' || true)
[ -n "$matrix_raw" ] || { echo "FAIL: no bolded engines found in decision matrix of $MATRIX" >&2; exit 1; }

norm() {
  local t
  t=$(echo "$1" | tr -d '\`*' | tr '[:upper:]' '[:lower:]')
  t="${t#/}"
  case "$t" in
    ralph-loop)             echo ralph ;;
    "claude -p in a while") echo claude-p ;;
    routines|schedule)      echo routine ;;
    *)                      echo "$t" ;;
  esac
}

matrix=$(while IFS= read -r b; do [ -n "$b" ] && norm "$b"; done <<< "$matrix_raw" | sort -u)

while IFS= read -r t; do
  [ -z "$t" ] && continue
  echo "$enum" | grep -qx "$t" \
    || err "engine '$t' is in the decision matrix but missing from the front-matter enum"
done <<< "$matrix"

while IFS= read -r t; do
  [ -z "$t" ] && continue
  echo "$matrix" | grep -qx "$t" \
    || err "engine '$t' is in the enum but not bolded in the decision matrix"
done <<< "$enum"

if [ "$fail" -eq 0 ]; then
  echo "OK: engine enum lockstep ($(echo $enum | tr '\n' ' '))"
fi
exit "$fail"
