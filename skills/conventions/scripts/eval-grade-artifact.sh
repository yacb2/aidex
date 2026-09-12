#!/usr/bin/env bash
# eval-grade-artifact.sh — grade the artifact a skill actually produced.
#
# The trigger evals answer "did the skill fire?" — a marker file appears or it
# does not. This answers the other half: "did it produce the RIGHT thing?" The
# predicate reads the artifact's content, and the artifact is reached through a
# glob because its slug is chosen by the model, not by the config.
#
# Usage:
#   eval-grade-artifact.sh --root <dir> --glob <pattern> --pattern <regex> [--newest]
#
#   --root     directory the glob is relative to
#   --glob     path pattern under root, e.g. 'communications/meetings/*/body.md'
#   --pattern  extended regex the matched file must contain
#   --newest   when several files match, grade the most recently modified one.
#              Without it, an ambiguous match is an error, never a silent pass.
#
# Exit: 0 pass · 1 predicate failed · 2 unresolvable artifact · 3 usage error
set -euo pipefail

ROOT="" GLOB="" PATTERN="" NEWEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --root)    ROOT="${2:-}"; shift 2 ;;
    --glob)    GLOB="${2:-}"; shift 2 ;;
    --pattern) PATTERN="${2:-}"; shift 2 ;;
    --newest)  NEWEST=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "usage error: unknown arg '$1'" >&2; exit 3 ;;
  esac
done

[ -n "$ROOT" ] && [ -n "$GLOB" ] && [ -n "$PATTERN" ] \
  || { echo "usage error: --root, --glob and --pattern are all required" >&2; exit 3; }
[ -d "$ROOT" ] || { echo "usage error: --root is not a directory: $ROOT" >&2; exit 3; }

# Resolve. `find -path` rather than shell globbing: bash 3.2 (the macOS default)
# has no globstar, and a nullglob-based expansion silently yields the literal
# pattern when nothing matches — which grades a file named '*' as absent instead
# of reporting that nothing resolved.
matches=()
while IFS= read -r f; do
  [ -n "$f" ] && matches+=("$f")
done < <(find "$ROOT" -type f -path "$ROOT/$GLOB" 2>/dev/null | LC_ALL=C sort)

if [ "${#matches[@]}" -eq 0 ]; then
  echo "UNRESOLVED  no file under $ROOT matches $GLOB"
  exit 2
fi

if [ "${#matches[@]}" -gt 1 ]; then
  if [ "$NEWEST" -eq 0 ]; then
    echo "UNRESOLVED  ${#matches[@]} files match $GLOB — pass --newest to grade the latest:"
    printf '              %s\n' "${matches[@]}"
    exit 2
  fi
  target=$(ls -t "${matches[@]}" | head -1)
else
  target="${matches[0]}"
fi

if grep -Eq -- "$PATTERN" "$target"; then
  echo "PASS  $target"
  exit 0
fi

echo "FAIL  $target does not match /$PATTERN/"
exit 1
