#!/usr/bin/env bash
# worklist-new.sh — create a .context/worklists/ run-queue from survey answers.
#
# Usage (non-interactive; the owning skill runs the AskUserQuestion survey and
# passes the answers here):
#   worklist-new.sh --title "<run name>" --ref "<kind:label>" [--ref ...] \
#                   [--publish ask|preauthorized] [--slug <kebab>]
#
#   --ref "<kind:label>"   queue item; kind ∈ backlog|plan|audit|inline. Repeatable;
#                          order on the command line == execution order.
#   --publish              gate-policy.publish (default: ask)
#   --slug                 override auto slug (default: derived from title)
#
# Prints the created file path to stdout. See references/worklist-conventions.md.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
WL_DIR="$ROOT/.context/worklists"

title="" publish="ask" slug=""
refs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   title="$2"; shift 2;;
    --ref)     refs+=("$2"); shift 2;;
    --publish) publish="$2"; shift 2;;
    --slug)    slug="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$title" ]] || { echo "--title required" >&2; exit 2; }
[[ "$publish" == "ask" || "$publish" == "preauthorized" ]] || { echo "--publish must be ask|preauthorized" >&2; exit 2; }
[[ ${#refs[@]} -gt 0 ]] || { echo "at least one --ref required" >&2; exit 2; }

if [[ -z "$slug" ]]; then
  slug="$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' \
          | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)"
fi
today="$(date +%F)"
mkdir -p "$WL_DIR"
file="$WL_DIR/${today}-${slug}.md"

{
  echo "---"
  echo "title: \"$title\""
  echo "status: doing"
  echo "created: $today"
  echo "updated: $today"
  echo "gate-policy:"
  echo "  publish: $publish"
  echo "  destructive: deny"
  echo "---"
  echo
  echo "# $title"
  echo
  echo "## Queue (in execution order)"
  i=1
  for r in "${refs[@]}"; do
    kind="${r%%:*}"; label="${r#*:}"
    echo "$i. [ ] $label   <!-- ref: $kind -->"
    i=$((i+1))
  done
  echo
  echo "## Deferred / emergent (class b: appended mid-run, never re-asked)"
} > "$file"

echo "$file"
