#!/usr/bin/env bash
# harvest-commit.sh — record a commit SHA into the tracking artifact(s) it
# resolved, by parsing trailers in the commit message (D-09 auto-harvest half of
# the hybrid). Designed to run from a repo-local post-commit hook.
#
# Trailers recognised (case-insensitive, one id/slug or comma/space list):
#   Backlog: BL-007            -> append sha to that backlog item's `commits:`
#   Plan: 2026-05-22-foo#3     -> append sha to that plan's `commits:` (#phase optional)
#
# Provenance rule (D-09): a commit lands where the work happened. A Backlog trailer
# is for items fixed directly; a Plan trailer for escalated work.
#
# Usage:
#   harvest-commit.sh [--sha <sha>] [--message "<msg>"]
# Defaults: sha = `git rev-parse --short HEAD`, message = HEAD's full message.
# Silent no-op when no recognised trailer is present (safe as a post-commit hook).

set -euo pipefail

find_project_root() {
  local dir; dir="$(pwd -P)"
  while [[ "$dir" != "/" ]]; do
    [[ -d "$dir/.context" ]] && { printf '%s\n' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  pwd -P
}

SHA="" MSG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --sha)     SHA="$2"; shift 2 ;;
    --message) MSG="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) shift ;;
  esac
done

[[ -n "$SHA" ]] || SHA="$(git rev-parse --short HEAD 2>/dev/null || true)"
[[ -n "$SHA" ]] || { echo "harvest: no sha (not a git repo?)" >&2; exit 0; }
[[ -n "$MSG" ]] || MSG="$(git log -1 --format=%B 2>/dev/null || true)"

ROOT="$(find_project_root)"
BACKLOG_DIR="$ROOT/.context/backlog"
PLANS_DIR="$ROOT/.context/plans"

# append a sha to the `commits:` field of a front-matter file (idempotent per sha)
append_commit() {
  local file="$1" sha="$2"
  grep -q "$sha" "$file" 2>/dev/null && return 0   # already recorded
  awk -v sha="$sha" '
    BEGIN { d=0; infm=0; seen=0 }
    /^---[[:space:]]*$/ {
      d++
      if (d==1){infm=1; print; next}
      if (d==2){ if(!seen) print "commits: \"" sha "\""; infm=0; print; next }
    }
    infm==1 && $0 ~ /^commits:/ {
      val=$0; sub(/^commits:[[:space:]]*/,"",val); gsub(/"/,"",val)
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",val)
      if (val=="" || val=="[]") print "commits: \"" sha "\""
      else                      print "commits: \"" val " " sha "\""
      seen=1; next
    }
    { print }
  ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

# locate a backlog item file (active, _archive, or _deferred) by id
backlog_file_by_id() {
  local id="$1" f
  for f in "$BACKLOG_DIR"/*.md "$BACKLOG_DIR"/_archive/*.md "$BACKLOG_DIR"/_deferred/*.md; do
    [[ -f "$f" ]] || continue
    [[ "$(awk '/^---[[:space:]]*$/{c++; if(c==2)exit} c==1 && $1=="id:"{print $2; exit}' "$f")" == "$id" ]] && { printf '%s\n' "$f"; return 0; }
  done
  return 1
}

# locate a plan front-matter file by slug (modular dir or single file, active or _archive)
plan_fm_by_slug() {
  local slug="$1"
  for base in "$PLANS_DIR" "$PLANS_DIR/_archive"; do
    [[ -d "$base/$slug" && -f "$base/$slug/00-index.md" ]] && { printf '%s\n' "$base/$slug/00-index.md"; return 0; }
    [[ -f "$base/$slug.md" ]] && { printf '%s\n' "$base/$slug.md"; return 0; }
    [[ -f "$base/$slug" ]] && { printf '%s\n' "$base/$slug"; return 0; }
  done
  return 1
}

harvested=0

# --- Backlog: <ids> ---
while IFS= read -r line; do
  ids="$(printf '%s' "$line" | sed -E 's/^[Bb]acklog:[[:space:]]*//; s/[,]+/ /g')"
  for id in $ids; do
    id="$(printf '%s' "$id" | tr '[:lower:]' '[:upper:]')"
    [[ "$id" =~ ^BL-[0-9]+$ ]] || continue
    if f="$(backlog_file_by_id "$id")"; then
      append_commit "$f" "$SHA"; echo "harvest: $SHA -> backlog $id ($(basename "$f"))" >&2; harvested=$((harvested+1))
    else echo "harvest: backlog $id not found (skipped)" >&2; fi
  done
done < <(printf '%s\n' "$MSG" | grep -iE '^backlog:' || true)

# --- Plan: <slug>[#phase] ---
while IFS= read -r line; do
  spec="$(printf '%s' "$line" | sed -E 's/^[Pp]lan:[[:space:]]*//')"
  slug="${spec%%#*}"
  slug="$(printf '%s' "$slug" | sed -E 's/[[:space:]]+$//')"
  [[ -n "$slug" ]] || continue
  if f="$(plan_fm_by_slug "$slug")"; then
    append_commit "$f" "$SHA"; echo "harvest: $SHA -> plan $slug ($(basename "$(dirname "$f")")/)" >&2; harvested=$((harvested+1))
  else echo "harvest: plan $slug not found (skipped)" >&2; fi
done < <(printf '%s\n' "$MSG" | grep -iE '^plan:' || true)

exit 0
