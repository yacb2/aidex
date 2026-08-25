#!/usr/bin/env bash
# close-dated-artifact.sh — close + archive a requests/ or decisions/ artifact.
#
# Fills the lifecycle asymmetry: plans have close-plan.sh, backlog has
# close-item.sh, audits have close-audit.sh — requests and decisions had to be
# closed and archived by hand (D-05/D-10 mandate archive-on-close for both).
#
# Usage:
#   close-dated-artifact.sh requests  <slug-or-filename> [--status done|dropped]
#   close-dated-artifact.sh decisions <slug-or-filename> --status superseded --superseded-by <type/ref>
#   close-dated-artifact.sh decisions <slug-or-filename> --status dropped
#
#   requests default --status: done. decisions REQUIRE an explicit terminal
#   status (superseded needs --superseded-by; dropped does not).
#   Stamps `updated`, sets `status` (+ `superseded_by`), moves the file to
#   <type>/_archive/, prints "CLOSED <new-path>".

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_lib.sh"

TYPE="${1:-}"; shift || true
ARG="${1:-}"; shift || true
[[ "$TYPE" == "requests" || "$TYPE" == "decisions" ]] || die "first arg must be requests|decisions"
[[ -n "$ARG" ]] || die "usage: close-dated-artifact.sh <requests|decisions> <slug> [--status ...] [--superseded-by <type/ref>]"

STATUS="" SUPERSEDED_BY=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --status) STATUS="$2"; shift 2 ;;
    --superseded-by) SUPERSEDED_BY="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ "$TYPE" == "requests" ]]; then
  STATUS="${STATUS:-done}"
  [[ "$STATUS" == "done" || "$STATUS" == "dropped" ]] || die "requests terminal status must be done|dropped"
else
  [[ -n "$STATUS" ]] || die "decisions require an explicit --status superseded|dropped"
  [[ "$STATUS" == "superseded" || "$STATUS" == "dropped" ]] || die "decisions terminal status must be superseded|dropped"
  if [[ "$STATUS" == "superseded" && -z "$SUPERSEDED_BY" ]]; then
    die "--status superseded requires --superseded-by <type/ref>"
  fi
fi

ROOT="$(find_project_root)"
DIR="$ROOT/.context/$TYPE"
[[ -d "$DIR" ]] || die "no $TYPE/ directory at $DIR"

if [[ -f "$ARG" ]]; then file="$ARG"; else file="$(ls "$DIR/"*"$ARG"*.md 2>/dev/null | head -1 || true)"; fi
[[ -n "${file:-}" && -f "$file" ]] || die "$TYPE artifact not found: $ARG"
case "$file" in */_archive/*) die "already archived: $file" ;; esac

today="$(today_iso)"
sed -i.bak -E "s|^status: .*|status: $STATUS|" "$file" && rm -f "$file.bak"
sed -i.bak -E "s|^updated: .*|updated: $today|" "$file" && rm -f "$file.bak"
if [[ -n "$SUPERSEDED_BY" ]]; then
  if grep -q "^superseded_by:" "$file"; then
    sed -i.bak -E "s|^superseded_by: .*|superseded_by: $SUPERSEDED_BY|" "$file" && rm -f "$file.bak"
  else
    # insert before the closing front-matter delimiter (second ---)
    awk -v val="$SUPERSEDED_BY" '
      /^---[[:space:]]*$/ { c++; if (c == 2) print "superseded_by: " val }
      { print }
    ' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  fi
fi

mkdir -p "$DIR/_archive"
dest="$DIR/_archive/$(basename "$file")"
[[ -e "$dest" ]] && die "archive collision: $dest already exists"
mv "$file" "$dest"
ok "closed $TYPE/$(basename "$file") -> _archive/ (status: $STATUS)"
# `requests`/`decisions` -> the singular cross-ref prefix the anchor is written with.
archive_companions "$ROOT/.context" "${TYPE%s}/$(basename "$file")" "$DIR/_archive"
echo "CLOSED $dest"
