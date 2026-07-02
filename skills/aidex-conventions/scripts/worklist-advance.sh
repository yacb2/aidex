#!/usr/bin/env bash
# worklist-advance.sh — mark the current head item done, print the next.
#
# This is what execution calls between items instead of asking "what next?".
#
# Usage:
#   worklist-advance.sh <slug-or-path>                 # complete head, print next
#   worklist-advance.sh <slug-or-path> --append "<kind:label>"   # add class-(b) emergent
#   worklist-advance.sh <slug-or-path> --peek          # print next without completing
#
# Prints the next unchecked queue item, or "DONE" when the queue is drained.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WL_DIR="$ROOT/.context/worklists"

arg="${1:-}"; shift || true
[[ -n "$arg" ]] || { echo "usage: worklist-advance.sh <slug-or-path> [--append <kind:label>] [--peek]" >&2; exit 2; }

append="" peek=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --append) append="$2"; shift 2;;
    --peek)   peek=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

# `|| true`: ls exits 2 on no match, which pipefail+errexit would turn into a
# silent exit 1 before the not-found diagnostic below ever runs.
if [[ -f "$arg" ]]; then file="$arg"; else file="$(ls "$WL_DIR/"*"$arg"*.md 2>/dev/null | head -1 || true)"; fi
[[ -n "${file:-}" && -f "$file" ]] || { echo "worklist not found: $arg" >&2; exit 2; }
today="$(date +%F)"

# append a class-(b) emergent item (no prompt, no re-ask). Appending is purely
# additive — it does NOT complete the current head (distinct semantics).
if [[ -n "$append" ]]; then
  kind="${append%%:*}"; label="${append#*:}"
  printf -- '- [ ] %s   <!-- ref: %s -->\n' "$label" "$kind" >> "$file"
  sed -i.bak -E "s/^updated: .*/updated: $today/" "$file" && rm -f "$file.bak"
fi

# complete the first unchecked numbered queue item — only on a plain advance
# (not on --peek, not on --append). `|| true`: grep exits 1 when none remain.
if [[ "$peek" -eq 0 && -z "$append" ]]; then
  head_line="$(grep -nE '^[0-9]+\. \[ \] ' "$file" | head -1 | cut -d: -f1 || true)"
  if [[ -n "$head_line" ]]; then
    sed -i.bak "${head_line}s/\[ \]/[x]/" "$file" && rm -f "$file.bak"
    sed -i.bak -E "s/^updated: .*/updated: $today/" "$file" && rm -f "$file.bak"
  fi
fi

# print the next still-unchecked numbered queue item, or DONE
next="$(grep -E '^[0-9]+\. \[ \] ' "$file" | head -1 || true)"
if [[ -n "$next" ]]; then echo "$next"; else echo "DONE"; fi
