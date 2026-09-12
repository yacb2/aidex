#!/usr/bin/env bash
# test-cross-skill-script-refs.sh — a script this skill tells the reader to run must be
# named WITH its owning skill when it ships elsewhere.
#
# BL-363's third instance: worklist-close.sh printed "run reconcile.sh for closure
# propagation" while reconcile.sh ships in backlog/scripts/. A reader looked in
# the wrong skill twice already; the earlier fix guarded the sweep policy DOCUMENT and
# said nothing about runtime output, which is the copy people actually act on.
#
# The check: every *.sh named inside a user-visible string (echo / printf / die) of a
# script in this skill must either live here, or appear as "<owner-skill>/…/<name>".
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS="$(cd "$HERE/../.." && pwd -P)"
SELF="conventions"
fail=0
err() { echo "FAIL: $1" >&2; fail=1; }

checked=0
for f in "$HERE"/../scripts/*.sh; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"
  while IFS= read -r line; do
    case "$line" in *echo*|*printf*|*die*) ;; *) continue ;; esac
    for name in $(printf '%s\n' "$line" | grep -oE '\b[a-z0-9_-]+\.sh\b' | sort -u); do
      [[ "$name" == "$base" ]] && continue
      [[ -e "$HERE/../scripts/$name" ]] && continue
      found="$(find "$SKILLS" -path "*/scripts/$name" -print -quit 2>/dev/null || true)"
      [[ -n "$found" ]] || continue
      checked=$((checked + 1))
      owner="$(basename "$(dirname "$(dirname "$found")")")"
      [[ "$owner" == "$SELF" ]] && continue
      case "$line" in
        *"$owner/"*) ;;
        *) err "$base tells the reader to run $name, which ships in $owner — name the skill, or the reader looks here for it" ;;
      esac
    done
  done < "$f"
done

# The gate must have seen non-empty input: a green run over zero cross-skill mentions
# is indistinguishable from a pass.
[ "$checked" -gt 0 ] || err "no cross-skill script reference was examined — the scan matched nothing"
[ "$fail" -eq 0 ] && echo "OK — cross-skill script refs: $checked mention(s) examined, each names its owning skill"
exit "$fail"
