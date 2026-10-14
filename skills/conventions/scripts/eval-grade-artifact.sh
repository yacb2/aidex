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
#   --glob     path pattern under root, e.g. 'communications/meetings/*/body.md';
#              `*` and `**` each match exactly one path segment (never across a `/`)
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
    -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
    *) echo "usage error: unknown arg '$1'" >&2; exit 3 ;;
  esac
done

[ -n "$ROOT" ] && [ -n "$GLOB" ] && [ -n "$PATTERN" ] \
  || { echo "usage error: --root, --glob and --pattern are all required" >&2; exit 3; }
[ -d "$ROOT" ] || { echo "usage error: --root is not a directory: $ROOT" >&2; exit 3; }
# a trailing slash would make `find -path` look for a double slash and report UNRESOLVED
while [ "$ROOT" != / ] && [ "${ROOT%/}" != "$ROOT" ]; do ROOT="${ROOT%/}"; done
[ -n "$ROOT" ] || ROOT=/

# Resolve. `find -path` rather than shell globbing: bash 3.2 (the macOS default)
# has no globstar, and a nullglob-based expansion silently yields the literal
# pattern when nothing matches — which grades a file named '*' as absent instead
# of reporting that nothing resolved.
# `find -path` lets `*` cross `/`, so keep only matches with as many segments as the glob:
# a deeper misfiled artifact must not satisfy `*/body.md`.
matches=()
want_depth="${GLOB//[!\/]/}"
while IFS= read -r f; do
  rel="${f#"$ROOT"/}"
  [ -n "$f" ] && [ "${rel//[!\/]/}" = "$want_depth" ] && matches+=("$f")
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
  target=$(ls -t "${matches[@]}" | sed -n 1p)
else
  target="${matches[0]}"
fi

# grep exits 1 for "no match" and 2 for an invalid regex OR an I/O error: tell them apart
# by checking the regex alone first.
g=0; grep -Eq -- "$PATTERN" </dev/null || g=$?
[ "$g" -ne 2 ] || { echo "usage error: --pattern is not a valid extended regex: $PATTERN" >&2; exit 3; }
g=0; gerr="$(grep -Eq -- "$PATTERN" "$target" 2>&1)" || g=$?
if [ "$g" -eq 0 ]; then
  echo "PASS  $target"
  exit 0
fi
[ "$g" -eq 1 ] || { echo "grep failed on $target: $gerr" >&2; exit 3; }

echo "FAIL  $target does not match /$PATTERN/"
exit 1
