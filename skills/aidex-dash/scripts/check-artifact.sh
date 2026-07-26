#!/usr/bin/env bash
# check-artifact.sh — verify a local-first artifact honours the file contract
# the Artifact tool enforces for published pages. Run it before opening the
# file; it is the deterministic half of rules/artifacts-local-first.md.
#
# Usage: check-artifact.sh <file.html> [...]
# Exit 0 = every file passes. Exit 1 = at least one violation (each printed).
# Exit 2 = usage error.
#
# Checks (per file):
#   doctype      complete document, not a headless fragment (quirks mode)
#   charset      <meta charset> — file:// pages have no server to declare it
#   viewport     <meta name="viewport"> — otherwise unusable on a phone
#   title        <title> — names the browser tab
#   themes       prefers-color-scheme — readable in dark mode
#   self         no external stylesheet/script/font/image: one file, no network
#   siblings     no .css/.js dropped next to it — the artifact IS the file

set -uo pipefail

[[ $# -ge 1 ]] || { echo "ERROR: usage: check-artifact.sh <file.html> [...]" >&2; exit 2; }

failures=0
report() { printf '  FAIL [%s] %s: %s\n' "$1" "$2" "$3"; failures=$((failures + 1)); }

for f in "$@"; do
  if [[ ! -f "$f" ]]; then
    report missing "$f" "no such file"
    continue
  fi
  name="$(basename "$f")"
  body="$(cat "$f")"

  grep -qiE '<!doctype[[:space:]]+html' <<<"$body" \
    || report doctype "$name" "no <!doctype html> — headless fragment, browsers render it in quirks mode"
  grep -qiE '<meta[^>]+charset' <<<"$body" \
    || report charset "$name" "no <meta charset> — accented text can mis-decode from file://"
  grep -qiE '<meta[^>]+name=["'"'"']?viewport' <<<"$body" \
    || report viewport "$name" "no viewport meta — unreadable on a phone"
  grep -qiE '<title>' <<<"$body" \
    || report title "$name" "no <title> — the browser tab has no name"
  grep -q 'prefers-color-scheme' <<<"$body" \
    || report themes "$name" "no prefers-color-scheme — unreadable for a dark-mode reader"

  grep -qiE '<link[^>]+rel=["'"'"']?stylesheet' <<<"$body" \
    && report self "$name" "external stylesheet — the file must stand alone offline"
  grep -qiE '<script[^>]+src=' <<<"$body" \
    && report self "$name" "external script — the file must stand alone offline"
  grep -qiE '@import[[:space:]]+(url\()?["'"'"']?https?:' <<<"$body" \
    && report self "$name" "@import of a remote stylesheet"
  grep -qiE '<img[^>]+src=["'"'"']?https?:' <<<"$body" \
    && report self "$name" "remote image — breaks offline and leaks a request"
  # A @font-face block can span lines, so flatten before matching it. Only a
  # remote src counts: url(data:…) is inlined and honours the contract.
  tr -d '\n' <<<"$body" | grep -qiE '@font-face[^}]*url\([[:space:]]*["'"'"']?(https?:)?//' \
    && report self "$name" "remote @font-face src — the font never loads offline and leaks a request"

  dir="$(dirname "$f")"
  assets="$(find "$dir" -maxdepth 1 \( -name '*.css' -o -name '*.js' \) 2>/dev/null | head -3)"
  [[ -n "$assets" ]] \
    && report siblings "$name" "sibling assets next to it ($(basename "$(head -1 <<<"$assets")")…) — inline them"
done

if [[ $failures -eq 0 ]]; then
  printf 'artifact contract OK (%d file(s))\n' "$#"
  exit 0
fi
printf '%d contract violation(s)\n' "$failures"
exit 1
