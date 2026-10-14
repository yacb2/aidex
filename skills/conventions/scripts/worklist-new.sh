#!/usr/bin/env bash
# worklist-new.sh — create a .context/worklists/ run-queue from survey answers.
#
# Usage (non-interactive; the owning skill runs the AskUserQuestion survey and
# passes the answers here):
#   worklist-new.sh --title "<run name>" --ref "<kind:label>" [--ref ...] \
#                   [--publish ask|preauthorized|never] [--merge ask|preauthorized]
#                   [--slug <kebab>] [--mode sweep]
#
#   --ref "<kind:label>"   queue item; kind ∈ backlog|plan|audit|inline. Repeatable;
#                          order on the command line == execution order.
#   --publish              gate-policy.publish (default: ask; `never` for a sweep)
#   --merge                gate-policy.merge (default: ask). Integrating the branch is
#                          class 2 in skills/conventions/references/autonomy-conventions.md: pre-authorizable at the initial
#                          phase, never assumed mid-run. This is where that grant is
#                          recorded, so the run stops printing a fixed refusal over an
#                          answer the owner already gave (BL-361). An ABSENT key means
#                          `ask` — what every work-list written before BL-361 meant.
#   --mode sweep           a backlog sweep: worklist-advance.sh then DRIVES the item
#                          lifecycle (close-item.sh --sweep the head, start-item.sh the
#                          next) instead of only ticking the box
#   --slug                 override auto slug (default: derived from title)
#
# Prints the created file path to stdout. See references/worklist-conventions.md.
set -euo pipefail

# Shared resolver (find_project_root in _lib.sh) — never a private one or git rev-parse; see its header.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"
ROOT="$(find_project_root)"
WL_DIR="$ROOT/.context/worklists"

title="" publish="ask" merge="ask" slug="" mode=""
refs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)   title="$2"; shift 2;;
    --ref)     refs+=("$2"); shift 2;;
    --publish) publish="$2"; shift 2;;
    --merge) merge="$2"; shift 2;;
    --slug)    slug="$2"; shift 2;;
    --mode)    mode="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$title" ]] || { echo "--title required" >&2; exit 2; }
[[ "$publish" == "ask" || "$publish" == "preauthorized" || "$publish" == "never" ]] || { echo "--publish must be ask|preauthorized|never" >&2; exit 2; }
[[ "$merge" == "ask" || "$merge" == "preauthorized" ]] || { echo "--merge must be ask|preauthorized" >&2; exit 2; }
[[ -z "$mode" || "$mode" == "sweep" ]] || { echo "--mode must be sweep" >&2; exit 2; }
[[ ${#refs[@]} -gt 0 ]] || { echo "at least one --ref required" >&2; exit 2; }
[[ "$title" != *$'\n'* ]] || { echo "--title must be one line" >&2; exit 2; }
# The work-list readers strip the quotes and do not unescape, so \ and " cannot round-trip.
[[ "$title" != *[\"\\]* ]] || { echo "--title must not contain a double quote or backslash" >&2; exit 2; }
for r in "${refs[@]}"; do
  case "$r" in
    backlog:*|plan:*|audit:*|inline:*) ;;
    *) echo "--ref must be <kind:label> with kind backlog|plan|audit|inline: $r" >&2; exit 2;;
  esac
done

if [[ -z "$slug" ]]; then
  slug="$(slugify "$title" | cut -c1-40 | sed -E 's/-+$//')"
  [[ -n "$slug" ]] || { echo "--title has no ASCII letters or digits to derive a slug from; pass --slug" >&2; exit 2; }
fi
today="$(today_iso)"
mkdir -p "$WL_DIR"
# BL-370: a slug shaped like every other .context/ filename already carries its date.
if [[ "$slug" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}- ]]; then
  file="$WL_DIR/${slug}.md"
else
  file="$WL_DIR/${today}-${slug}.md"
fi
[[ ! -e "$file" ]] || { echo "work-list already exists, not overwriting: $file (resume or close the existing work-list, or pass a different --slug)" >&2; exit 2; }

{
  echo "---"
  echo "title: \"$title\""
  echo "status: doing"
  echo "created: $today"
  echo "updated: $today"
  [[ -n "$mode" ]] && echo "mode: $mode"
  echo "gate-policy:"
  echo "  publish: $publish"
  echo "  merge: $merge"
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
