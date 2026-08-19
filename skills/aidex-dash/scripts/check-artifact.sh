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
#   layout       a kit page keeps its content inside .page / .main (BL-177),
#                and every table inside a scrolling wrapper
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

  # --- the kit's layout container (BL-177) -----------------------------------
  # The kit puts the entire width system on two classes: `.page` caps the measure
  # and lays the two-column grid, `.main` is the content column. wrap-report.sh
  # injects the STYLES; the STRUCTURE comes from skeleton.html, which is a file
  # the author is expected to copy and nothing made them. A page written as a bare
  # <h1> plus sections got every token and no layout — full bleed at the browser's
  # default width, enormous type past 64rem — and passed every check here.
  #
  # Scoped to pages that carry the kit stamp: a page without it has no `.page`
  # rule to be inside of, and judging it would fail every pre-kit artifact.
  #
  # Matched as class TOKENS. components.css spells `.page` and `.main` as
  # selectors and is injected into every page, so a looser grep is answered by the
  # stylesheet on precisely the page that has none of the structure.
  #
  # There is no opt-out marker and there is deliberately none: a page that wants
  # to be full-bleed overrides `.page { max-width: none }` in its own <style> and
  # keeps the grid, the rail and the responsive collapse. A second mechanism would
  # buy nothing the cascade does not already give.
  if grep -qiE '<meta[^>]+name=["'"'"']artifact-kit' <<<"$flat"; then
    for cls in page main; do
      grep -qE 'class=["'"'"']([^["'"'"']]*[[:space:]])?'"$cls"'([[:space:]][^["'"'"']]*)?["'"'"']' <<<"$flat" \
        || report layout "$name" "no element with class=\"$cls\" — the content is outside the kit's layout container, so the page renders full-bleed with no reading measure. Wrap it the way assets/artifact-kit/skeleton.html does: <div class=\"page\"><main class=\"main\">…</main><aside class=\"rail\">…</aside></div>"
    done
  fi

  # --- wide content sits inside a scroll container ---------------------------
  # `.tw` is the kit's table wrapper and nothing made a page use it. A table is
  # the one element that cannot be capped: `max-width` will not take it below its
  # min-content width, and `display: block` collapses a narrow table's cells — so
  # there is no CSS net, only the wrapper. Measured on a real page: a 12-column
  # table in the 728px column renders 1055px wide, right edge at x=1299, with the
  # rail starting at x=1028. It paints OVER the rail, and while the viewport is
  # wider than the page there is no scrollbar to give it away.
  #
  # Same stamp gate as the layout check above, for the same reason and one more:
  # a route-A board is nothing but tables and is not a kit page.
  if grep -qiE '<meta[^>]+name=["'"'"']?artifact-kit' <<<"$flat"; then
    unwrapped="$(python3 - "$f" <<'PYTBL'
import re, sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()

# 1. Which classes scroll, according to the stylesheets THIS document carries. Read
#    rather than whitelisted: a page that wraps its tables in a `.scroll` of its own
#    is honouring the rule, and failing it would be a checker inventing a defect.
css = "\n".join(m.group(1) for m in
                re.finditer(r"<style\b[^>]*>(.*?)</style>", text, re.I | re.S))
css = re.sub(r"/\*.*?\*/", " ", css, flags=re.S)
scroll = set()
for sel, decls in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
    if re.search(r"overflow(-x)?\s*:\s*(auto|scroll)", decls, re.I):
        scroll.update(re.findall(r"\.([A-Za-z_][\w-]*)", sel))

# 2. Walk the markup keeping an ancestor stack. Script and style content goes
#    first: a template string inside the composer is not markup.
body = re.sub(r"<(script|style)\b[^>]*>.*?</\1\s*>", " ", text, flags=re.I | re.S)
# Comments too. A page whose comment carries an example table is not shipping an
# unwrapped table, and skeleton.html is a file of examples in comments — the
# checker would have invented a defect on the one page authors copy from.
body = re.sub(r"<!--.*?-->", " ", body, flags=re.S)
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
        "meta", "param", "source", "track", "wbr"}
stack, bad = [], 0
for m in re.finditer(r"<(/?)([a-zA-Z][\w:-]*)([^>]*)>", body):
    closing, tag, attrs = m.group(1), m.group(2).lower(), m.group(3)
    if closing:
        for i in range(len(stack) - 1, -1, -1):
            if stack[i][0] == tag:
                del stack[i:]
                break
        continue
    if tag in VOID or attrs.rstrip().endswith("/"):
        continue
    cm = re.search(r"\bclass\s*=\s*(?:\"([^\"]*)\"|\x27([^\x27]*)\x27|([^\s>]+))",
                   attrs, re.I)
    classes = set(next(g for g in cm.groups() if g is not None).split()) if cm else set()
    if tag == "table" and not any(c in scroll for _, anc in stack for c in anc):
        bad += 1
    stack.append((tag, classes))

print(bad)
PYTBL
)"
    unwrapped_rc=$?
    if [[ $unwrapped_rc -ne 0 ]]; then
      report layout "$name" "the table-wrapper scan did not run (python3 exited $unwrapped_rc)"
    elif [[ "$unwrapped" != "0" ]]; then
      report layout "$name" "$unwrapped table(s) outside any scrolling container — a table cannot be capped, so a wide one renders over the rail with no scrollbar to show it. Wrap each in <div class=\"tw\">…</div>, or in any wrapper this page declares with overflow-x: auto"
    fi
  fi

  # --- § 8: the page is a CONSULTATION, not a read ---------------------------
  # Detection is an OR over three arms, and it has to stay one:
  #   a reply surface in the MARKUP  — a page that never copied the template has
  #     no `.consult-item` to key on, and that is the violation observed in the
  #     field (BL-168 — a hand-rolled page with 9 reply boxes, 0 stable ids and
  #     no doctype). Keying only off data-id would drop exactly that case.
  #   a data-id item                 — an item whose reply surface is a radio
  #     group or a select carries no textarea and would otherwise be invisible.
  #   the composer button id         — a page that offers to compose a reply.
  #   the item CLASS in an attribute — a page that builds its reply boxes at
  #     runtime has no reply surface in its markup at all, and this is what is
  #     left of it. Matched as `class="…consult-item…"`, never as the bare word:
  #     components.css is injected into every page and defines `.consult-item`,
  #     so an unanchored match would fire on every read.
  # A report meant to be read hits none of the four and this stays silent.
  #
  # The patterns are `<tag`-anchored so the injected composer does not match its
  # own querySelector strings. The v1 clause `createElement\([^)]*textarea` was
  # REMOVED rather than worked around: once artifact-kit ships composer.js on
  # every page, its clipboard fallback contains that string always, so the clause
  # fired on 100% of pages and discriminated nothing. What it existed for —
  # reply boxes appended by script — is covered by the data-id arm.
  surface_pat='<textarea|contenteditable=|<select|<input[^>]+type=["'"'"']?(radio|checkbox|text)'
  if grep -qiE "$surface_pat"'|data-id=|id=["'"'"']?consult-copy|class=["'"'"'][^"'"'"']*consult-item' <<<"$flat"; then
    # Items, not boxes. v1 counted `<textarea` occurrences against data-id, which
    # told a radio-only page it had ids for boxes that did not exist. The unit is
    # the ITEM: it needs a stable id, a title, and at least one reply surface of
    # any kind inside it.
    items="$(python3 - "$f" <<'PY'
import re, sys

# Subtree by tag-name balance, not by an HTML parser: a page with an unclosed
# <p> is still well formed enough to answer, and counting only the item own tag
# name is immune to it.
OPEN = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*\bdata-id\s*=\s*'
                  r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))[^>]*>', re.I | re.S)
TITLE = re.compile(r'\bdata-title\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))', re.I | re.S)
SURFACE = re.compile(r'<textarea\b|contenteditable\s*=|<select\b'
                     r'|<input\b[^>]*\btype\s*=\s*["\x27]?(?:radio|checkbox|text)\b'
                     r'|<input\b(?![^>]*\btype\s*=)', re.I | re.S)
# Free text, which is a SEPARATE requirement from having a reply surface at all.
# A radio group, a checkbox set and a select are closed lists: they carry the
# answer the author anticipated and lose the one they did not. Every item gets a
# place to say the rest, so the reader never has to pick the nearest wrong option.
NOTES = re.compile(r'<textarea\b|contenteditable\s*=', re.I | re.S)

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()


def subtree(tag, start):
    """Text between the item open tag and its matching close tag."""
    op = re.compile(r'<' + re.escape(tag) + r'\b', re.I)
    cl = re.compile(r'</' + re.escape(tag) + r'\s*>', re.I)
    depth, pos = 1, start
    while depth:
        m_o, m_c = op.search(text, pos), cl.search(text, pos)
        if not m_c:
            return text[start:]            # unclosed: judge what is left
        if m_o and m_o.start() < m_c.start():
            depth, pos = depth + 1, m_o.end()
        else:
            depth, pos = depth - 1, m_c.end()
            if not depth:
                return text[start:m_c.start()]
    return ""


for m in OPEN.finditer(text):
    tag = m.group(1)
    ident = next(g for g in m.groups()[1:] if g is not None)
    body = subtree(tag, m.end())
    has_title = 1 if TITLE.search(m.group(0)) else 0
    # The open tag itself may BE the surface (an <input data-id=...>).
    has_surface = 1 if (SURFACE.search(body) or SURFACE.search(m.group(0))) else 0
    has_notes = 1 if (NOTES.search(body) or NOTES.search(m.group(0))) else 0
    print(f"{ident}\t{has_title}\t{has_surface}\t{has_notes}")
PY
)"
    items_rc=$?
    if [[ $items_rc -ne 0 ]]; then
      report consult "$name" "the consultation-item scan did not run (python3 exited $items_rc)"
      items=""
    fi
    n_items=0
    [[ -n "$items" ]] && n_items="$(wc -l <<<"$items" | tr -d ' ')"

    # Requirement 1 — every claim is an item with a stable id. Without data-id
    # there is nothing to keep stable and nothing --prev can compare.
    if [[ "$n_items" -eq 0 ]]; then
      n_surface="$(grep -oiE "$surface_pat" <<<"$flat" | wc -l | tr -d ' ')"
      report consult "$name" "$n_surface reply surface(s) but no data-id item — every consultation item needs a stable id (copy assets/templates/consultation-block.html.template)"
    else
      while IFS=$'\t' read -r ident has_title has_surface has_notes; do
        [[ -z "$ident" ]] && continue
        # data-title is what the composed reply is headed with; without it the
        # paste says (### c3) and the reader must return to the page to learn
        # what c3 was.
        [[ "$has_title" == "1" ]] \
          || report consult "$name" "item '$ident' has no data-title — the composed reply would have an unnamed heading"
        # Any reply surface counts: textarea, contenteditable, radio, checkbox,
        # select, short text. An item with NONE is a claim the reader cannot
        # answer, which is the one shape that still fails.
        [[ "$has_surface" == "1" ]] \
          || report consult "$name" "item '$ident' has no reply surface — a consultation item the reader cannot answer"
        # ...and every item also carries FREE TEXT, whatever else it offers.
        # Reported from use: "si quiero mencionar algo más, además de la selección
        # que realicé, sea simple o múltiple, tengo que tener el espacio para
        # comentarlo". A closed list with no room to qualify the choice makes the
        # reader answer the question the page asked instead of the one they have.
        [[ "$has_notes" == "1" ]] \
          || report consult "$name" "item '$ident' has no notes box — a closed choice with nowhere to qualify it loses everything the options do not cover. Add a <textarea> to the item (assets/templates/consultation-block.html.template ships one in every block)"
      done <<<"$items"

      # Two claims answering to one id: a reply about that id points at both.
      # Read off the parsed items rather than a second regex over the file, so
      # every quote form the item scan accepts is covered here too.
      dupes="$(cut -f1 <<<"$items" | sort | uniq -d | tr '\n' ' ' | sed 's/ *$//')"
      [[ -n "$dupes" ]] \
        && report consult "$name" "duplicate ids ($dupes) — two claims answering to one id"
    fi
    # ...and the page carries the general-notes item, always last, always present:
    # it is where the reply that fits no question goes, and without it that reply
    # is lost or forced into the wrong item.
    #
    # Matched as `class="…consult-notes…"`, never as the bare word. components.css
    # DEFINES `.consult-notes` and is injected into every page, so an unanchored
    # grep would be answered by the stylesheet on a page that carries no such item
    # — the lie-by-omission this contract exists to prevent, and it has already
    # happened twice inside this kit.
    grep -qE 'class=["'"'"'][^"'"'"']*consult-notes' <<<"$flat" \
      || report consult "$name" "no general-notes item (class=\"consult-item consult-notes\") — the answer that fits none of the questions has nowhere to go"

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
      # The reason has to be a REASON. The shipped template declared
      # `none: replace this with the reason, or with svg/mermaid/img` — the
      # instruction to write a reason, standing in for one — and §8 tells authors
      # to copy that template rather than re-derive it. So every derived
      # consultation arrived with this gate already satisfied by a page that has
      # no visual and no reason: the exact state §8 says must fail. The grep was
      # one away from review and it returned the placeholder.
      visual_reason="$(python3 - "$f" <<'PY'
import re, sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r'<meta\b[^>]*\bname\s*=\s*["\x27]?consult-visual["\x27]?[^>]*'
              r'\bcontent\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)', text, re.I | re.S)
val = "" if not m else next(g for g in m.groups() if g is not None).strip()
# Only a `none:` declaration carries a reason. Anything else (svg / mermaid / img)
# is a claim to have a visual, which the tag check above already adjudicated.
print(val[5:].strip() if val.lower().startswith("none:") else "")
PY
)"
      visual_rc=$?
      if [[ $visual_rc -ne 0 ]]; then
        report consult "$name" "the visual-declaration scan did not run (python3 exited $visual_rc)"
      elif [[ -z "$visual_reason" ]]; then
        report consult "$name" "no visual and no <meta name=\"consult-visual\" content=\"none: why\"> — a consultation opens with the drawing when the subject has a shape, and states the reason when it does not"
      elif grep -qiE '^(replace this|replace with|tbd|todo|fixme|xxx|why|the reason)\b' <<<"$visual_reason"; then
        report consult "$name" "the consult-visual declaration is still the template placeholder (\"$visual_reason\") — that is the instruction to write a reason, not a reason. Replace it with why this page has no drawing, or with svg/mermaid/img"
      fi
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
