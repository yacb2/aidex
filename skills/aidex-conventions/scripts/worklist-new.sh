#!/usr/bin/env bash
# worklist-new.sh — create a .context/worklists/ run-queue from survey answers.
#
# Usage (non-interactive; the owning skill runs the AskUserQuestion survey and
# passes the answers here):
#   worklist-new.sh --title "<run name>" --ref "<kind:label>" [--ref ...] \
#                   [--publish ask|preauthorized|never] [--slug <kebab>] [--mode sweep]
#
#   --ref "<kind:label>"   queue item; kind ∈ backlog|plan|audit|inline. Repeatable;
#                          order on the command line == execution order.
#   --publish              gate-policy.publish (default: ask; `never` for a sweep)
#   --mode sweep           a backlog sweep: worklist-advance.sh then DRIVES the item
#                          lifecycle (close-item.sh --sweep the head, start-item.sh the
#                          next) instead of only ticking the box
#   --slug                 override auto slug (default: derived from title)
#
# Prints the created file path to stdout. See references/worklist-conventions.md.
set -euo pipefail

# Shared resolver — never `git rev-parse --show-toplevel`. That answered the wrong root
# twice over: inside a linked worktree it is the worktree (which vanishes on teardown),
# and in a multi-repo workspace it is the sub-repo, not the workspace `.context/`. Every
# backlog script the sweep chains this with resolves through _lib.sh, so a private
# resolver here would update the queue in one tree while the item closes in another.
# Pinned by test-find-project-root.sh (no private copies).
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
ROOT="$(find_project_root)"
WL_DIR="$ROOT/.context/worklists"

title="" publish="ask" slug="" mode=""
refs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   title="$2"; shift 2;;
    --ref)     refs+=("$2"); shift 2;;
    --publish) publish="$2"; shift 2;;
    --slug)    slug="$2"; shift 2;;
    --mode)    mode="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$title" ]] || { echo "--title required" >&2; exit 2; }
[[ "$publish" == "ask" || "$publish" == "preauthorized" || "$publish" == "never" ]] || { echo "--publish must be ask|preauthorized|never" >&2; exit 2; }
[[ -z "$mode" || "$mode" == "sweep" ]] || { echo "--mode must be sweep" >&2; exit 2; }
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
  [[ -n "$mode" ]] && echo "mode: $mode"
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
