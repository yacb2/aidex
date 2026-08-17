#!/usr/bin/env bash
# check-artifact.sh — verify a local-first artifact honours the file contract
# the Artifact tool enforces for published pages. Run it before opening the
# file; it is the deterministic half of rules/artifacts-local-first.md.
#
# Usage: check-artifact.sh <file.html> [...]
#        check-artifact.sh <new.html> --prev <previous.html>
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
#   consult      a page the reader must ANSWER carries the §8 shape (only fires
#                when the page has a <textarea>)
#   consult-ids  with --prev: an id kept between two regenerations still names
#                the same claim

set -uo pipefail

PREV=""
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prev) PREV="${2:-}"; shift 2 || { echo "ERROR: --prev needs a file" >&2; exit 2; } ;;
    *)      FILES+=("$1"); shift ;;
  esac
done

[[ ${#FILES[@]} -ge 1 ]] || { echo "ERROR: usage: check-artifact.sh <file.html> [...] [--prev <old.html>]" >&2; exit 2; }
# --prev compares ONE page against its own previous version; with several files
# there is no way to say which prior belongs to which, and guessing would report
# a renumbering that never happened.
if [[ -n "$PREV" && ${#FILES[@]} -ne 1 ]]; then
  echo "ERROR: --prev takes exactly one file to compare against" >&2; exit 2
fi
set -- "${FILES[@]}"

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

  # --- § 8: the page is a CONSULTATION, not a read ---------------------------
  # Detection is the <textarea>, not the template's own class name: a page that
  # never copied the template is precisely the case that has no `.consult-item`
  # to key on, and that is the violation observed in the field (BL-168 — a
  # hand-rolled consultation page with 9 reply boxes, 0 stable ids and no
  # doctype). A report meant to be read has no inputs, so this stays silent for
  # an ordinary route B page.
  if grep -qi '<textarea' <<<"$body"; then
    n_area="$(grep -oiE '<textarea' <<<"$body" | wc -l | tr -d ' ')"
    n_id="$(grep -oiE 'data-id=' <<<"$body" | wc -l | tr -d ' ')"
    n_title="$(grep -oiE 'data-title=' <<<"$body" | wc -l | tr -d ' ')"

    # Requirement 1 — every claim is an item with a stable id. Without data-id
    # there is nothing to keep stable and nothing --prev can compare.
    [[ "$n_id" -ne "$n_area" ]] \
      && report consult "$name" "$n_area reply box(es) but $n_id data-id — every consultation item needs a stable id (copy assets/templates/consultation-block.html.template)"
    # data-title is what the composed reply is headed with; without it the paste
    # says '### c3' and the reader must return to the page to learn what c3 was.
    [[ "$n_title" -ne "$n_area" ]] \
      && report consult "$name" "$n_area reply box(es) but $n_title data-title — the composed reply would have unnamed headings"
    dupes="$(grep -oE 'data-id="[^"]*"' <<<"$body" | sort | uniq -d | head -3 | tr '\n' ' ')"
    [[ -n "$dupes" ]] \
      && report consult "$name" "duplicate ids ($dupes) — two claims answering to one id"

    # Requirement 2 — the page composes the reply, and says how many are blank.
    grep -q 'id="consult-copy"' <<<"$body" \
      || report consult "$name" "no compose-and-copy button (id=\"consult-copy\") — the reader has to assemble the reply by hand"
    grep -q 'id="consult-status"' <<<"$body" \
      || report consult "$name" "no status line (id=\"consult-status\") — nowhere to report how many items are still blank"
    grep -qi 'blank' <<<"$body" \
      || report consult "$name" "the composer never mentions blank items — a half-answered page must be visible BEFORE it is pasted"

    # A consultation carries a visual by DEFAULT (USAGE-19: asked ~9 times over
    # 90 days across 3 projects, granted every time, which is why it never
    # registered as a defect). No checker can judge whether a topic has a shape
    # worth drawing, so the check is on the DECLARATION: carry a visual, or say
    # in one line why there is none. Silence is the only thing that fails.
    if ! grep -qiE '<svg|<img|class="mermaid"|<canvas' <<<"$body"; then
      grep -qiE '<meta[^>]+name=["'"'"']?consult-visual["'"'"']?[^>]+content=["'"'"']?none:[^"'"'"']+' <<<"$body" \
        || report consult "$name" "no visual and no <meta name=\"consult-visual\" content=\"none: why\"> — a consultation opens with the drawing when the subject has a shape, and states the reason when it does not"
    fi

    # The template's own recorded regression: with only the media query, an
    # explicitly-toggled dark page keeps the light sticky bar and the blank-count
    # lands at 1.31:1. A page derived from the template carries both forms.
    tr -d '\n' <<<"$body" | grep -qE 'data-theme="dark"[^{]*consult-bar' \
      || report consult "$name" "no :root[data-theme=\"dark\"] rule for .consult-bar — the blank-count status is unreadable on an explicitly-dark page"
  fi
done

# --- Requirement 1, across regenerations (--prev) ----------------------------
# "Ids are assigned once and never renumbered" is only checkable with both
# versions in hand, which is why it went unenforced and was then broken by its
# own author: a claim moved from D4 to D5 between two versions of one
# consultation, so a reply about "D5" meant two different things, and the
# violation was papered over with a note to the reader.
#
# The failure is a SHIFT — the ids all still exist, the titles moved — so the
# check is title stability across the ids the two versions share. An id that
# DISAPPEARS is not flagged: ids are never renumbered, but a claim is allowed to
# be closed out.
if [[ -n "$PREV" ]]; then
  if [[ ! -f "$PREV" ]]; then
    report consult-ids "$(basename "$PREV")" "--prev file does not exist"
  else
    moved="$(python3 - "$PREV" "$1" <<'PY'
import re, sys, unicodedata

PAIR = re.compile(r'data-id="([^"]*)"[^>]*?data-title="([^"]*)"'
                  r'|data-title="([^"]*)"[^>]*?data-id="([^"]*)"', re.S)


def norm(s):
    # A retyped title must not read as a moved claim: collapse whitespace, drop
    # accents and case. Only a genuinely different claim behind a kept id fails.
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return " ".join(s.split()).casefold()


def ids(path):
    out = {}
    text = open(path, encoding="utf-8", errors="replace").read()
    for m in PAIR.finditer(text):
        i, t = (m.group(1), m.group(2)) if m.group(1) else (m.group(4), m.group(3))
        out.setdefault(i, norm(t))
    return out


old, new = ids(sys.argv[1]), ids(sys.argv[2])
for i in sorted(set(old) & set(new)):
    if old[i] != new[i]:
        print(f'{i}: was "{old[i]}", now "{new[i]}"')
PY
)"
    if [[ -n "$moved" ]]; then
      while IFS= read -r line; do
        report consult-ids "$(basename "$1")" \
          "id reused for a different claim — $line. Append a new id instead; a reply about that id now points somewhere else"
      done <<<"$moved"
    fi
  fi
fi

if [[ $failures -eq 0 ]]; then
  printf 'artifact contract OK (%d file(s))\n' "$#"
  exit 0
fi
printf '%d contract violation(s)\n' "$failures"
exit 1
