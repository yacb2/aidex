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
#   consult      a page the reader must ANSWER carries the §8 shape (fires when
#                the page offers a reply surface: <textarea>, contenteditable,
#                boxes appended by script, or an id="consult-copy" composer)
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

  # EVERY self check runs against the flattened body. grep is line-based and
  # `[^>]+` cannot cross a newline, so a `<script>` or `<link>` wrapped past the
  # print width by any HTML formatter walked through the contract and the page was
  # handed over fetching remote JS and CSS. The @font-face check already flattened
  # (a block spans lines by nature); that fix reached one of the five.
  #
  # `tr '\n' ' '` rather than `tr -d '\n'`: deleting the newline joins `<script`
  # to `src=` and the pattern stops matching for a second, quieter reason. The
  # tag-internal patterns are all `[^>]`-bounded, so the extra spaces are inert.
  flat="$(tr '\n' ' ' <<<"$body")"
  grep -qiE '<link[^>]+rel=["'"'"']?stylesheet' <<<"$flat" \
    && report self "$name" "external stylesheet — the file must stand alone offline"
  grep -qiE '<script[^>]+src=' <<<"$flat" \
    && report self "$name" "external script — the file must stand alone offline"
  grep -qiE '@import[[:space:]]+(url\()?["'"'"']?https?:' <<<"$flat" \
    && report self "$name" "@import of a remote stylesheet"
  grep -qiE '<img[^>]+src=["'"'"']?https?:' <<<"$flat" \
    && report self "$name" "remote image — breaks offline and leaks a request"
  # Only a remote src counts: url(data:…) is inlined and honours the contract.
  grep -qiE '@font-face[^}]*url\([[:space:]]*["'"'"']?(https?:)?//' <<<"$flat" \
    && report self "$name" "remote @font-face src — the font never loads offline and leaks a request"

  dir="$(dirname "$f")"
  assets="$(find "$dir" -maxdepth 1 \( -name '*.css' -o -name '*.js' \) 2>/dev/null | head -3)"
  [[ -n "$assets" ]] \
    && report siblings "$name" "sibling assets next to it ($(basename "$(head -1 <<<"$assets")")…) — inline them"

  # --- § 8: the page is a CONSULTATION, not a read ---------------------------
  # Detection is any REPLY SURFACE, not the template's own class name: a page that
  # never copied the template is precisely the case that has no `.consult-item`
  # to key on, and that is the violation observed in the field (BL-168 — a
  # hand-rolled consultation page with 9 reply boxes, 0 stable ids and no
  # doctype). A report meant to be read has no inputs, so this stays silent for
  # an ordinary route B page.
  #
  # The gate was the literal string `<textarea`, which is the one element a
  # hand-rolled page is free NOT to use: contenteditable divs and boxes appended
  # by script both skipped all of §8 and printed `artifact contract OK`. Every
  # alternative below is structural — a tag, an attribute, a DOM call, the
  # composer's own id — so prose that merely NAMES a textarea is still a read.
  if grep -qiE '<textarea|contenteditable=|createElement\([^)]*textarea|id=["'"'"']?consult-copy' <<<"$flat"; then
    # Reply boxes, however they are spelled. Counted against data-id below, so a
    # contenteditable page is told which ids it is missing instead of being told
    # nothing at all.
    n_area="$(grep -oiE '<textarea|contenteditable=' <<<"$body" | wc -l | tr -d ' ')"
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
    # Quote style is the author's choice — and a title that quotes something
    # forces single quotes on that attribute even on a template-derived page — so
    # read the VALUE rather than requiring one spelling of the delimiters. The
    # double-quote-only form silently reported no duplicates on a single-quoted
    # page while the count checks above (which are quote-agnostic) passed it.
    dupes="$(python3 - "$f" <<'PY'
import collections, re, sys

# \x27 rather than a literal apostrophe. The bash lexer for $( ) counts
# apostrophes even inside a quoted heredoc, and an odd number of them swallows
# the closing paren. `re` reads \x27 as the apostrophe, so the pattern is the
# same one. (This comment is written without apostrophes for the same reason.)
ATTR = re.compile(r'\bdata-id\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))', re.I | re.S)
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
# finditer + groups(), never findall: findall reports a non-participating group
# as "" rather than None, so every id collapsed onto the empty string and the
# scan reported one duplicate that did not exist instead of the ones that did.
vals = [next(g for g in m.groups() if g is not None) for m in ATTR.finditer(text)]
print(" ".join(v for v, n in sorted(collections.Counter(vals).items()) if n > 1)[:200])
PY
)"
    dupe_rc=$?
    if [[ $dupe_rc -ne 0 ]]; then
      report consult "$name" "the duplicate-id scan did not run (python3 exited $dupe_rc)"
    elif [[ -n "$dupes" ]]; then
      report consult "$name" "duplicate ids ($dupes) — two claims answering to one id"
    fi

    # Requirement 2 — the page composes the reply, and says how many are blank.
    grep -q 'id="consult-copy"' <<<"$body" \
      || report consult "$name" "no compose-and-copy button (id=\"consult-copy\") — the reader has to assemble the reply by hand"
    grep -q 'id="consult-status"' <<<"$body" \
      || report consult "$name" "no status line (id=\"consult-status\") — nowhere to report how many items are still blank"
    # Read the COMPOSER, not the whole document. This was `grep -qi 'blank'` over
    # the file, which measured nothing about the thing it names:
    #   false negative — a page with its blank accounting torn out still matched,
    #     because the style block that references/02 §8 tells authors to copy
    #     verbatim contains the words "blank-count status" in a CSS COMMENT, and
    #     the template's textarea placeholders say "leave blank to skip it". The
    #     check was a tautology on the suite's own happy path.
    #   false positive — a correct Spanish consultation reports "sin responder"
    #     and has no occurrence of the English word at all, so the language: field
    #     the suite ships was unusable together with the consultation shape.
    # Script content with comments stripped is what remains: identifiers are
    # English by house rule, so the composer still computes `blank` whatever
    # language the page displays. Residual, and it is documented rather than
    # hidden: a hand-rolled composer using non-English identifiers still fails.
    composer="$(python3 - "$f" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
js = "\n".join(m.group(1) for m in
               re.finditer(r"<script\b[^>]*>(.*?)</script>", text, re.I | re.S))
js = re.sub(r"/\*.*?\*/", " ", js, flags=re.S)     # block comments
js = re.sub(r"(?m)//.*$", " ", js)                 # line comments
print(js)
PY
)"
    composer_rc=$?
    if [[ $composer_rc -ne 0 ]]; then
      report consult "$name" "the composer scan did not run (python3 exited $composer_rc)"
    elif ! grep -qi 'blank' <<<"$composer"; then
      report consult "$name" "the composer never counts blank items — a half-answered page must be visible BEFORE it is pasted. The check reads <script> content with comments stripped, so prose, CSS comments and placeholder text do not satisfy it"
    fi

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
  # `-f` alone tests existence and regular-file-ness, never readability, so a
  # mode-000 file passed this guard and blew up in open() — which the swallow
  # below then read as "no ids moved".
  if [[ ! -f "$PREV" || ! -r "$PREV" ]]; then
    report consult-ids "$(basename "$PREV")" "--prev is not a readable file (missing, a directory, or unreadable) — nothing to compare against"
  else
    moved="$(python3 - "$PREV" "$1" <<'PY'
import re, sys, unicodedata

# Read the TAG, then its attributes, rather than matching one spelling of an
# id/title pair. The pair regex hard-required double quotes on both attributes
# and fixed nothing about their order, so a single-quoted page — or a page whose
# title merely quotes something, which forces single quotes on that one
# attribute — dropped out of the map entirely and every shift on it went
# unreported.
TAG = re.compile(r'<[^>]*\bdata-id\s*=[^>]*>', re.I | re.S)
# \x27, not a literal apostrophe: the bash lexer for $( ) counts apostrophes
# even inside a quoted heredoc, so an odd number of them eats the closing paren.
ATTR = re.compile(r'\bdata-(id|title)\s*=\s*'
                  r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))', re.I | re.S)


def norm(s):
    # A retyped title must not read as a moved claim: collapse whitespace, drop
    # accents and case. Only a genuinely different claim behind a kept id fails.
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return " ".join(s.split()).casefold()


def ids(path):
    out = {}
    text = open(path, encoding="utf-8", errors="replace").read()
    for tag in TAG.finditer(text):
        attrs = {}
        for m in ATTR.finditer(tag.group(0)):
            # `is not None`, never truthiness: an empty value is a real value,
            # and testing it for truth used to select an unmatched branch and
            # crash norm(None) — killing the diff for the entire page.
            val = next(g for g in m.groups()[1:] if g is not None)
            attrs.setdefault(m.group(1).lower(), val)
        if "id" in attrs and "title" in attrs:
            out.setdefault(attrs["id"], norm(attrs["title"]))
    return out


old, new = ids(sys.argv[1]), ids(sys.argv[2])
for i in sorted(set(old) & set(new)):
    if old[i] != new[i]:
        print(f'{i}: was "{old[i]}", now "{new[i]}"')
PY
)"
    # The exit status, not just stdout. This is the one rule --prev exists to
    # enforce, and it ran under `set -uo pipefail` with no `-e`: an exception,
    # a missing interpreter or an unreadable file all produced an empty `moved`
    # that read as "no ids moved", after which the script printed `artifact
    # contract OK` and exited 0.
    diff_rc=$?
    if [[ $diff_rc -ne 0 ]]; then
      report consult-ids "$(basename "$1")" "the id-stability diff did not run (python3 exited $diff_rc) — a check that is skipped is indistinguishable from a check that passed, so this fails rather than reporting no change"
    elif [[ -n "$moved" ]]; then
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
