#!/usr/bin/env python3
"""check_artifact.py — the artifact contract. Logic lives here; check-artifact.sh
is the entry, the same split wrap-report.sh already has.

This used to be 486 lines of bash wrapping five python3 heredocs. The port is not
cosmetic: the dominant defect class in the contract's own history is "prose
satisfies the grep" — a comment or a template string answering a check on behalf
of a page that does not carry the rule — and it happened twice inside the kit.
Bash greps over raw HTML are the surface that class lives on. One Python process
that owns every scan can strip scripts, styles and comments ONCE, share the
result between checks, and fail closed in-process instead of reconstructing
"did the heredoc run" from an exit code.

Checks (per file):
  doctype      complete document, not a headless fragment (quirks mode)
  charset      <meta charset> — file:// pages have no server to declare it
  viewport     <meta name="viewport"> — otherwise unusable on a phone
  title        <title> — names the browser tab
  themes       prefers-color-scheme — readable in dark mode
  self         no external stylesheet/script/font/image: one file, no network
  siblings     no .css/.js dropped next to it — the artifact IS the file
  double-wrap  one kit envelope per document: two stamps or two composer.js
               mean an already-wrapped page was fed back in as a body (BL-414)
  layout       a kit page keeps its content inside .page / .main (BL-177),
               and every table inside a scrolling wrapper
  consult      a page the reader must ANSWER carries the §8 shape
  consult-shape every decision inside a block (`.consult-group`), every block
               with a decision, nothing but blocks between the first block and
               the general notes, only header/figure/ledger before them (BL-247),
               and no block or item after the general notes — reference
               sections may follow them (BL-457)
  consult-ids  with --prev: an id kept between two regenerations still names
               the same claim, and no id disappears — a closed claim stays on
               the page; only a page declaring `consult-surfaces: none` (the
               closed-page exit) may drop ids (BL-396)
  consult-marker-duties with --prev: every ask marker a saved reply
               (`.aidex-artifact-prev/<stem>.reply.md`) puts on an item owes a
               checkable duty (02-local-first-artifacts.md, the asks table's Gate
               column), judged against `.aidex-artifact-prev/<stem>.answered.html`
               (`save-reply.sh`'s snapshot of the page as the reader answered it) —
               never against the contract baseline, which is advanced on every
               passing wrap and so cannot be what a round's duties are judged
               against (BL-475, BL-504). With no reply/answered snapshot saved for
               the page at all it only WARNS.
  svg-contrast figure text below 4.5:1 against what it is painted on, in either
               theme (BL-330). The one check with two severities: it FAILS a
               named file — the wrap — and only WARNS in `--census`, because a
               page being written must not ship unreadable text while the same
               finding on a page nobody is editing is noise no one can clear.
  <class>      one FAIL per finding of contract_defects.py's source classes
               (decision-item-without-options, mixed-content-types,
               copy-control-placement, ...; LOOP-006), keyed by the class slug
               and prefixed with the line. That module owns every rule; this
               only reports it on every page, and only WARNS in `--census`
               (CENSUS_ADVISORY)

Warnings (`WARN [check]`) are a SECOND channel and deliberately not a third
severity of the first. They report a shape that renders badly or reads wrong
without being a contract violation, they never change the exit code, and they
are not waivable — a waiver keys on (`artifact-<check>`, path) and sharing that
namespace would let one waiver silence a real failure on the same file. They
run at authoring time only (a direct check of named files), never in `--census`:
a census warning on a page nobody is editing is noise no one can clear.

  consult-opts marks outside `.opts` — the kit styles option groups only there,
               so any other wrapper renders them unstyled (BL-244)
  consult-rec  "(recommended)" typed into `data-label` — the marker then travels
               in the pasted reply and is invisible on the page (BL-245)
  consult-independent a checkbox group whose option labels each name a distinct
               tracked id (BL-NNN, a dated plan slug) — several decisions drawn as
               one item; a checkbox group is for facets of ONE decision, and each id
               is its own two-option radio item (BL-375)
  consult-facts a paragraph inside a block context or an item body carrying four
               or more `<code>` tokens or semicolon-separated clauses — the shape
               of "N things with their state and verdict" written as prose, which
               the reader returns unread; rows, not a paragraph (BL-269, BL-270)
  consult-order a block whose last item is followed by evidence (figure, img,
               svg, video, table, canvas, a `@@VIDEO` marker paragraph) before
               the block ends — the answer box rendered above the material it
               asks about; evidence precedes its question (BL-463)
  svg-text     two inline-SVG labels whose estimated boxes intersect, a label
               that leaves its viewBox, or a label wider than the rect it sits
               in — a consultation shipped two unreadable figures past every
               check above because the contract reads DOM shape, never
               geometry. No renderer at wrap time, so this is a static estimate
               (font-size x per-character width from a Chrome calibration,
               ±5 %); labels under a rotate/scale/matrix transform are skipped
               rather than guessed. Runs on every page, not only consultations
               (BL-310)

Exit 0 = every file passes. Exit 1 = at least one violation (each printed).
Exit 2 = usage error.
"""
import hashlib
import html as _html
import xml.etree.ElementTree as _ET
import os
import re
import time
import sys
import unicodedata

# --- § 8 detection patterns --------------------------------------------------
# Matched against the FLATTENED body (newlines to spaces): grep was line-based
# and `[^>]+` could not cross a newline, so a tag wrapped past the print width
# by any HTML formatter walked through the contract (the @font-face check had
# flattened already; that fix had reached one of five).
SURFACE_PAT = re.compile(
    r'<textarea|contenteditable=|<select'
    r'|<input[^>]+type=["\']?(?:radio|checkbox|text)', re.I)
# The patterns are `<tag`-anchored so the injected composer does not match its
# own querySelector strings. The v1 clause `createElement\([^)]*textarea` was
# REMOVED rather than worked around: once artifact-kit ships composer.js on
# every page, its clipboard fallback contains that string always, so the clause
# fired on 100% of pages and discriminated nothing.
CONSULT_GATE = re.compile(
    r'<textarea|contenteditable=|<select'
    r'|<input[^>]+type=["\']?(?:radio|checkbox|text)'
    r'|data-id=|id=["\']?consult-copy|class=["\'][^"\']*consult-item', re.I)

KIT_STAMP = re.compile(r'<meta[^>]+name=["\']?artifact-kit', re.I)

# --- one kit envelope per document (BL-414) ----------------------------------
# A revising caller that takes the WRAPPED page from disk as its body gets a
# second full kit: two stamps, two composers, and both run buildRail() against
# the same #raillist and APPEND to it, so the reader sees the index twice. The
# composer is counted by CODE, not by its banner comment — prose satisfying the
# grep is this contract's own dominant defect class. The signature is a function
# the composer DECLARES, not a DOM query it makes: a page's own script may read
# `#raillist` legitimately (test-composer-functional.sh's harness does), and
# keying on that counted the harness as a second composer.
COMPOSER_SIG = re.compile(r"\bfunction\s+railLink\s*\(")


def composer_copies(text):
    """How many <script> blocks in this document are a kit composer."""
    n = 0
    for m in re.finditer(r"<script\b[^>]*>(.*?)</script>", text, re.I | re.S):
        js = re.sub(r"/\*.*?\*/", " ", m.group(1), flags=re.S)
        js = re.sub(r"(?m)//.*$", " ", js)
        if COMPOSER_SIG.search(js):
            n += 1
    return n

# The two halves of the gate, split for the consult-surfaces declaration below.
# FREE_TEXT is what a consultation IS — BL-168's page was hand-rolled textareas
# — and STRUCTURE is a page already claiming to be one; neither can be declared
# away. What CAN be is the remainder: closed controls (select, radio, checkbox,
# short text) on a page meant only to be read, which is the ordinary shape of a
# dashboard filter and was a false positive with no exit.
FREE_TEXT = re.compile(r'<textarea|contenteditable=', re.I)
CONSULT_STRUCTURE = re.compile(
    r'data-id=|id=["\']?consult-copy|class=["\'][^"\']*consult-item', re.I)
# The same thing minus the copy BUTTON (BL-331). A button is chrome; what makes
# a page a consultation is that it carries questions. A page whose last item was
# answered has none — §8's own model says a decided item leaves the question set
# — and it was then stuck: the gate fired on the bar still sitting in its body,
# and the `consult-surfaces` escape was skipped because CONSULT_STRUCTURE
# matched that same bar. The failure message pointed at the declaration the page
# was already carrying. Hit closing the figure-route bench page, 2026-09-07.
CONSULT_ITEMS = re.compile(
    r'data-id=|class=["\'][^"\']*consult-item', re.I)


def flatten(text):
    """Newlines to spaces, never deleted: deleting joins `<script` to `src=`
    and the tag-internal patterns stop matching for a second, quieter reason."""
    return text.replace("\n", " ").replace("\r", " ")


def strip_script_style(text):
    """Markup only: a template string inside the composer is not markup."""
    return re.sub(r"<(script|style)\b[^>]*>.*?</\1\s*>", " ", text,
                  flags=re.I | re.S)


def strip_html_comments(text):
    """A commented-out example is not markup either — skeleton.html is a file
    of examples in comments, and judging them invents defects on the one page
    authors copy from."""
    return re.sub(r"<!--.*?-->", " ", text, flags=re.S)


# --- lang: the body must speak the language <html lang> declares (BL-279) -------
# Stopword sets and thresholds mirror validate.py's body-language heuristic; a
# page whose dominant language disagrees with its lang attribute is the shape
# that shipped on 2026-08-31 — English prose under a Spanish profile, with the
# composer's chrome (which keys off lang) in Spanish on top of it.
SPANISH_STOPWORDS = {
    "el", "la", "los", "las", "una", "uno", "unas", "unos", "de", "del", "al",
    "que", "es", "son", "está", "están", "fue", "era", "ser", "hay", "como",
    "pero", "más", "para", "por", "sobre", "también", "porque", "cuando",
    "donde", "entre", "desde", "hasta", "según", "muy", "ya", "cada", "todo",
    "toda", "todos", "todas", "esta", "este", "esto", "estas", "estos", "se",
    "sus", "les", "nos", "tiene", "tienen", "puede", "pueden", "debe", "deben",
    "así", "aquí", "durante", "después",
}
ENGLISH_STOPWORDS = {
    "the", "and", "of", "to", "in", "is", "that", "for", "with", "on", "as",
    "are", "this", "be", "it", "by", "from", "or", "an", "not", "at", "was",
    "we", "if", "has", "have", "will", "which", "when", "can", "should",
    "must", "each", "all", "into", "than", "then", "these", "those", "there",
    "any", "only", "also", "after", "before", "over", "under", "between",
}
LANG_MIN_HITS = 10      # below this the page is too short to have a language
LANG_RATIO = 3          # dominant = at least 3x the other language's stopwords
HTML_LANG = re.compile(r'<html\b[^>]*\blang\s*=\s*["\']?([A-Za-z]{2})', re.I)
WORD_RE_LANG = re.compile(r"[a-záéíóúñü]+", re.I)


def visible_source(text):
    """The page's markup minus scripts, styles and comments (tags kept)."""
    return strip_html_comments(strip_script_style(text))


RAW_LINK = re.compile(r"\[[^\]<>\n]+\]\([^()\s<>]+(?:\([^()\s<>]*\)[^()\s<>]*)?\)")


def visible_text(text):
    """The page as a reader sees it: no scripts, styles, comments or tags."""
    return re.sub(r'<[^>]+>', ' ', visible_source(text))


def language_mismatch(text):
    """(declared, dominant, es_hits, en_hits) when the body's dominant language
    contradicts <html lang>; None when they agree or the page is too short."""
    m = HTML_LANG.search(text)
    declared = (m.group(1).lower() if m else "en")
    if declared not in ("es", "en"):
        return None
    tokens = WORD_RE_LANG.findall(visible_text(text).lower())
    es = sum(1 for w in tokens if w in SPANISH_STOPWORDS)
    en = sum(1 for w in tokens if w in ENGLISH_STOPWORDS)
    if declared == "es" and en >= LANG_MIN_HITS and en >= LANG_RATIO * es:
        return (declared, "en", es, en)
    if declared == "en" and es >= LANG_MIN_HITS and es >= LANG_RATIO * en:
        return (declared, "es", es, en)
    return None


def script_code(text):
    """<script> contents with JS comments stripped. Identifiers are English by
    house rule, so this is what a composer is judged by whatever language the
    page displays — prose, CSS comments and placeholder text cannot answer for
    it (they did, twice)."""
    js = "\n".join(m.group(1) for m in
                   re.finditer(r"<script\b[^>]*>(.*?)</script>", text,
                               re.I | re.S))
    js = re.sub(r"/\*.*?\*/", " ", js, flags=re.S)
    return re.sub(r"(?m)//.*$", " ", js)


# --- the kit's layout container (BL-177) -------------------------------------

def scroll_classes(text):
    """Which classes scroll, according to the stylesheets THIS document carries.
    Read rather than whitelisted: a page that wraps its tables in a `.scroll` of
    its own is honouring the rule, and failing it would be a checker inventing a
    defect."""
    css = "\n".join(m.group(1) for m in
                    re.finditer(r"<style\b[^>]*>(.*?)</style>", text,
                                re.I | re.S))
    css = re.sub(r"/\*.*?\*/", " ", css, flags=re.S)
    scroll = set()
    for sel, decls in re.findall(r"([^{}]+)\{([^{}]*)\}", css):
        if re.search(r"overflow(-x)?\s*:\s*(auto|scroll)", decls, re.I):
            scroll.update(re.findall(r"\.([A-Za-z_][\w-]*)", sel))
    return scroll


VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
             "meta", "param", "source", "track", "wbr"}


def unwrapped_tables(text):
    """Tables outside any scrolling ancestor, by walking the markup with an
    ancestor stack. A table is the one element the page cannot cap — max-width
    will not take it below its min-content width — so an unwrapped wide one is
    drawn straight over the rail, with no scrollbar to show it."""
    scroll = scroll_classes(text)
    body = strip_html_comments(strip_script_style(text))
    stack, bad = [], 0
    for m in re.finditer(r"<(/?)([a-zA-Z][\w:-]*)([^>]*)>", body):
        closing, tag, attrs = m.group(1), m.group(2).lower(), m.group(3)
        if closing:
            for i in range(len(stack) - 1, -1, -1):
                if stack[i][0] == tag:
                    del stack[i:]
                    break
            continue
        if tag in VOID_TAGS or attrs.rstrip().endswith("/"):
            continue
        cm = re.search(r"\bclass\s*=\s*(?:\"([^\"]*)\"|\x27([^\x27]*)\x27"
                       r"|([^\s>]+))", attrs, re.I)
        classes = (set(next(g for g in cm.groups() if g is not None).split())
                   if cm else set())
        if tag == "table" and not any(c in scroll
                                      for _, anc in stack for c in anc):
            bad += 1
        stack.append((tag, classes))
    return bad


# --- § 8 items ----------------------------------------------------------------

ITEM_OPEN = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*\bdata-id\s*=\s*'
                       r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))[^>]*>',
                       re.I | re.S)
ITEM_TITLE = re.compile(r'\bdata-title\s*=\s*'
                        r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))',
                        re.I | re.S)
ITEM_SURFACE = re.compile(r'<textarea\b|contenteditable\s*=|<select\b'
                          r'|<input\b[^>]*\btype\s*=\s*["\x27]?'
                          r'(?:radio|checkbox|text)\b'
                          r'|<input\b(?![^>]*\btype\s*=)', re.I | re.S)
# Free text, which is a SEPARATE requirement from having a reply surface at all.
# A radio group, a checkbox set and a select are closed lists: they carry the
# answer the author anticipated and lose the one they did not.
ITEM_NOTES = re.compile(r'<textarea\b|contenteditable\s*=', re.I | re.S)
# A textarea the reader cannot see is not a notes box. The kit composer owns a
# `<textarea class="kit-marks" hidden>` per gallery row (region marks, Phase 4 of
# the gallery-review unit) and a page may carry one for a decided row; neither
# qualifies anything the reader chose. Stripped before the notes and surface
# scans, so a row with only that channel still fails both rules.
HIDDEN_TEXTAREA = re.compile(r'<textarea\b(?:[^>"\x27]|"[^"]*"|\x27[^\x27]*\x27)*?'
                             r'(?:\shidden(?=[\s=/>])|\bclass\s*=\s*["\x27][^"\x27]*\bkit-marks\b)'
                             r'.*?</textarea\s*>', re.I | re.S)
# BL-359: the item's own declaration that it is settled. `02-local-first-
# artifacts.md` § Update in place makes keeping the item and marking it the
# DEFAULT for a decided one, and both the kit's CSS and composer.js already
# honour the attribute; the checker was the only reader that did not.
# BL-421: `\b` after "decided" is satisfied by the hyphen of `data-decided-round`
# — the round stamp the wrapper writes NEXT TO this mark — so without the
# lookahead an item carrying only the stamp reads as settled and the still-asked
# rule goes silent on a live question.
ITEM_DECIDED = re.compile(r'\bdata-decided\b(?!-)', re.I)


def _subtree(text, tag, start):
    """Text between an item's open tag and its matching close tag, by tag-name
    balance rather than an HTML parser: a page with an unclosed <p> is still
    well formed enough to answer, and counting only the item's own tag name is
    immune to it."""
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


def consult_items(text):
    """Every data-id item: (id, has_title, has_surface, has_notes, decided).
    The unit is the ITEM, never the box count: v1 counted `<textarea`
    occurrences against data-id, which told a radio-only page it had ids for
    boxes that did not exist."""
    items = []
    for m in ITEM_OPEN.finditer(text):
        # A block (`.consult-group`) carries data-id/data-title so --prev can
        # hold its id stable, but it is a context, not a claim: it has no
        # reply surface of its own and is judged by check_shape instead.
        if GROUP_CLASS.search(m.group(0)):
            continue
        tag = m.group(1)
        ident = next(g for g in m.groups()[1:] if g is not None)
        body = HIDDEN_TEXTAREA.sub(' ', _subtree(text, tag, m.end()))
        # The open tag itself may BE the surface (an <input data-id=...>).
        items.append((
            ident,
            bool(ITEM_TITLE.search(m.group(0))),
            bool(ITEM_SURFACE.search(body) or ITEM_SURFACE.search(m.group(0))),
            bool(ITEM_NOTES.search(body) or ITEM_NOTES.search(m.group(0))),
            bool(ITEM_DECIDED.search(m.group(0))),
        ))
    return items


def visual_declaration(text):
    """The consult-visual meta's `none:` reason, or "" when there is none.
    Only a `none:` declaration carries a reason — anything else (svg / img) is a
    claim to have a visual, which the tag check adjudicates. `mermaid` was a third
    value until BL-328 and never rendered anywhere: no shipped code draws it and a
    local page may not fetch a renderer, so it showed the reader `graph TD`."""
    m = re.search(r'<meta\b[^>]*\bname\s*=\s*["\x27]?consult-visual["\x27]?'
                  r'[^>]*\bcontent\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)',
                  text, re.I | re.S)
    val = "" if not m else next(g for g in m.groups() if g is not None).strip()
    return val[5:].strip() if val.lower().startswith("none:") else ""


PLACEHOLDER_REASON = re.compile(
    r'^(replace this|replace with|tbd|todo|fixme|xxx|why|the reason)\b', re.I)


def surfaces_declaration(text):
    """The consult-surfaces meta's `none:` reason, or "" when there is none.
    Same shape as consult-visual, and for the same reason: no checker can judge
    whether a select is a filter or a question, so the page states which it is
    — and the reason is one grep away from review, which silence never is."""
    m = re.search(r'<meta\b[^>]*\bname\s*=\s*["\x27]?consult-surfaces["\x27]?'
                  r'[^>]*\bcontent\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)',
                  text, re.I | re.S)
    val = "" if not m else next(g for g in m.groups() if g is not None).strip()
    return val[5:].strip() if val.lower().startswith("none:") else ""


LEDGER_OPEN = re.compile(r'<(\w+)\b[^>]*\bclass\s*=\s*["\x27][^"\x27]*\bledger\b'
                         r'[^"\x27]*["\x27][^>]*>', re.I | re.S)
LEDGER_KEY = re.compile(r'class\s*=\s*["\x27][^"\x27]*\bk\b[^"\x27]*["\x27][^>]*>'
                        r'(.*?)<', re.I | re.S)
# A key is a compound in the field — "c35 · BL-265", "c1 + c12" — so the id is a
# TOKEN inside it, not the key. Leading letter required: a ledger keyed 1/2/3 is
# a numbered list, not a set of item ids, and must not be read as one.
LEDGER_TOKEN = re.compile(r'[A-Za-z][\w.-]*')


def ledger_ids(text):
    """Ids named by the ledger. Empty is a LEGITIMATE answer twice over: the
    first page of a thread carries no ledger at all, and `.ledger` is also used
    as a plain grid whose rows have no `.k` key. Neither is a violation, so
    neither reports. Id harvesting tolerates that plain grid; consult-shape
    does not EXEMPT it before the first block — a grid of anything but `.k`/`.v`
    rows is judged there like any other preamble (BL-426, `_ledger_shape`)."""
    out = set()
    for m in LEDGER_OPEN.finditer(text):
        body = _subtree(text, m.group(1), m.end())
        for k in LEDGER_KEY.findall(body):
            out.update(LEDGER_TOKEN.findall(flatten(k)))
    return out


# --- warnings: shapes that render wrong without violating the contract --------
# Both cases below were written by hand on the SAME page in one session
# (dashboard_template_ws BL-066), and both passed the contract while failing the
# reader: the contract checks ids, notes boxes and buttons, never the wrapper an
# option group sits in nor where a recommendation is legible from.

ATTR_CLASS = re.compile(r'\bclass\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27'
                        r'|([^\s>]+))', re.I)
MARK_INPUT = re.compile(r'<input\b[^>]*\btype\s*=\s*["\x27]?(?:radio|checkbox)\b',
                        re.I | re.S)


INPUT_TAG = re.compile(r'<input\b[^>]*>', re.I | re.S)
CHECKBOX_TYPE = re.compile(r'type=["\']checkbox["\']', re.I)
TRACKED_ID = re.compile(r'\bBL-\d{3}\b|\b\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)+\b')


def independent_checkbox_ids(body):
    """The distinct tracked ids named by an item's checkbox labels, when there are
    at least two and every checkbox names one. A proxy for the shape BL-375 names:
    boxes that are each a separate decision, drawn as facets of one."""
    ids = []
    for tag in INPUT_TAG.finditer(body):            # attribute order is not fixed
        if not CHECKBOX_TYPE.search(tag.group(0)):
            continue
        m = DATA_LABEL.search(tag.group(0))
        if not m:
            return []
        val = next(g for g in m.groups() if g is not None)
        found = TRACKED_ID.search(val)
        if not found:
            return []
        ids.append(found.group(0))
    return ids if len(set(ids)) == len(ids) and len(ids) >= 2 else []


def consult_item_bodies(text):
    """[(id, body)] for every data-id item. A second walk rather than a wider
    return from `consult_items`: that one answers the contract in booleans and
    is read by the failure path, and warnings must not be able to change it."""
    out = []
    for m in ITEM_OPEN.finditer(text):
        ident = next(g for g in m.groups()[1:] if g is not None)
        out.append((ident, _subtree(text, m.group(1), m.end())))
    return out


# --- the gallery row (Phase 1, 2026-09-22) -----------------------------------
# A `consult-gallery` item is one screen state seen in every tile the matrix
# declares. What makes it answerable is that the reader sees EVERY tile: a row
# missing its dark-mobile cell is a verdict given on three quarters of the
# evidence, and nothing else on the page says so — the item still has its
# options, its notes box and its stable id, so every rule that already exists
# passes it. The tiles are named by the enclosing block (`data-tiles`) rather
# than hard-coded here: the matrix belongs to the project that emits the rows,
# and a second copy of it in the checker would disagree with the first the day
# a viewport is added.
#
# The other half is the row that is not applicable at all (a state a screen
# cannot reach): it carries one `.gal-na` with the reason and no tiles. A row
# with BOTH claims both things at once, and a row with NEITHER is an item with
# nothing to look at.
GALLERY_CLASS = re.compile(r'\bclass\s*=\s*["\'][^"\']*\bconsult-gallery\b',
                           re.I)
ANY_OPEN_TAG = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*>', re.I | re.S)
GAL_FIGURE_OPEN = re.compile(r'<figure\b[^>]*>', re.I | re.S)
DATA_TILE = re.compile(r'\bdata-tile\s*=\s*'
                       r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))',
                       re.I | re.S)
FIGURE_TILE = re.compile(r'<figure\b[^>]*\bdata-tile\s*=\s*'
                         r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))[^>]*>',
                         re.I | re.S)
GAL_NA_OPEN = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*\bclass\s*=\s*["\'][^"\']*'
                         r'\bgal-na\b[^>]*>', re.I | re.S)
# `<gallery>-<cell>`: two or more lowercase slugs. An id of one word cannot name
# both halves, and a capital or an underscore is a hand-written id that the
# generator would never have produced.
GALLERY_ID = re.compile(r'^[a-z0-9]+(-[a-z0-9]+)+$')


def _subtree_closed(text, tag, start):
    """`_subtree`, but None when the element is never closed.

    `_subtree` answers an unclosed element with the REST of its container, which
    is the right answer when the question is "what is in this item" and the
    wrong one when it is "what does this element say". A `<p class="gal-na">`
    nobody closed then reads as a reason whose text is the verdict labels below
    it — a row with no reason and no tiles passing as not applicable.
    """
    op = re.compile(r'<' + re.escape(tag) + r'\b', re.I)
    cl = re.compile(r'</' + re.escape(tag) + r'\s*>', re.I)
    depth, pos = 1, start
    while depth:
        m_o, m_c = op.search(text, pos), cl.search(text, pos)
        if not m_c:
            return None
        if m_o and m_o.start() < m_c.start():
            depth, pos = depth + 1, m_o.end()
        else:
            depth, pos = depth - 1, m_c.end()
            if not depth:
                return text[start:m_c.start()]
    return ""


def _gal_grids(body):
    """Every `.gal` subtree in an item. The class is a TOKEN: `gal-na` is the
    not-applicable line, not an empty grid, and a substring test reads it as
    one."""
    out = []
    for m in ANY_OPEN_TAG.finditer(body):
        if "gal" in _class_tokens(m.group(0)):
            out.append(_subtree(body, m.group(1), m.end()))
    return out


def gallery_findings(text):
    """Every violation of the gallery-row shape, as plain messages.

    Judged against the ENCLOSING block's `data-tiles`, so the failure is about
    this page's own declared matrix. A gallery item with no such block is its
    own failure: without the declaration there is nothing to be complete
    against, and a silent pass there would empty the rule.

    What makes an item a gallery row is what it LOOKS like, never a class the
    author had to remember: `consult-gallery`, or a `.gal` grid, or any
    `<figure data-tile>`. The first version keyed on the class alone, and the
    rows that existed before the generator — five rounds of hand-written block E
    — carry the grid and not the class, so the whole battery went silent on
    precisely the markup it was written for.
    """
    # Comments first, as every other scan in this file does: a previous round's
    # row left commented out is not markup, and judging it fails the page it was
    # removed from.
    text = strip_html_comments(text)
    out = []
    groups = []                       # (body_start, body_end, tiles|None)
    for m in GROUP_OPEN.finditer(text):
        body = _subtree(text, m.group(1), m.end())
        # A `data-tiles` of nothing but spaces declares no matrix. It is not an
        # empty matrix: with `[]` every tile a row shows is "undeclared" and the
        # message names all four as the defect instead of the absent list.
        tiles = (_tag_attr(m.group(0), "data-tiles") or "").split() or None
        groups.append((m.end(), m.end() + len(body), tiles))

    for m in ITEM_OPEN.finditer(text):
        if GROUP_CLASS.search(m.group(0)):
            continue                  # a block is a context, never a row
        ident = next(g for g in m.groups()[1:] if g is not None)
        # A page may carry its own <style>, and components.css defines both
        # `.gal` and `.gal-na`: read the markup only, never a stylesheet that
        # would answer the check on behalf of a row that has no figures.
        body = strip_script_style(_subtree(text, m.group(1), m.end()))

        grids = _gal_grids(body)
        if not (GALLERY_CLASS.search(m.group(0)) or grids
                or FIGURE_TILE.search(body)):
            continue

        if not GALLERY_ID.match(ident):
            out.append(f"gallery item '{ident}' has an id that is not "
                       f"<gallery>-<cell> (two or more lowercase slugs joined "
                       f"by hyphens) — the row id is what keeps this cell "
                       f"answerable across rounds, and it is the project's "
                       f"gallery and cell names, never a serial number")

        # A figure in the grid with no `data-tile` is a cell nothing can place:
        # the reader counts four images and the matrix has three.
        # Scanned over the whole row, not only its `.gal` grids: a row admitted
        # by shape (tiles with no grid) has no grid to look inside.
        untiled = sum(1 for f in GAL_FIGURE_OPEN.finditer(body)
                      if not DATA_TILE.search(f.group(0)))
        if untiled:
            out.append(f"gallery item '{ident}' has {untiled} figure(s) "
                       f"with no data-tile — a tile nothing can "
                       f"place, so the reader counts more cells than the "
                       f"matrix has")

        # The innermost block containing this item: a block inside a block
        # would otherwise be judged by the outer one's matrix.
        enclosing = [g for g in groups if g[0] <= m.start() < g[1]]
        tiles = None
        if enclosing:
            tiles = min(enclosing, key=lambda g: g[1] - g[0])[2]
        if tiles is None:
            out.append(f"gallery item '{ident}' is not inside a "
                       f"<section class=\"consult-group\" data-tiles=\"…\"> — "
                       f"the block declares which tiles every row in it must "
                       f"show, and without it no reader and no check can tell "
                       f"a complete row from a truncated one")
            continue

        twice = sorted({t for t in tiles if tiles.count(t) > 1})
        if twice:
            out.append(f"gallery item '{ident}' sits in a block that declares "
                       f"tile(s) twice: {' '.join(twice)} — a repeated name "
                       f"counts as a cell no row can show, so a missing tile "
                       f"passes as present")
            continue
        # A row may declare its own `data-tiles` for ONE case only: a new
        # screen has no baseline, so in a `before after` block its row shows
        # `after` alone. Any other row-level list — a widening, a repeat, or
        # another subset — is a verdict on part of the row passed off as the
        # whole. Whitespace-only declares nothing (the block's list holds).
        own = (_tag_attr(m.group(0), "data-tiles") or "").split()
        if own and own != tiles:
            if own == ["after"] and sorted(tiles) == ["after", "before"]:
                tiles = own
            else:
                out.append(f"gallery item '{ident}' declares data-tiles="
                           f"\"{' '.join(own)}\" in a block of "
                           f"\"{' '.join(tiles)}\" — the only narrowing a row "
                           f"may make is a new screen: \"after\" alone in a "
                           f"\"before after\" block")
                continue
        found = [next(g for g in fm.groups() if g is not None).strip()
                 for fm in FIGURE_TILE.finditer(body)]
        reasons = []
        for nm in GAL_NA_OPEN.finditer(body):
            inner = _subtree_closed(body, nm.group(1), nm.end())
            # Unclosed is empty whatever text follows: in the browser that
            # element swallows the verdict and the notes, so the "reason" is
            # not the reason the author sees.
            reasons.append("" if inner is None else flatten(inner).strip())

        if found and reasons:
            out.append(f"gallery item '{ident}' carries both tiles and a "
                       f"not-applicable reason — a row is either shown in "
                       f"every tile or declared not applicable, never both")
            continue
        if not found and not reasons:
            out.append(f"gallery item '{ident}' has neither a tile nor a "
                       f"not-applicable reason — there is nothing for the "
                       f"reader to judge. Show the {len(tiles)} tile(s) "
                       f"({' '.join(tiles)}) as <figure data-tile=\"…\">, or "
                       f"state why the row does not apply in a "
                       f"<p class=\"gal-na\">")
            continue
        if reasons:
            if len(reasons) > 1:
                out.append(f"gallery item '{ident}' carries {len(reasons)} "
                           f"gal-na reasons — a row is not applicable for one "
                           f"reason")
            elif not reasons[0]:
                out.append(f"gallery item '{ident}' has an empty gal-na — the "
                           f"reason a row does not apply is the whole content "
                           f"of that row (an unclosed <p> is an empty one: the "
                           f"text after it belongs to whatever follows)")
            continue

        unknown = [t for t in found if t not in tiles]
        if unknown:
            out.append(f"gallery item '{ident}' shows tile(s) its matrix does "
                       f"not declare: {' '.join(sorted(set(unknown)))} "
                       f"(declared: {' '.join(tiles)}) — a tile outside the "
                       f"matrix is a cell no other row has, so the rows stop "
                       f"being comparable")
        dupes = sorted({t for t in found if found.count(t) > 1})
        if dupes:
            out.append(f"gallery item '{ident}' shows tile(s) twice: "
                       f"{' '.join(dupes)} — one row, one figure per tile")
        missing = [t for t in tiles if t not in found]
        if missing:
            out.append(f"gallery item '{ident}' is missing tile(s) "
                       f"{' '.join(missing)} — the block declares "
                       f"{' '.join(tiles)}, and a verdict given on part of "
                       f"the matrix reads as a verdict on all of it")
    return out


def marks_outside_opts(body):
    """True when the item holds a radio/checkbox with no `.opts` ancestor.

    Walked with an ancestor stack, not grepped for `.opts` anywhere in the item:
    the observed page had one group correctly wrapped and a second one in a
    hand-invented `consult-options`, and any presence test passes that."""
    body = strip_html_comments(strip_script_style(body))
    stack = []
    for m in re.finditer(r"<(/?)([a-zA-Z][\w:-]*)([^>]*)>", body):
        closing, tag, attrs = m.group(1), m.group(2).lower(), m.group(3)
        if closing:
            for i in range(len(stack) - 1, -1, -1):
                if stack[i][0] == tag:
                    del stack[i:]
                    break
            continue
        if tag == "input" and MARK_INPUT.match(m.group(0)):
            if not any("opts" in anc for _, anc in stack):
                return True
        if tag in VOID_TAGS or attrs.rstrip().endswith("/"):
            continue
        cm = ATTR_CLASS.search(attrs)
        classes = (set(next(g for g in cm.groups() if g is not None).split())
                   if cm else set())
        stack.append((tag, classes))
    return False


DATA_LABEL = re.compile(r'\bdata-label\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27)',
                        re.I | re.S)
# The two spellings the field produced, plus the negative form the same page
# needed. Bounded on purpose: this warns about a marker typed into the copied
# label, and a wider net would fire on an option legitimately CALLED
# "recommended" in its own text.
REC_IN_LABEL = re.compile(r'\(\s*(?:not\s+)?(?:recommended|recomendad[ao]|no\s+'
                          r'recomendad[ao])\s*\)', re.I)


# The facts-in-a-paragraph shape (BL-270). Counted, not weighed: a word count is
# the proxy BL-243 rejected, and both incidents — twelve skills with counts and
# verdicts (G3), ~20 skills split across three layers (Q15) — were paragraphs
# dense in `<code>` tokens or `;`-joined clauses, which an explanatory paragraph
# is not. Scanned on the innermost owner only, so a paragraph in an item is
# reported once, under the item, never again under its block.
FACTS_MIN = 4
P_BLOCK = re.compile(r'<p\b([^>]*)>(.*?)</p>', re.I | re.S)
P_FIELDLABEL = re.compile(r'\bclass\s*=\s*["\x27][^"\x27]*\bfieldlabel\b', re.I)


def facts_paragraphs(body):
    """[(codes, clauses, excerpt)] for every paragraph of `body` that carries
    FACTS_MIN or more semicolon-separated clauses only by counting those inside
    <code>: every other dense paragraph is mixed-content-types' FAIL."""
    own = _strip_subtrees(strip_html_comments(strip_script_style(body)), ITEM_OPEN)
    out = []
    for m in P_BLOCK.finditer(own):
        if P_FIELDLABEL.search(m.group(1)):
            continue
        inner = m.group(2)
        codes = len(re.findall(r'<code\b', inner, re.I))
        # BL-324: on the DECODED text. `;` is the clause separator and it is
        # also the last character of every character entity, so a Spanish page
        # written with `&iacute;` read as prose it never contained: one
        # paragraph with a single real semicolon and five accents was reported
        # as seven clauses, and twelve warnings fired on a page whose English
        # original fired none. Rewriting the accents as literal UTF-8 cleared
        # all twelve without touching a sentence — the check was measuring the
        # encoding. Tags are stripped first, or an attribute's own `;` counts.
        prose = _html.unescape(re.sub(r'<[^>]+>', ' ', inner))
        clauses = prose.count(';') + 1 if ';' in prose else 1
        # contract_defects' mixed-content-types FAILS the same paragraph when
        # it has FACTS_MIN <code> tokens or clauses counted OUTSIDE <code>;
        # that one owns it (LOOP-006). What is left here is the shape only this
        # warning counts: semicolons inside <code>.
        bare = _html.unescape(re.sub(r'<[^>]+>', ' ', re.sub(
            r'<code\b[^>]*>.*?</code\s*>', ' ', inner, flags=re.I | re.S)))
        if codes >= FACTS_MIN or bare.count(';') + 1 >= FACTS_MIN:
            continue
        if clauses >= FACTS_MIN:
            excerpt = ' '.join(prose.split())
            out.append((codes, clauses, excerpt[:60]))
    return out


# The item-before-its-evidence shape (BL-463). §8.4 orders a unit as evidence ->
# question, so evidence BETWEEN two items is the next item's and reads right;
# only evidence left after a block's LAST item has no question below it. That is
# the one position a checker can judge without guessing which item a video is
# for. Read on the built HTML, where every block has already become markup; a
# `@@VIDEO` marker paragraph counts because a project's post-build step turns it
# into <video> after this check has run (codefilm round 4, 2026-09-25).
EVIDENCE_TAGS = {"figure", "img", "svg", "video", "table", "canvas"}
EVIDENCE_INSIDE = re.compile(r'<(?:figure|img|svg|video|table|canvas)\b', re.I)
VIDEO_MARKER = re.compile(r'^\s*@@VIDEO\b')


def trailing_evidence(text):
    """[(group_id, item_id, evidence_tag)] for every block whose last item is
    followed, before the block ends, by a figure, img, svg, video, table,
    canvas or `@@VIDEO` paragraph."""
    out = []
    for g in GROUP_OPEN.finditer(text):
        body = strip_html_comments(strip_script_style(_subtree(text, g.group(1), g.end())))
        last, after = None, None
        for tag, open_tag, inner in _child_nodes(body):
            if tag is None:
                continue
            m = None
            for m in ITEM_OPEN.finditer(open_tag + inner):
                pass
            if m:
                last, after = next(x for x in m.groups()[1:] if x is not None), None
            elif last and after is None:
                t = tag.lower()
                # A paragraph is evidence only as a video marker: an inline
                # icon or legend swatch inside prose is decoration.
                if t == "p":
                    if VIDEO_MARKER.match(inner):
                        after = "@@VIDEO"
                elif t in EVIDENCE_TAGS or EVIDENCE_INSIDE.search(inner):
                    after = t
        if last and after:
            gid = _tag_attr(g.group(0), "data-id") or _tag_attr(g.group(0), "id") or "?"
            out.append((gid, last, after))
    return out


# --- svg-text: label geometry estimated from viewBox coordinates (BL-310) ------
# Per-character advance as a fraction of font-size, calibrated on 2026-09-03
# against getBBox() of 52 labels in system-ui: digits and capitals ~0.6, the
# narrow glyphs ~0.3, everything else ~0.52. A single 0.55 constant reported a
# 26 px gap as a 13 px collision; the table lands within ±5 % of the rendering.
# BL-411 (2026-09-14, 12 Spanish labels at 10.5-12 px in Chrome): r, t and f
# at 0.3 put the estimate 8 % under the browser (-11.7 % worst); at 0.45 the
# mean error is -3.3 %, inside the ±5 % the message claims.
SVG_TAG = re.compile(r'<(/?)([a-zA-Z][\w:-]*)([^>]*?)(/?)>', re.S)
SVG_ATTR = re.compile(r'([\w:-]+)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))')
SVG_BLOCK = re.compile(r'<svg\b([^>]*)>(.*?)</svg>', re.S | re.I)
SVG_NARROW = set("iljI.,:;'|!()[] ")
SVG_MID = set("rtf")       # 0.45: narrower than a lowercase letter, wider than an i
SVG_WIDE = set("mwMW@")
# A container whose children ARE placed on the canvas: geometry and inherited
# presentation flow through it. SVG_TEMPLATES is the other kind — its children
# are a stencil the renderer instantiates somewhere else (or not at all), so a
# rect inside one is never a label's background. BL-346: D2 and Graphviz put a
# knockout rect inside <mask> under every edge label so the edge line does not
# run through the glyphs; reading those as painted reported 36 labels at 4.02:1
# against black on the route bench page, 11 of them legible in the browser.
# `defs` was the only one skipped. Names are lowercase: `tag` is lowered when
# it is parsed, so `clipPath` never matches as written in the markup.
SVG_TEMPLATES = ('defs', 'mask', 'clippath', 'pattern', 'symbol', 'marker')
SVG_CONTAINERS = ('g', 'a', 'switch') + SVG_TEMPLATES
SVG_UNPLACEABLE = re.compile(r'rotate|matrix|scale|skew', re.I)
SVG_CSS_RULE = re.compile(r'([^{}]+)\{([^{}]*)\}', re.S)
SVG_CSS_SIZE = re.compile(r'font(?:-size)?\s*:\s*(?:[\w-]+\s+)*?(\d*\.?\d+)px', re.I)
SVG_CSS_MONO = re.compile(r'font(?:-family)?\s*:[^;]*mono', re.I)
SVG_CSS_BOLD = re.compile(r'font(?:-weight)?\s*:\s*(?:bold|[6-9]00)\b', re.I)
SVG_SLACK = 4.0            # absolute floor, plus a share of the label width:
SVG_ERR = 0.06             # the estimate is ±5 %, so a 250 px label carries
                           # ~15 px of noise and a smaller finding is not one


def _svg_attrs(s):
    return {m.group(1).lower(): next(g for g in m.groups()[1:] if g is not None)
            for m in SVG_ATTR.finditer(s)}


def _svg_num(v, default):
    m = re.match(r'\s*(-?\d*\.?\d+)', v or '')
    return float(m.group(1)) if m else default


def _svg_translate(transform):
    m = re.search(r'translate\(\s*(-?[\d.]+)[\s,]*(-?[\d.]+)?', transform or '')
    return (float(m.group(1)), float(m.group(2) or 0)) if m else (0.0, 0.0)


def strip_css_comments(css):
    """CSS source with `/* ... */` removed.

    BL-357: SVG_CSS_RULE's selector group swallows everything since the previous
    `}`, so a comment sitting in front of a selector travels WITH it. `/*` fails
    SVG_COMPOUND, the selector does not parse, and the WHOLE rule is discarded —
    the suppressing direction: the label keeps what it inherits and a genuine
    contrast failure goes unreported. A comment is not a selector, so removing it
    is not widening the parser. `svg_css_fonts` already did this inline; every
    reader of SVG_CSS_RULE needs it."""
    return re.sub(r'/\*.*?\*/', '', css, flags=re.S)


def svg_css_fonts(text):
    """{'.cls': (size|None, bold, mono), 'text': ...} from every <style>
    block. Pages set label sizes in CSS classes at least as often as in
    attributes, and a class read as 16 px reported 10 px labels colliding."""
    fonts = {}
    for style in re.findall(r'<style\b[^>]*>(.*?)</style>', text, re.S | re.I):
        style = strip_css_comments(style)
        for sel, body in SVG_CSS_RULE.findall(style):
            m = SVG_CSS_SIZE.search(body)
            size = float(m.group(1)) if m else None
            bold, mono = bool(SVG_CSS_BOLD.search(body)), bool(SVG_CSS_MONO.search(body))
            if size is None and not bold and not mono:
                continue
            for s in sel.split(','):
                s = s.strip()
                key = None
                cm = re.search(r'\.([\w-]+)\s*$', s)
                if cm:
                    key = '.' + cm.group(1)
                elif re.search(r'(^|\s)(svg\s+)?text\s*$', s):
                    key = 'text'
                if key is None:
                    continue
                old = fonts.get(key, (None, False, False))
                fonts[key] = (size if size is not None else old[0],
                              bold or old[1], mono or old[2])
    return fonts


def svg_text_width(label, size, bold=False, mono=False):
    if mono:
        return 0.6 * size * len(label)
    w = 0.0
    for ch in label:
        if ch in SVG_NARROW:
            w += 0.3
        elif ch in SVG_MID:
            w += 0.45
        elif ch in SVG_WIDE:
            w += 0.85
        elif ch.isdigit() or ch.isupper():
            w += 0.6
        else:
            w += 0.52
    return w * size * (1.04 if bold else 1.0)


def svg_geometry(svg, fonts=None, rules=None, root=None):
    """(texts, rects) for one <svg> body. texts: [(label, x0, y0, x1, y1, fill)]
    for every placeable <text>; rects: [(x0, y0, x1, y1, fill)]. Inherits
    font-size, text-anchor, font-weight, fill and translate() through the
    container stack; a class rule from `fonts` fills what attributes leave
    unset. A label whose size no attribute or rule states is skipped, not
    guessed at 16 px — that guess was the false-positive source.

    `fill` is a literal colour or None (unset, `currentColor`, a gradient url,
    a var()) — never a guess. BL-330: the contrast check refuses to invent the
    half of a pair it cannot read, and counts those separately."""
    fonts = fonts or {}
    rules = rules or []
    fs, anchor, tx, ty, skip, bold = None, 'start', 0.0, 0.0, False, False
    mono = False
    fill = None
    stack, texts, rects, cur = [], [], [], None
    # BL-347: what a label is painted with is declared on the node carrying the
    # GLYPHS. Mermaid's sequenceDiagram puts the actor name in a <tspan> and
    # paints it `text.actor>tspan{fill:#333}`, while `.actor{fill:#eee}` on the
    # enclosing <text> is there for the actor RECT — reading the <text> reported
    # all 10 actor labels on the route bench page at 1.04:1 where the browser
    # measures 0 of 20 failing. `tsp` is the open-tspan stack, `glyph_fills` the
    # distinct effective fills of the runs that actually carry glyphs, and
    # `bare` the text sitting directly in the <text>. A merged label whose runs
    # disagree resolves to SVG_UNREADABLE: it has no single colour to measure,
    # and inventing one is what this whole check refuses to do.
    tsp, glyph_fills, bare, last = [], set(), [], 0
    # BL-348: a fill rule is matched against the node's ANCESTOR CHAIN, so the
    # chain has to exist. `anc` is [(tag, classes)] for every open container,
    # pushed and popped exactly where the inherited-style stack is.
    # BL-358: the chain starts at the <svg> ROOT, which is not in the body this
    # function walks. Without it a compound naming the root — `svg text`, or
    # the `.d2-<hash> .fill-N1` that d2 and mermaid actually emit — parses fine
    # and then matches nothing. `root` is the caller's (tag, classes) for that
    # element; `anc_base` is the floor a close tag may never pop past.
    anc = [root] if root else []
    anc_base = len(anc)
    # BL-355: what the ROOT is painted with is inherited by everything under it,
    # so it is the figure's starting fill — not something matched on the label.
    if root:
        fill = svg_fill_for(rules, [root])
    for m in SVG_TAG.finditer(svg):
        closing, tag, raw, selfclosed = m.group(1), m.group(2).lower(), m.group(3), m.group(4)
        if cur is not None:
            if tag == 'tspan' and not closing and not selfclosed:
                if not tsp:
                    bare.append(svg[last:m.start()])
                # BL-353: what an inner run INHERITS is the nearest enclosing
                # run that declares a fill, not the <text> two levels up. The
                # effective fill is resolved at push time, so the fallback is
                # already in place for whatever nests inside it. Declaring
                # nothing anywhere still lands on the <text> (`cur[8]`).
                _tfl = _svg_tspan_fill(_svg_attrs(raw), cur[9], rules)
                if _tfl is None and tsp:
                    _tfl = tsp[-1][1]
                tsp.append((m.end(), _tfl))
            elif tag == 'tspan' and closing and tsp:
                st, tfl = tsp.pop()
                if re.sub(r'<[^>]+>', ' ', svg[st:m.start()]).strip():
                    glyph_fills.add(cur[8] if tfl is None else tfl)
                if not tsp:
                    last = m.end()
            elif closing and tag == 'text':
                start, f, an, x, y, sk, b, mo, fl, _chain = cur
                label = ' '.join(_html.unescape(
                    re.sub(r'<[^>]+>', ' ', svg[start:m.start()])).split())
                bare.append(svg[last:m.start()])
                if re.sub(r'<[^>]+>', ' ', ''.join(bare)).strip():
                    glyph_fills.add(fl)
                if glyph_fills:
                    fl = (next(iter(glyph_fills)) if len(glyph_fills) == 1
                          else SVG_UNREADABLE)
                cur, tsp, glyph_fills, bare = None, [], set(), []
                if label and not sk and f is not None:
                    w = svg_text_width(label, f, b, mo)
                    x0 = {'middle': x - w / 2, 'end': x - w}.get(an, x)
                    texts.append((label, x0, y - 0.8 * f, x0 + w, y + 0.25 * f, fl))
            continue
        if closing:
            if tag in SVG_CONTAINERS and stack:
                fs, anchor, tx, ty, skip, bold, mono, fill = stack.pop()
                if len(anc) > anc_base:
                    anc.pop()
            continue
        d = _svg_attrs(raw)
        # attribute beats class rule beats inherited; `text` element rule
        # is the page-wide floor for a bare <text>
        nfs, nb, nmo = fs, bold, mono
        for cls in d.get('class', '').split():
            csize, cbold, cmono = fonts.get('.' + cls, (None, False, False))
            nfs = csize if csize is not None else nfs
            nb, nmo = nb or cbold, nmo or cmono
        if tag == 'text' and nfs is None:
            nfs = fonts.get('text', (None, False, False))[0]
        # Cascade, weakest first: an element rule, then a class rule, then the
        # element's own attribute. SVG_UNREADABLE is a DECLARATION we cannot
        # read (currentColor, a var(), a gradient) and it overrides an inherited
        # colour rather than falling through to it. The bench page's lead figure
        # declares `fill:currentColor` on its label classes; treating that as
        # "unset" let it inherit a leaked literal and read as measured, which
        # reported 31 findings on the one figure that was already correct.
        chain = anc + [(tag, tuple(d.get('class', '').split()))]
        nfl = fill
        rule_fill = svg_fill_for(rules, chain)
        if rule_fill is not None:
            nfl = rule_fill
        raw_fill = _svg_style_prop(d.get('style'), 'fill') or d.get('fill')
        if raw_fill:
            nfl = svg_literal_colour(raw_fill) or SVG_UNREADABLE
        nfs = _svg_num(d.get('font-size'), nfs)
        nan = d.get('text-anchor', anchor)
        dx, dy = _svg_translate(d.get('transform'))
        nsk = skip or tag in SVG_TEMPLATES or bool(SVG_UNPLACEABLE.search(d.get('transform', '')))
        nb = nb or d.get('font-weight', '') in ('bold', 'bolder', '600', '700', '800', '900')
        nmo = nmo or 'mono' in d.get('font-family', '').lower()
        if tag == 'text' and not selfclosed:
            cur = (m.end(), nfs, nan,
                   _svg_num(d.get('x'), 0.0) + tx + dx,
                   _svg_num(d.get('y'), 0.0) + ty + dy, nsk, nb, nmo, nfl,
                   chain)
            tsp, glyph_fills, bare, last = [], set(), [], m.end()
        elif tag == 'rect' and not nsk:
            rx, ry = _svg_num(d.get('x'), 0.0) + tx + dx, _svg_num(d.get('y'), 0.0) + ty + dy
            rects.append((rx, ry, rx + _svg_num(d.get('width'), 0.0),
                          ry + _svg_num(d.get('height'), 0.0), nfl))
        elif tag in SVG_CONTAINERS and not selfclosed:
            stack.append((fs, anchor, tx, ty, skip, bold, mono, fill))
            anc.append(chain[-1])
            fs, anchor, tx, ty, skip, bold, mono, fill = nfs, nan, tx + dx, ty + dy, nsk, nb, nmo, nfl
    return texts, rects


# --- svg-scope / svg-contrast: the <style> that leaks, and the colour nobody
# --- measured (BL-330) --------------------------------------------------------
#
# An `<svg>`'s `<style>` is NOT scoped to that SVG. It is a stylesheet in the
# document, so a bare `text { fill: #1F2937 }` inside one figure paints every
# `<text>` on the page, last one in the cascade winning. Reported by the owner
# on a bench page carrying 26 figures: the lead figure measured 1.15:1 in dark
# and every gate was green, because the contract read geometry and never colour.
#
# `svg-scope` is a warning; `svg-contrast` is a failure at the wrap and a warning
# in the census (v15, and see CENSUS_ADVISORY). Both are static. Contrast is computed only for
# pairs where BOTH sides are literal colours; anything resolved through
# `currentColor`, a gradient, a `var()` or a CSS file the figure does not carry
# is counted as unmeasured and SAID SO. A checker that quietly measured nothing
# is green and indistinguishable from one that passed — the whole reason this
# defect survived three gates.
SVG_STYLE_BLOCK = re.compile(r'<style\b[^>]*>(.*?)</style>', re.S | re.I)
SVG_PAINTED = ('text', 'tspan', 'rect', 'circle', 'ellipse', 'line', 'path',
               'polygon', 'polyline', 'g', 'svg', 'marker', 'image', 'use')
# BL-367: a class-headed descendant rule (`.note text`) is a document stylesheet
# exactly like `text` is, but two shapes of it are not the author's to scope. A root
# class carrying a generator hash (d2's `.d2-<digits>`, mermaid's `.mermaid-<n>`) is
# de-facto scoping; generator class vocabulary (graphviz `.node`/`.edge`/`.cluster`,
# mermaid's actor/message/label family) is pasted output. Measured 2026-09-08 over
# every page in .context/: widening naively adds 648 warnings, these two leave 8.
SVG_HASH_CLASS = re.compile(r'^\.(?:d2-\d+|mermaid-\d+|[A-Za-z][\w-]*-\d{6,})$')
SVG_GENERATOR_CLASSES = frozenset((
    'node', 'edge', 'cluster', 'graph',                                   # graphviz
    'actor', 'actor-line', 'messageText', 'messageLine0', 'messageLine1',  # mermaid
    'loopText', 'loopLine', 'noteText', 'note', 'activation0', 'activation1',
    'sequenceNumber', 'labelBox', 'labelText', 'label', 'edgeLabel', 'edgePath',
    'flowchart-link', 'nodeLabel', 'cluster-label', 'marker', 'arrowheadPath',
    'statediagram-state', 'statediagram-cluster', 'stateGroup', 'transition',
    'legend', 'section', 'task', 'grid', 'tick', 'today',
))
SVG_HEX = re.compile(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$')
SVG_RGB = re.compile(r'^rgba?\(\s*(\d+)\s*[, ]\s*(\d+)\s*[, ]\s*(\d+)', re.I)
SVG_NAMED = {'white': '#ffffff', 'black': '#000000', 'red': '#ff0000',
             'green': '#008000', 'blue': '#0000ff', 'grey': '#808080',
             'gray': '#808080'}
# The kit's own ground, per theme, and the fallback when a page carries no
# token: a figure is judged against what it is actually painted on.
SVG_GROUND_FALLBACK = {'light': '#F3F5F1', 'dark': '#131614'}
SVG_CONTRAST_FLOOR = 4.5
# A fill that IS declared and cannot be read: currentColor, a var(), a gradient
# url. Distinct from None (never declared) because it overrides inheritance.
SVG_UNREADABLE = '?'


def _svg_style_prop(style, prop):
    """One declaration out of a `style="…"` attribute."""
    for decl in (style or '').split(';'):
        k, _, v = decl.partition(':')
        if k.strip().lower() == prop:
            return v.strip()
    return None


def svg_literal_colour(v):
    """An sRGB triple for a colour we can actually read, else None. `none`,
    `currentColor`, `url(#grad)` and `var(--x)` are all None ON PURPOSE: the
    contrast check must not invent the half of a pair it cannot see."""
    if not v:
        return None
    # A CSS declaration may end in `!important`: priority, not part of the colour.
    v = re.sub(r'\s*!\s*important\s*$', '', v.strip(), flags=re.I).strip('"\'')
    low = v.lower()
    if low in SVG_NAMED:
        v = SVG_NAMED[low]
    m = SVG_HEX.match(v)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = ''.join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    m = SVG_RGB.match(v)
    if m:
        return tuple(min(255, int(g)) for g in m.groups())
    m = SVG_OKLCH.match(v)
    if m:
        return _oklch_to_srgb(*m.groups())
    return None


# oklch(L C H [/ A]): a literal colour like hex, so a box painted with it is a
# background the label is judged against (LOOP-006). Unread, the box was skipped
# and its label judged against the page ground instead: a false FAIL. Alpha is
# ignored, as it is for rgba(); `none` reads as 0, as CSS says.
_NUM = r'(?:\d+(?:\.\d*)?|\.\d+)'    # a CSS number: never "0.5." nor "."
SVG_OKLCH = re.compile(
    r'^oklch\(\s*(none|' + _NUM + r'%?)[\s,]+(none|' + _NUM + r'%?)[\s,]+'
    r'(none|' + _NUM + r')(deg|rad|grad|turn)?\s*(?:/\s*(?:none|' + _NUM
    + r'%?)\s*)?\)$', re.I)
_HUE_UNIT = {'deg': 1.0, 'grad': 0.9, 'rad': 180 / 3.141592653589793, 'turn': 360.0}


def _oklch_to_srgb(L, C, H, unit):
    """CSS Color 4: OKLCH -> OKLab -> linear sRGB -> sRGB, clipped per channel
    the way Chromium paints an out-of-gamut colour."""
    import math

    def num(s, pct_scale):
        if s.lower() == 'none':
            return 0.0
        return float(s[:-1]) / 100 * pct_scale if s.endswith('%') else float(s)
    lig, chroma = min(1.0, num(L, 1.0)), num(C, 0.4)      # CSS clamps L to [0, 1]
    hue = math.radians(num(H, 0) * _HUE_UNIT[(unit or 'deg').lower()])
    a, b = chroma * math.cos(hue), chroma * math.sin(hue)
    l_ = (lig + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m_ = (lig - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s_ = (lig - 0.0894841775 * a - 1.2914855480 * b) ** 3
    lin = (4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_,
           -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_,
           -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_)

    def enc(x):
        x = min(1.0, max(0.0, x))
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    return tuple(round(enc(x) * 255) for x in lin)


# --- svg-embed: what a figure FILE may carry into a page ----------------------
# The rules a spec's `::: figure` block applies to an .svg before inlining it
# (spec_build.py imports this; it keeps no copy). Not a per-page check: a page
# already on disk is judged by the checks above, and the originals of the spec
# corpus are measured against these rules, not failed by them.
#
# An ALLOWLIST over a real parse, not a denylist over a scan. The file is parsed
# as strict XML (`xml.etree`); what does not parse is refused, and so is any
# element or attribute not named below. The page then gets the PARSED TREE,
# re-serialised with every text node and value escaped — never a slice of the
# source — so the browser's HTML parser reads exactly the elements checked here
# and no construct can mean one thing to this parser and another to it. The
# denylist it replaced let `<a>`, `<base>`, `<form>`, `href="data:text/html…"`
# and a namespaced `x:href` through, each a road out of the figure.
#
# Paint is refused as a hex literal or a colour FUNCTION (rgb, hsl, hwb, lab,
# lch, oklab, oklch, color). A named colour (`white`) is just as fixed and is
# not refused here: the rule is the figure-kit's, and widening it is a
# decision, not a fix.
SVG_NS = 'http://www.w3.org/2000/svg'
SVG_XLINK_NS = 'http://www.w3.org/1999/xlink'
SVG_XML_NS = 'http://www.w3.org/XML/1998/namespace'
SVG_EMBED_ELEMENTS = frozenset((
    'svg', 'g', 'defs', 'title', 'desc', 'rect', 'circle', 'ellipse', 'line',
    'polyline', 'polygon', 'path', 'text', 'tspan', 'marker', 'use', 'symbol',
    'clipPath', 'mask', 'linearGradient', 'radialGradient', 'stop', 'pattern',
    'style'))
SVG_EMBED_ATTRS = frozenset((
    # identity, structure, accessibility
    'id', 'class', 'style', 'lang', 'role', 'aria-label', 'aria-labelledby',
    'aria-describedby', 'aria-hidden', 'focusable', 'version', 'type', 'media',
    # geometry and coordinate systems
    'viewBox', 'preserveAspectRatio', 'width', 'height', 'x', 'y', 'x1', 'y1',
    'x2', 'y2', 'cx', 'cy', 'r', 'rx', 'ry', 'fx', 'fy', 'fr', 'd', 'points',
    'pathLength', 'transform', 'dx', 'dy', 'rotate', 'textLength',
    'lengthAdjust',
    # markers, clipping, masks, gradients, patterns
    'marker-start', 'marker-mid', 'marker-end', 'markerWidth', 'markerHeight',
    'markerUnits', 'refX', 'refY', 'orient', 'clip-path', 'clip-rule',
    'clipPathUnits', 'mask', 'maskUnits', 'maskContentUnits', 'gradientUnits',
    'gradientTransform', 'spreadMethod', 'offset', 'stop-color', 'stop-opacity',
    'patternUnits', 'patternContentUnits', 'patternTransform',
    # presentation
    'fill', 'fill-opacity', 'fill-rule', 'stroke', 'stroke-width',
    'stroke-opacity', 'stroke-dasharray', 'stroke-dashoffset',
    'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'opacity',
    'color', 'display', 'visibility', 'overflow', 'vector-effect',
    'shape-rendering', 'text-rendering', 'paint-order',
    # text
    'font-family', 'font-size', 'font-weight', 'font-style', 'font-variant',
    'text-anchor', 'dominant-baseline', 'alignment-baseline', 'baseline-shift',
    'letter-spacing', 'word-spacing', 'text-decoration', 'white-space',
    # references: a #fragment of this file and nothing else (checked below)
    'href'))
SVG_EMBED_PAINT = re.compile(
    r'^\s*(#[0-9a-fA-F]{3,8}\b|(?:rgba?|hsla?|hwb|oklch|oklab|lab|lch|color)\()',
    re.I)
SVG_EMBED_DECL = re.compile(r'(?:^|[;{\s])(fill|stroke)\s*:\s*([^;}]+)', re.I)
SVG_EMBED_URL_OK = re.compile(r'url\(#[A-Za-z_][\w.-]*\)', re.I)
SVG_EMBED_URL_REF = re.compile(r'url\(#([A-Za-z_][\w.-]*)\)', re.I)
# Attributes whose value is a space-separated list of ids (BL-452).
SVG_EMBED_ID_LISTS = ('aria-labelledby', 'aria-describedby')
SVG_EMBED_FUNC = re.compile(r'([A-Za-z_-][\w-]*)?\(')
# The CSS functions a figure's styles may call: custom properties and
# arithmetic, colours, transforms — and `url()`, only as exactly `url(#id)`.
# Anything else (`image-set()`, `image()`, `cross-fade()`, `element()`, …) may
# fetch or reference something, so it is refused rather than searched.
SVG_EMBED_CSS_FUNCS = frozenset((
    'var', 'calc', 'min', 'max', 'clamp', 'rgb', 'rgba', 'hsl', 'hsla', 'hwb',
    'lab', 'lch', 'oklab', 'oklch', 'color', 'translate', 'translatex',
    'translatey', 'rotate', 'scale', 'scalex', 'scaley', 'matrix', 'skewx',
    'skewy', 'url'))
SVG_EMBED_CSS_WORDS = ('javascript:', 'expression', 'behavior', '-moz-binding')
SVG_EMBED_ENTITY = re.compile(r'&([A-Za-z][A-Za-z0-9]*);')
SVG_EMBED_XML_ENTITIES = ('amp', 'lt', 'gt', 'quot', 'apos')


def _svg_embed_urls(text, where):
    """A `url(` that is not exactly `url(#id)` — no quotes, no spaces."""
    return [f"{where} {text[m.start():m.start() + 40]!r} — only url(#id), "
            f"exactly; anything else is an external reference or hides one"
            for m in re.finditer(r'url\(', text, re.I)
            if not SVG_EMBED_URL_OK.match(text, m.start())]


# Third security pass: CSS in a figure is an ALLOWLIST, and it is scoped. A
# <style> inside an inline <svg> is a stylesheet of the whole DOCUMENT, and
# `position:fixed` lifts the drawing out of its <figure> — both confirmed in
# headless Chrome (a figure repainted <body> and hid the page's <h1>). So a
# figure may style only paint and text, only with type/.class/#id compounds
# joined by a descendant or `>` combinator, and every selector is rewritten
# under its own root, `svg[data-embed="<key>"] <selector>`, so no rule can
# match outside the figure that carries it.
SVG_EMBED_CSS_PROPS = frozenset((
    'fill', 'fill-opacity', 'fill-rule', 'stroke', 'opacity', 'font-family',
    'font-size', 'font-weight', 'font-style', 'font-variant', 'text-anchor',
    'dominant-baseline', 'letter-spacing', 'text-decoration', 'paint-order',
    'vector-effect', 'visibility'))
SVG_EMBED_CSS_PROP_PREFIXES = ('stroke-', 'marker-')
SVG_EMBED_COMPOUND = re.compile(r'(?:[A-Za-z][\w-]*)?(?:[.#][A-Za-z_-][\w-]*)*')
SVG_EMBED_RULES = re.compile(r'(?:\s*[^{}]+\{[^{}]*\})*\s*')
# Presentation attributes the ROOT <svg> may not carry: each moves or unclips
# the drawing relative to the page around it.
SVG_EMBED_ROOT_REFUSED = ('transform', 'overflow', 'display')


def _svg_embed_prop_ok(prop):
    return (prop in SVG_EMBED_CSS_PROPS
            or prop.startswith(SVG_EMBED_CSS_PROP_PREFIXES))


def _svg_embed_decls(body, where):
    """`(violations, "prop:value;…")` for one declaration block."""
    out, kept = [], []
    for decl in body.split(';'):
        if not decl.strip():
            continue
        prop, colon, val = decl.partition(':')
        prop, val = prop.strip().lower(), val.strip()
        if not colon or not prop or not val:
            out.append(f"{where} {decl.strip()!r} is not a declaration")
            continue
        if not _svg_embed_prop_ok(prop):
            out.append(f"{where} {prop} — a figure's CSS sets paint and text "
                       f"only")
            continue
        if prop in ('fill', 'stroke') and SVG_EMBED_PAINT.match(val):
            out.append(f"{where} {{{prop}: {val}}} — a literal colour; use "
                       f"currentColor or a kit class")
            continue
        kept.append(f"{prop}:{val}")
    return out, ';'.join(kept)


def _svg_embed_selector(sel):
    """The selector, whitespace-normalised, or None when it is outside the
    grammar: compounds of type, .class and #id, joined by ' ' or '>'."""
    parts = re.split(r'\s*>\s*|\s+', sel.strip())
    if not sel.strip() or any(
            not p or not SVG_EMBED_COMPOUND.fullmatch(p)
            or re.match(r'(html|body)\b', p, re.I) for p in parts):
        return None
    return ' '.join(sel.split())


def _svg_embed_css(css, where, rules, key=None, root_id=None):
    """`(violations, css_out)` for CSS a figure carries — its <style>
    (`rules`) or a `style=""` value. `css_out` is what the page gets: the
    declarations that were checked, and (with `key`) every selector scoped
    under `svg[data-embed="key"]`. A selector whose first compound is the
    root itself (`svg`, or `#root_id`) joins that scope as one compound: the
    root is not its own descendant.

    First refused by SHAPE (second security pass): a backslash (a CSS escape
    can spell anything), an unclosed comment, any @-rule, `</`, a function not
    in SVG_EMBED_CSS_FUNCS, `url(` that is not exactly `url(#id)`, the words in
    SVG_EMBED_CSS_WORDS. Then by the property and selector allowlists."""
    if '\\' in css:
        return [f"{where} a backslash — a CSS escape can spell anything, so "
                f"figure CSS carries none"], ''
    out = []
    if '</' in css:
        out.append(f"{where} '</' — markup inside CSS")
    body = re.sub(r'/\*.*?\*/', ' ', css, flags=re.S)
    if '/*' in body:
        out.append(f"{where} an unclosed comment")
        body = body[:body.index('/*')]
    out += [f"{where} {kw} — an @-rule; figure CSS is plain rules"
            for kw in re.findall(r'@[\w-]*', body)]
    low = body.lower()
    out += [f"{where} {w} — CSS that loads or runs something"
            for w in SVG_EMBED_CSS_WORDS if w in low]
    for m in SVG_EMBED_FUNC.finditer(body):
        name = (m.group(1) or '').lower()
        if name and name != 'url' and name not in SVG_EMBED_CSS_FUNCS:
            out.append(f"{where} {name}( — a CSS function a figure may not call")
    out += _svg_embed_urls(body, where)
    if out:
        return out, ''
    if not rules:
        return _svg_embed_decls(body, where)
    if not SVG_EMBED_RULES.fullmatch(body):
        return [f"{where} text that is not a rule (`selector {{ … }}`)"], ''
    scope = f'svg[data-embed="{key}"] ' if key else ''
    kept = []
    for sels, decls in SVG_CSS_RULE.findall(body):
        good = []
        for sel in sels.split(','):
            norm = _svg_embed_selector(sel)
            if norm is None:
                out.append(f"{where} selector {sel.strip()!r} — only type, "
                           f".class and #id, joined by a space or '>'")
            else:
                head = re.match(r'[^\s>]+', norm).group(0)
                typ = re.match(r'[A-Za-z][\w-]*', head)
                typ = typ.group(0) if typ else ''
                at_root = bool(key) and (typ == 'svg' or not typ and root_id
                                         in re.findall(r'#([\w-]+)', head))
                if at_root:
                    norm = norm[len(typ):]
                if key:
                    norm = re.sub(r'#([A-Za-z_-][\w-]*)', lambda m: '#'
                                  + _svg_embed_id(m.group(1), key), norm)
                good.append(scope.rstrip() + norm if at_root
                            else scope + norm)
        why, decl_out = _svg_embed_decls(decls, f"{where} {sels.strip()}")
        out += why
        if key:
            decl_out = _svg_embed_scope_urls(decl_out, key)
        kept.append(', '.join(good) + '{' + decl_out + '}')
    return out, ' '.join(kept)


def _svg_embed_id(name, key):
    """An id as the page gets it: prefixed with its figure's key (BL-452), so
    two figures never share one and none can equal an id of the page."""
    return f'e{key}-{name}'


def _svg_embed_scope_urls(text, key):
    return SVG_EMBED_URL_REF.sub(
        lambda m: f'url(#{_svg_embed_id(m.group(1), key)})', text)


def _svg_embed_refs(root):
    """Every reference to an id the file does not define, named (BL-452): a
    scoped id cannot reach the page's own, so such a reference is dangling."""
    ids = {el.get('id').strip() for el in root.iter() if el.get('id')}
    out = []
    for el in root.iter():
        local = _svg_embed_name(el.tag)[0]
        for key, val in el.attrib.items():
            name = _svg_embed_attr(key)
            if name in ('href', 'xlink:href'):
                refs = [val.strip()[1:]]
            elif name in SVG_EMBED_ID_LISTS:
                refs = val.split()
            else:
                refs = SVG_EMBED_URL_REF.findall(val)
            out += [f"<{local} {name}=…> — #{r} is not an id this file defines"
                    for r in refs if r not in ids]
        if local == 'style':
            out += [f"<style> url(#{r}) — #{r} is not an id this file defines"
                    for r in SVG_EMBED_URL_REF.findall(el.text or '')
                    if r not in ids]
    return out


def _svg_embed_name(tag):
    """`(local, in_svg_namespace)` for an element tag as ElementTree gives it."""
    if tag.startswith('{'):
        ns, local = tag[1:].split('}', 1)
        return local, ns == SVG_NS
    return tag, True


def _svg_embed_attr(key):
    """The attribute's name as it is written back, or None when it is in a
    namespace a figure may not use (anything but xlink:href, xml:space/lang)."""
    if not key.startswith('{'):
        return key
    ns, local = key[1:].split('}', 1)
    if ns == SVG_XLINK_NS and local == 'href':
        return 'xlink:href'
    if ns == SVG_XML_NS and local in ('space', 'lang'):
        return 'xml:' + local
    return None


def _svg_embed_check(el, out):
    local, ours = _svg_embed_name(el.tag)
    if not ours:
        out.append(f"<{el.tag}> — an element in a foreign namespace")
        return
    if local not in SVG_EMBED_ELEMENTS:
        out.append(f"<{local}> is not an SVG element a figure may carry")
        return
    for key, val in el.attrib.items():
        name = _svg_embed_attr(key)
        if name is None:
            out.append(f"<{local} {key}=…> — an attribute in a foreign namespace")
            continue
        if name.lower().startswith('on'):
            out.append(f"<{local} {name}=…> — an event handler is code")
            continue
        if name not in SVG_EMBED_ATTRS and name not in (
                'xlink:href', 'xml:space', 'xml:lang'):
            out.append(f"<{local} {name}=…> is not an attribute a figure "
                       f"may carry")
            continue
        if name in ('href', 'xlink:href') and not val.strip().startswith('#'):
            out.append(f"<{local} {name}=\"{val}\"> — only a #fragment of this "
                       f"file; the page must stand alone")
            continue
        if name == 'style':
            out += _svg_embed_css(val, f"<{local} style=…>", rules=False)[0]
            continue
        out += _svg_embed_urls(val, f"<{local} {name}=…>")
        if name in ('fill', 'stroke') and SVG_EMBED_PAINT.match(val):
            out.append(f"<{local} {name}=\"{val.strip()}\"> — a literal colour; "
                       f"use currentColor or a kit class")
    if local == 'style':
        # Its text reaches the page UNESCAPED (see _svg_embed_write), so it
        # must mean the same whether a parser reads it raw or decodes it.
        text = el.text or ''
        if len(el):
            out.append("<style> holds elements — a stylesheet is text")
        for bad in ('<', '&', ']]>'):
            if bad in text:
                out.append(f"<style> text holds {bad!r} — it would read "
                           f"differently to an HTML and an XML parser")
        out += _svg_embed_css(text, "<style>", rules=True)[0]
        return
    for child in el:
        _svg_embed_check(child, out)


def _svg_embed_write(el, out, key, root=False, root_id=None):
    local = _svg_embed_name(el.tag)[0]
    if root:
        root_id = (el.get('id') or '').strip() or None
    out.append('<' + local)
    if root:
        out.append(' data-embed="%s"' % key)
    for k, val in el.attrib.items():
        name = _svg_embed_attr(k)
        if name == 'style':
            val = _svg_embed_css(val, '', rules=False)[1]
        if name == 'id':
            val = _svg_embed_id(val.strip(), key)
        elif name in ('href', 'xlink:href'):
            val = '#' + _svg_embed_id(val.strip()[1:], key)
        elif name in SVG_EMBED_ID_LISTS:
            val = ' '.join(_svg_embed_id(r, key) for r in val.split())
        else:
            val = _svg_embed_scope_urls(val, key)
        out.append(' %s="%s"' % (name, _html.escape(val, quote=True)))
    if not len(el) and not el.text:
        out.append('/>')
        return
    if local == 'style':
        # The CHECKED rules, each selector scoped under this figure's root. No
        # '<' and no '&' (refused above): raw text reads the same to an HTML
        # tokenizer (raw text or data state) and to XML.
        out.append('>' + _svg_embed_css(el.text or '', '', rules=True,
                                        key=key, root_id=root_id)[1]
                   + '</style>')
        return
    out.append('>' + _html.escape(el.text or '', quote=True))
    for child in el:
        _svg_embed_write(child, out, key, root_id=root_id)
        out.append(_html.escape(child.tail or '', quote=True))
    out.append('</%s>' % local)


def _svg_embed_parse(text):
    """The file as an ElementTree root (raises `ParseError`). An HTML named
    character reference (`&middot;`) becomes its numeric form first; the five
    XML ones are left to XML, so the rewrite can never produce `<` or `&`."""
    from html.entities import name2codepoint

    def entity(m):
        name = m.group(1)
        if name in SVG_EMBED_XML_ENTITIES or name not in name2codepoint:
            return m.group(0)
        return '&#%d;' % name2codepoint[name]

    return _ET.fromstring(SVG_EMBED_ENTITY.sub(entity, text))


def svg_embed_sanitize(text):
    """`(violations, html)` for an SVG file's text: `html` is the drawing as a
    page may inline it — the parsed tree re-serialised — or None when anything
    is refused. Comments and processing instructions are dropped; an HTML named
    character reference (`&middot;`) is read as its character, because inline
    SVG copied out of a page carries them and they are text, not structure.
    """
    if re.search(r'<!(DOCTYPE|ENTITY)', text, re.I):
        return ["a <!DOCTYPE>/<!ENTITY> — a figure declares no entities"], None
    try:
        root = _svg_embed_parse(text)
    except _ET.ParseError as e:
        return [f"the file does not parse as XML ({e})"], None
    local, ours = _svg_embed_name(root.tag)
    if local != 'svg' or not ours:
        return [f"the root element is <{root.tag}>, not <svg>"], None
    out = [f"<svg {k}=…> on the root — it moves or unclips the drawing "
           f"against the page around it" for k in root.attrib
           if k in SVG_EMBED_ROOT_REFUSED]
    _svg_embed_check(root, out)
    if not out:
        out = _svg_embed_refs(root)
    if out:
        return out, None
    # The scope key: this file's own, so two figures on one page never share
    # one, and the build stays deterministic.
    key = hashlib.sha256(text.encode('utf-8')).hexdigest()[:8]
    html = []
    _svg_embed_write(root, html, key, root=True)
    return [], ''.join(html)


def svg_embed_violations(svg):
    """Why this SVG source may not be inlined as a kit figure; [] when it may."""
    return svg_embed_sanitize(svg)[0]


def _relative_luminance(rgb):
    def chan(c):
        c /= 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (chan(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(fg, bg):
    a, b = _relative_luminance(fg), _relative_luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def svg_css_fills(css, own_id=None):
    """[(compounds, combinators, specificity, colour)] for one CSS source, in
    SOURCE ORDER — a rule keyed on its WHOLE selector, not on its leaf.

    BL-348: the first cut stored `#id .statediagram-note text{fill:#fff}` under
    the bare key `text`, so a rule the browser gives to one subtree was modelled
    as the base fill of every <text> in the figure, and a second rule with the
    same leaf silently replaced the first with no source-order or specificity
    model. That is wrong in BOTH directions — it invents a finding on a node
    outside the subtree, and it HIDES a real one when a later rule with the same
    leaf overwrites a pale fill with a dark one. A checker that is wrong in both
    directions is worse than one that is merely noisy.

    A compound the parser cannot read exactly — an attribute selector
    (`[id$="-barbEnd"]`), a pseudo-class, `*` — drops the whole rule rather than
    being widened into a match: the same refusal to invent that keeps
    SVG_UNREADABLE out of the contrast pairs.

    Two rules survive from before. A selector carrying an `#id` applies ONLY to
    that figure, so it is kept when `own_id` matches and dropped otherwise. And
    a fill we cannot read is recorded as SVG_UNREADABLE rather than omitted, so
    it overrides an inherited literal instead of falling through to it."""
    out = []
    for rule in SVG_CSS_RULE.finditer(strip_css_comments(css)):
        decl = _svg_style_prop(rule.group(2), 'fill')
        if decl is None:
            continue
        colour = svg_literal_colour(decl) or SVG_UNREADABLE
        for sel in rule.group(1).split(','):
            sel = sel.strip()
            if not sel:
                continue
            ids = re.findall(r'#([\w-]+)', sel)
            if ids and (own_id is None or own_id not in ids):
                continue                            # another figure's rule
            parsed = svg_parse_selector(sel)
            if parsed is None:
                continue
            compounds, combs, spec = parsed
            out.append((compounds, combs, spec, colour))
    return out


SVG_COMPOUND = re.compile(r'^([a-zA-Z][\w-]*)?((?:[.#][\w-]+)*)$')


def svg_parse_selector(sel):
    """(compounds, combinators, specificity) for a selector we can match
    exactly, else None. `compounds` is [(tag, classes)] outermost first and
    `combinators` the len-1 shorter list of `' '` (descendant) or `'>'` (child)
    between them.

    The `#id` compounds are stripped after the caller's own_id gate, which has
    already decided the rule belongs to this figure: `#fig text` becomes `text`,
    scoped by that gate rather than by the chain. The root itself IS in the
    chain since BL-358 — under its tag and its classes, not its id. Specificity is counted
    BEFORE the strip and keeps the id, because a figure's own `#fig text` must
    outrank an unscoped `.cls` leaked in from another figure's <style>."""
    toks = re.sub(r'\s*>\s*', ' > ', sel.strip()).split()
    compounds, combs, pending = [], [], ' '
    nid = ncls = ntag = 0
    root_only = False
    for t in toks:
        if t == '>':
            pending = '>'
            continue
        m = SVG_COMPOUND.match(t)
        if not m:
            return None                 # an attribute selector or a pseudo
        tag = (m.group(1) or '').lower()
        cls = tuple(re.findall(r'\.([\w-]+)', m.group(2)))
        nid += len(re.findall(r'#[\w-]+', m.group(2)))
        ncls += len(cls)
        ntag += 1 if tag else 0
        if not tag and not cls:
            root_only = True
            continue                    # a bare #id compound: the figure root
        if compounds:
            combs.append(pending)
        compounds.append((tag, cls))
        pending = ' '
    if not compounds:
        # BL-355: a selector that was NOTHING but ids named the <svg> root and
        # nothing else — `#<figure-id>{fill:#000}`, which is the first rule in
        # every mermaid <style> and the only fill many of its labels ever get.
        # Dropping it left them with no colour at all. The caller's own_id gate
        # has already confined the rule to this figure, so the root is the one
        # `svg` node it can reach.
        return ([('svg', ())], [], (nid, ncls, ntag)) if root_only else None
    return compounds, combs, (nid, ncls, ntag)


def _svg_compound_match(comp, node):
    tag, cls = comp
    ntag, ncls = node
    return (not tag or tag == ntag) and all(c in ncls for c in cls)


def svg_chain_match(compounds, combs, chain):
    """Does this selector match the node at the end of `chain`? Right to left,
    the way a browser matches: the leaf must match the node itself, a `>` must
    match the immediate parent, and a descendant walks up until it does. The
    descendant walk is greedy and does not backtrack, so a selector that repeats
    a compound at two depths (`.a .a .b`) can miss; no figure in the field
    writes one, and missing is the safe direction — the label is then counted
    unmeasurable and said so, never painted with a colour nobody gave it."""
    if not chain or not _svg_compound_match(compounds[-1], chain[-1]):
        return False
    j = len(chain) - 2
    for i in range(len(compounds) - 2, -1, -1):
        if combs[i] == '>':
            if j < 0 or not _svg_compound_match(compounds[i], chain[j]):
                return False
            j -= 1
            continue
        while j >= 0 and not _svg_compound_match(compounds[i], chain[j]):
            j -= 1
        if j < 0:
            return False
        j -= 1
    return True


def svg_fill_for(rules, chain):
    """The fill the cascade lands on this node, or None when nothing matches.
    Highest specificity wins; SOURCE ORDER — the rule's position in the list,
    which is why `svg_contrast_findings` concatenates leaked rules before the
    figure's own — breaks a tie."""
    best, out = None, None
    for order, (compounds, combs, spec, colour) in enumerate(rules):
        if svg_chain_match(compounds, combs, chain):
            key = (spec, order)
            if best is None or key > best:
                best, out = key, colour
    return out


def _svg_tspan_fill(d, text_chain, rules):
    """The fill DECLARED on one <tspan>, or None when nothing declares one and
    the tspan simply inherits its <text>. Same cascade as the <text> one level
    up, run against the tspan's own chain — its <text>'s ancestors, the <text>,
    and the tspan itself — and then its own attribute. A NESTED tspan is
    resolved against `text_chain` too, as if it hung directly off the <text>:
    the deeper CHAIN is still a seam, and a selector reaching for `tspan tspan`
    does not exist in the field. What BL-353 fixed is the other half — the
    INHERITANCE fallback, which the caller applies: a run declaring nothing
    takes the nearest enclosing run's fill before it takes the <text>'s."""
    fl = svg_fill_for(rules, text_chain + [('tspan', tuple(d.get('class', '').split()))])
    raw = _svg_style_prop(d.get('style'), 'fill') or d.get('fill')
    if raw:
        fl = svg_literal_colour(raw) or SVG_UNREADABLE
    return fl


# The wrapper a figure is actually painted on. Measured on the 2026-09-07 bench
# page: 25 of its 26 figures sit in a `<div class="figbox">` with a fixed light
# background — the fix that made tool output legible in dark mode. Judging those
# against the page ground reported 12 figures where the browser found 9, and the
# three extra were entirely this. The wrapper is in the source, so the checker
# can read it instead of guessing.
SVG_WRAPPER = re.compile(r'<(?:div|figure|section|span|td|li)\b([^>]*)>\s*$', re.I | re.S)
CSS_BG = re.compile(r'background(?:-color)?\s*:\s*([^;}]+)', re.I)
CSS_COMPOUND = re.compile(r'[a-zA-Z][\w-]*(?:\.[\w-]+)+|(?:\.[\w-]+)+')


def page_backgrounds(text):
    """[(required_classes, leaf_class, rgb)] for every class-only rule that
    paints a literal background. `.litebox .figbox` is the real shape on the
    page this was measured against, so a single-class match is not enough —
    the rule lands on `.figbox`, but only inside a `.litebox`."""
    out = []
    # Inside <style> only. Run over the raw document, SVG_CSS_RULE's selector
    # group swallows every character since the previous `}` — prose included —
    # so a real rule reads as a paragraph and matches nothing.
    for block in SVG_STYLE_BLOCK.finditer(strip_html_comments(text)):
        for rule in SVG_CSS_RULE.finditer(strip_css_comments(block.group(1))):
            m = CSS_BG.search(rule.group(2))
            # The whole value first: `oklch(0.97 0.01 130)` has spaces inside,
            # so its first word alone is no colour. Then the first word, for
            # the `#fff url(...)` shorthand.
            val = m.group(1).strip() if m else ''
            colour = (svg_literal_colour(val) or svg_literal_colour(val.split()[0])
                      if val else None)
            if colour is None:
                continue
            for sel in rule.group(1).split(','):
                parts = sel.strip().split()
                # A compound may carry an element qualifier: the real rule on the
                # page this was measured against is `figure.cell.litebox .figbox`,
                # and a classes-only pattern matched none of it. The tag name is
                # dropped; the classes are what the ancestor chain is matched on.
                if not parts or not all(CSS_COMPOUND.fullmatch(q) for q in parts):
                    continue
                need = {c for q in parts for c in re.findall(r'\.([\w-]+)', q)}
                leaf = re.findall(r'\.([\w-]+)', parts[-1])
                if not need or not leaf:
                    continue
                out.append((need, leaf[-1], colour))
    return out


def svg_ancestor_classes(before):
    """The classes on the chain of elements enclosing an <svg>, read backwards
    from the source immediately before it. Exact for generated markup, where
    the wrapper chain is written as consecutive opening tags; it stops at the
    first thing that is not one, which is the conservative direction."""
    window, classes, chain = before[-1200:], set(), []
    while True:
        m = SVG_WRAPPER.search(window)
        if not m:
            break
        cls = (_svg_attrs(m.group(1)).get('class') or '').split()
        chain.append(set(cls))
        classes.update(cls)
        window = window[:m.start()]
    return classes, chain


def wrapper_ground(before, backgrounds):
    """The literal background painted behind an <svg> by its own wrappers, or
    None when the figure sits on the page's own ground. The innermost wrapper
    that any rule paints wins, which is what the browser does."""
    classes, chain = svg_ancestor_classes(before)
    for own in chain:                                # innermost first
        for required, leaf, colour in backgrounds:
            if leaf in own and required <= classes:
                return colour
    return None


def page_ground(text):
    """The page's own `--paper`, light and dark, read from its CSS. The dark
    value is whichever of the two dark declarations the page carries; both say
    the same thing by contract (tokens.css defines the palette three times so
    the toggle wins in both directions)."""
    ground = dict(SVG_GROUND_FALLBACK)
    decls = re.findall(r'--paper\s*:\s*(#[0-9a-fA-F]{3,8})', text)
    if decls:
        lit = [svg_literal_colour(d) for d in decls]
        lit = [c for c in lit if c]
        if lit:
            # Lightest is the light ground, darkest is the dark one. Reading
            # them positionally would depend on the order three blocks happen
            # to appear in; reading them by luminance cannot.
            ground['light'] = max(lit, key=_relative_luminance)
            ground['dark'] = min(lit, key=_relative_luminance)
    for k, v in list(ground.items()):
        ground[k] = svg_literal_colour(v) if isinstance(v, str) else v
    return ground


def svg_scope_findings(text):
    """Every bare element selector inside an embedded <svg>'s own <style>."""
    out = []
    for n, m in enumerate(SVG_BLOCK.finditer(strip_html_comments(text)), 1):
        for block in SVG_STYLE_BLOCK.finditer(m.group(2)):
            for rule in SVG_CSS_RULE.finditer(strip_css_comments(block.group(1))):
                for sel in rule.group(1).split(','):
                    sel = sel.strip()
                    if not sel or '#' in sel:
                        continue
                    toks = sel.split()
                    head = toks[0]
                    if head in SVG_PAINTED:
                        what = f"every <{head}>"
                    elif (head.startswith('.') and len(toks) > 1
                          and not SVG_HASH_CLASS.match(head)
                          and head[1:].split(':')[0] not in SVG_GENERATOR_CLASSES):
                        what = f"every {head} descendant"
                    else:
                        continue
                    out.append(
                        f"svg #{n}: '{sel}' — an embedded <style> is a "
                        f"stylesheet in the PAGE, not in the figure, so "
                        f"this paints {what} in the document and "
                        f"the last figure loaded wins. Scope it to the "
                        f"figure's own id (#<svg-id> {sel})")
    return out


def svg_contrast_findings(text):
    """(findings, measured, unmeasured) for figure text against what it is
    painted on, in BOTH themes. A pair with a literal background on both sides
    is theme-independent; one that falls back to the page ground is not, and
    the theme it fails in is named."""
    out = []
    fonts = svg_css_fonts(text)
    ground = page_ground(text)
    body = strip_html_comments(text)
    # What every figure inherits from every other: the UNSCOPED rules, which is
    # precisely the leak svg-scope reports. Rules carrying an id stay home.
    leaked = []
    for block in SVG_STYLE_BLOCK.finditer(body):
        leaked += svg_css_fills(block.group(1))
    backgrounds = page_backgrounds(text)
    measured = unmeasured = 0
    for n, m in enumerate(SVG_BLOCK.finditer(body), 1):
        own_id = _svg_attrs(m.group(1)).get('id')
        wrap = wrapper_ground(body[:m.start()], backgrounds)
        # The figure's own rules come AFTER the leaked ones, so that at equal
        # specificity the figure's own <style> wins the source-order tie.
        rules = list(leaked)
        for block in SVG_STYLE_BLOCK.finditer(m.group(2)):
            rules += svg_css_fills(block.group(1), own_id)
        root_attrs = _svg_attrs(m.group(1))
        texts, rects = svg_geometry(
            m.group(2), fonts, rules,
            root=('svg', tuple(root_attrs.get('class', '').split())))
        for label, x0, y0, x1, y1, fg in texts:
            if not isinstance(fg, tuple):
                unmeasured += 1
                continue
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            box = wrap
            for rx0, ry0, rx1, ry1, rf in rects:     # last painted rect wins
                if isinstance(rf, tuple) and rx0 <= cx <= rx1 and ry0 <= cy <= ry1:
                    box = rf
            measured += 1
            if box is not None:
                # Its own painted box is the escape hatch, and the one the
                # bench page's fix used: a figure that hard-codes light-mode
                # colours is legal on a light rect it draws itself, because
                # then the pair no longer depends on the theme at all.
                r = contrast_ratio(fg, box)
                if r < SVG_CONTRAST_FLOOR:
                    where = "rect it sits on" if box is not wrap else "box it is wrapped in"
                    out.append(f"svg #{n}: '{label}' is {r:.2f}:1 against the "
                               f"{where}, in both themes")
                continue
            # No literal colour clears 4.5:1 against BOTH grounds — the two
            # requirements pull opposite ways — so a hard-coded fill on the
            # bare page ground always fails a theme. That is the finding, not
            # a limitation of the check: the answer is `currentColor` (or a
            # token), or a box of the figure's own drawn behind it.
            fails = [(t, contrast_ratio(fg, ground[t])) for t in ('light', 'dark')
                     if contrast_ratio(fg, ground[t]) < SVG_CONTRAST_FLOOR]
            if fails:
                where = ', '.join(f"{t} {r:.2f}:1" for t, r in fails)
                out.append(f"svg #{n}: '{label}' is {where} against the page "
                           f"ground — below {SVG_CONTRAST_FLOOR}:1. A literal "
                           f"fill cannot clear both themes; use currentColor, "
                           f"or draw the box it sits on")
    return out, measured, unmeasured


def svg_text_findings(text):
    """Messages for every inline <svg> whose labels collide, leave the
    viewBox, or outgrow the rect they are centred in."""
    out = []
    fonts = svg_css_fonts(text)
    body = strip_html_comments(strip_script_style(text))
    for n, m in enumerate(SVG_BLOCK.finditer(body), 1):
        vb = _svg_attrs(m.group(1)).get('viewbox')
        try:
            vx, vy, vw, vh = (float(v) for v in re.split(r'[\s,]+', vb.strip()))
        except (AttributeError, ValueError):
            continue                                # no viewBox: no frame to judge against
        texts, rects = svg_geometry(m.group(2), fonts)
        for label, x0, y0, x1, y1, _fill in texts:
            slack = max(SVG_SLACK, SVG_ERR * (x1 - x0))
            if (x0 < vx - slack or x1 > vx + vw + slack
                    or y0 < vy - SVG_SLACK or y1 > vy + vh + SVG_SLACK):
                out.append(f"svg #{n}: '{label}' leaves the viewBox "
                           f"(estimated x {x0:.0f}..{x1:.0f}, y {y0:.0f}..{y1:.0f} "
                           f"against {vb.strip()}) — the browser clips it")
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            for rx0, ry0, rx1, ry1, _rf in rects:
                if not (rx0 <= cx <= rx1 and ry0 <= cy <= ry1):
                    continue
                if (x1 - x0) > (rx1 - rx0) + slack:
                    out.append(f"svg #{n}: '{label}' is wider than the box it sits in "
                               f"(estimated {x1 - x0:.0f} px in a {rx1 - rx0:.0f} px rect)")
                    break
                # BL-411: a label narrower than its box still leaves it when it
                # does not start at the box's left edge — width against width
                # said "fits" for three labels 28-30 px past their rect.
                if x1 > rx1 + slack or x0 < rx0 - slack:
                    side = "right" if x1 > rx1 + slack else "left"
                    out.append(f"svg #{n}: '{label}' runs past the {side} edge of the box "
                               f"it sits in (estimated x {x0:.0f}..{x1:.0f} against a rect "
                               f"{rx0:.0f}..{rx1:.0f})")
                    break
        for i in range(len(texts)):
            for j in range(i + 1, len(texts)):
                la, ax0, ay0, ax1, ay1, _fa = texts[i]
                lb, bx0, by0, bx1, by1, _fb = texts[j]
                ow = min(ax1, bx1) - max(ax0, bx0)
                oh = min(ay1, by1) - max(ay0, by0)
                slack = max(SVG_SLACK, SVG_ERR * min(ax1 - ax0, bx1 - bx0))
                if ow > slack and oh > SVG_SLACK:
                    out.append(f"svg #{n}: '{la}' and '{lb}' overlap by an estimated "
                               f"{ow:.0f}x{oh:.0f} px")
    return out


def warn_file(path):
    """Non-fatal findings as (check, name, message). Exit-neutral and never
    waived — see the module docstring for why they are a separate channel."""
    warns = []
    name = os.path.basename(path)
    if not os.path.isfile(path):
        return warns
    text = open(path, encoding="utf-8", errors="replace").read()
    try:
        for msg in svg_text_findings(text):
            warns.append(("svg-text", name,
                          msg + " — a static estimate (±5 %), so verify in the "
                          "browser with the DevTools script in "
                          "02-local-first-artifacts.md § Figures, then move "
                          "the label; this warning is cleared by the layout, "
                          "not by a waiver"))
    except Exception:                               # noqa: BLE001 — advisory
        pass
    try:
        for msg in svg_scope_findings(text):
            warns.append(("svg-scope", name, msg))
    except Exception:                               # noqa: BLE001 — advisory
        pass
    # The below-floor findings are FAILURES and live in check_file (v15); what
    # comes back here is only "nothing could be measured".
    warns.extend(svg_contrast_reports(text, name)[1])
    flat = flatten(text)
    if not CONSULT_GATE.search(flat):
        return warns
    try:
        bodies = consult_item_bodies(text)
    except Exception:                               # noqa: BLE001 — advisory
        return warns

    for ident, body in bodies:
        try:
            loose = marks_outside_opts(body)
        except Exception:                           # noqa: BLE001 — advisory
            continue
        if loose:
            warns.append(("consult-opts", name,
                          f"item '{ident}' has radio/checkbox options outside "
                          f"any .opts wrapper — components.css styles options "
                          f'only under .opts (radio groups: class="opts one", '
                          f'checkbox groups: class="opts"), so these render '
                          f"with no grid, no hover and the hints inline"))

    for ident, body in bodies:
        try:
            ids = independent_checkbox_ids(body)
        except Exception:                           # noqa: BLE001 — advisory
            continue
        if ids:
            warns.append(("consult-independent", name,
                          f"item '{ident}' is a checkbox group whose options are "
                          f"each a distinct tracked id ({', '.join(ids)}) — that is "
                          f"{len(ids)} decisions drawn as one item. A checkbox group "
                          f"is for facets of ONE decision; each of these is its own "
                          f"item with a two-option radio and its own "
                          f"data-recommended (§8, BL-375). Cleared by the rewrite"))

    for ident, body in bodies:
        for m in DATA_LABEL.finditer(body):
            val = next(g for g in m.groups() if g is not None)
            if REC_IN_LABEL.search(val):
                warns.append(("consult-rec", name,
                              f"item '{ident}' spells the recommendation "
                              f"inside data-label (\"{val.strip()}\") — that "
                              f"attribute is what the composer copies, so the "
                              f"marker travels in the pasted reply and is "
                              f"invisible on the page. Put data-recommended on "
                              f"the input instead; the kit renders the badge "
                              f"and the composer appends the suffix"))
                break

    for ident, body in bodies:
        try:
            dense = facts_paragraphs(body)
        except Exception:                           # noqa: BLE001 — advisory
            continue
        for codes, clauses, excerpt in dense:
            shape = (f"{codes} <code> tokens" if codes >= FACTS_MIN
                     else f"{clauses} semicolon-separated clauses")
            warns.append(("consult-facts", name,
                          f"'{ident}' carries a paragraph with {shape} "
                          f"(\"{excerpt}…\") — more than three facts of one "
                          f"shape are a table, a list or a figure, never a "
                          f"paragraph (§8.4, BL-269/BL-270). Rewrite it as "
                          f"rows; this warning is cleared by the rewrite, not "
                          f"by a waiver"))

    try:
        trailing = trailing_evidence(text)
    except Exception:                               # noqa: BLE001 — advisory
        trailing = []
    for gid, ident, kind in trailing:
        warns.append(("consult-order", name,
                      f"block '{gid}' ends with evidence ({kind}) after its last "
                      f"item '{ident}' — the reader meets the answer box before "
                      f"the material it asks about. Evidence precedes its "
                      f"question and an item closes its unit (§8.4, BL-463): "
                      f"move the evidence above the item it belongs to"))
    return warns


# --- Requirement 1, across regenerations (--prev) -----------------------------

ID_TAG = re.compile(r'<[^>]*\bdata-id\s*=[^>]*>', re.I | re.S)
ID_ATTR = re.compile(r'\bdata-(id|title)\s*=\s*'
                     r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))', re.I | re.S)


def _norm_title(s):
    """A retyped title must not read as a moved claim: decode entities, collapse
    whitespace, drop accents and case. Only a genuinely different claim behind a
    kept id fails.

    BL-324: the decode is first and it is load-bearing. `data-title` is read out
    of raw source, so the same Spanish title written `para qui&eacute;n` in one
    version and `para quién` in the next compared unequal — seven ids on one
    page reported as "reused for a different claim", same language, same words.
    Accent-folding alone does not fix it: `&eacute;` is five ASCII characters,
    and there is no combining mark to strip."""
    s = _html.unescape(s)
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return " ".join(s.split()).casefold()


def _page_lang(path):
    """The two-letter `<html lang>` of a page, `en` when it declares none —
    the same default `language_mismatch` uses."""
    m = HTML_LANG.search(open(path, encoding="utf-8", errors="replace").read())
    return (m.group(1).lower().split("-")[0] if m else "en")


def id_title_map(path):
    """{data-id: normalised title}. Reads the TAG, then its attributes, rather
    than one spelling of an id/title pair — a single-quoted page, or a title
    that merely quotes something, must not drop out of the map."""
    out = {}
    text = open(path, encoding="utf-8", errors="replace").read()
    for tag in ID_TAG.finditer(text):
        attrs = {}
        for m in ID_ATTR.finditer(tag.group(0)):
            # `is not None`, never truthiness: an empty value is a real value,
            # and testing it for truth used to select an unmatched branch and
            # crash on None — killing the diff for the entire page.
            val = next(g for g in m.groups()[1:] if g is not None)
            attrs.setdefault(m.group(1).lower(), val)
        if "id" in attrs and "title" in attrs:
            out.setdefault(attrs["id"], _norm_title(attrs["title"]))
    return out


# --- the per-file contract -----------------------------------------------------


def svg_contrast_reports(text, name):
    """(fails, warns) — figure text below the 4.5:1 floor, and the no-measurement note.

    One producer, two severities. Since v15 these are FAILURES when a named
    file is checked — the wrap — and WARNINGS in `--census`. The asymmetry is
    the whole point and it was the owner's call: a page being written must not
    ship text nobody can read, while the same finding on a page nobody is
    editing is noise no one can clear. `CENSUS_ADVISORY` is what carries it.
    """
    fails, warns = [], []
    try:
        found, measured, unmeasured = svg_contrast_findings(text)
    except Exception:                               # noqa: BLE001 — advisory
        return fails, warns
    # The denominator travels with every finding, and the clean case says
    # nothing at all — a page with no figures must not grow a line. What it
    # cannot say is "nothing to report" when it measured nothing: that is
    # the shape this whole check exists because of.
    tail = (f" — measured {measured} text node(s) in this page's "
            f"figures, {unmeasured} unmeasurable (currentColor, a "
            f"gradient or a var() the file does not resolve); verify "
            f"those in the browser")
    for msg in found:
        fails.append(("svg-contrast", name, msg + tail))
    # "Nothing was measurable" stays a WARNING even at the wrap, and that is not
    # a softening — it is the difference between a measurement and its absence.
    # The kit's own skeleton paints every label with `currentColor`, which is
    # the pattern the canon prescribes precisely because it follows the theme;
    # failing on it would fail every page built the recommended way. It still
    # has to be said out loud, because a gate that silently measured nothing is
    # green and indistinguishable from one that passed.
    if measured == 0 and unmeasured:
        warns.append(("svg-contrast", name,
                      "no figure text could be measured for contrast" + tail))
    return fails, warns


# Checks that FAIL a named file but only WARN in the census. svg-contrast, and
# contract_defects' classes (ruling 2026-09-28, LOOP-006): a page nobody is
# editing was built by an older kit and is red on them by construction, so the
# census reports them and the page being written or wrapped is what they block.
import contract_defects                             # noqa: E402 — same directory
CENSUS_ADVISORY = ("svg-contrast", "contract") + tuple(contract_defects.CHECKS)



def h2s_outside_id_sections(flat):
    """Count <h2> elements the rail cannot index, the way the browser nests them.

    composer.js indexes `.main > section[id]` and takes the first h2 of each. So
    an h2 is indexable only if some ancestor is a section WITH an id that is a
    DIRECT child of `.main`. A regex depth counter over <section> tags missed
    the shipped case: haiku's consultation (A1, 2026-09-14) never closed its
    <figure>, so every section was nested inside the figure and the rail listed
    one entry. html.parser follows the source nesting the same way the browser
    does for an unclosed non-void element, so the parser sees what the reader
    saw. Fails closed: an h2 with no .main ancestor is counted too.
    """
    from html.parser import HTMLParser

    VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link",
            "meta", "param", "source", "track", "wbr"}

    class P(HTMLParser):
        def __init__(self):
            super().__init__()
            self.stack = []          # (tag, is_main, indexable_section)
            self.orphans = 0

        def handle_starttag(self, tag, attrs):
            a = dict(attrs)
            classes = (a.get("class") or "").split()
            is_main = tag == "main" and "main" in classes or "main" in classes
            parent_is_main = bool(self.stack) and self.stack[-1][1]
            indexable = (tag == "section" and bool(a.get("id"))
                         and parent_is_main)
            if tag == "h2":
                if not any(fr[2] for fr in self.stack):
                    self.orphans += 1
            if tag in VOID:
                return
            self.stack.append((tag, is_main, indexable))

        def handle_startendtag(self, tag, attrs):
            self.handle_starttag(tag, attrs)
            if tag not in VOID:
                self.stack.pop()

        def handle_endtag(self, tag):
            for k in range(len(self.stack) - 1, -1, -1):
                if self.stack[k][0] == tag:
                    del self.stack[k:]
                    return

    p = P()
    p.feed(flat)
    return p.orphans


def check_file(path):
    """Every violation in one file, as (check, name, message) tuples."""
    fails = []

    def report(check, msg, name=None):
        fails.append((check, name or os.path.basename(path), msg))

    if not os.path.isfile(path):
        report("missing", "no such file", name=path)
        return fails
    text = open(path, encoding="utf-8", errors="replace").read()
    flat = flatten(text)

    if not re.search(r'<!doctype\s+html', flat, re.I):
        report("doctype", "no <!doctype html> — headless fragment, browsers "
                          "render it in quirks mode")
    if not re.search(r'<meta[^>]+charset', flat, re.I):
        report("charset", "no <meta charset> — accented text can mis-decode "
                          "from file://")
    if not re.search(r'<meta[^>]+name=["\']?viewport', flat, re.I):
        report("viewport", "no viewport meta — unreadable on a phone")
    if not re.search(r'<title>', flat, re.I):
        report("title", "no <title> — the browser tab has no name")
    if "prefers-color-scheme" not in text:
        report("themes", "no prefers-color-scheme — unreadable for a "
                         "dark-mode reader")

    mm = language_mismatch(text)
    if mm:
        declared, dominant, es, en = mm
        report("lang", f'<html lang="{declared}"> but the body reads {dominant} '
                       f"({es} Spanish vs {en} English stopwords) — the composer "
                       f"and the kit's chrome key off lang, so the reader gets two "
                       f"languages on one page. Write the body in the profile's "
                       f"language (artifact-style.md `language:`) or pass --lang "
                       f"(BL-279)")

    # --- raw-link: markdown link syntax shipped to the reader as text ----------
    # A spec had no inline link until 2026-09-25, so `[R1](R1.html)` reached the
    # blind-review page as brackets and a filename (the build was patched after
    # the fact). The builder renders links now and refuses a bad scheme; this is
    # the check for what still slips through (an HTML-route page, a refused
    # target left literal by `md_body._inline`). Text inside <code>, <pre> or a
    # <textarea> is the author quoting the syntax, and is not counted.
    unquoted = re.sub(r"<(code|pre|textarea)\b[^>]*>.*?</\1\s*>", " ",
                      visible_source(text), flags=re.I | re.S)
    raw = RAW_LINK.search(re.sub(r"<[^>]+>", " ", unquoted))
    if raw:
        report("raw-link", f"the page shows a raw markdown link, {raw.group(0)!r}, "
                           f"as text — write it as <a href>, or in a spec as "
                           f"[text](target) with a relative, #fragment or "
                           f"https: target, which the builder renders")

    # rec-leak (BL-481) lived here until LOOP-006: a literal `{recommended}` is
    # now contract_defects' decision-item-without-options finding (below), one
    # owner per rule. Its <textarea> exemption was not ported: it was inherited
    # from raw-link's `unquoted` (a4dcc72), not decided for the marker — a
    # prefilled reply box holding the marker is pasted back as the leak.

    # --- self: one file, no network -------------------------------------------
    if re.search(r'<link[^>]+rel=["\']?stylesheet', flat, re.I):
        report("self", "external stylesheet — the file must stand alone offline")
    if re.search(r'<script[^>]+src=', flat, re.I):
        report("self", "external script — the file must stand alone offline")
    if re.search(r'@import\s+(url\()?["\']?https?:', flat, re.I):
        report("self", "@import of a remote stylesheet")
    if re.search(r'<img[^>]+src=["\']?https?:', flat, re.I):
        report("self", "remote image — breaks offline and leaks a request")
    # Only a remote src counts: url(data:…) is inlined and honours the contract.
    if re.search(r'@font-face[^}]*url\(\s*["\']?(https?:)?//', flat, re.I):
        report("self", "remote @font-face src — the font never loads offline "
                       "and leaks a request")

    # --- siblings ---------------------------------------------------------------
    dirpath = os.path.dirname(path) or "."
    try:
        assets = sorted(e for e in os.listdir(dirpath)
                        if e.endswith((".css", ".js"))
                        and os.path.isfile(os.path.join(dirpath, e)))
    except OSError:
        assets = []
    if assets:
        report("siblings", f"sibling assets next to it ({assets[0]}…) — "
                           f"inline them")

    # --- the kit's layout container (BL-177) ------------------------------------
    # Scoped to pages that carry the kit stamp: a page without it has no `.page`
    # rule to be inside of, and judging it would fail every pre-kit artifact.
    # Matched as class TOKENS: components.css spells `.page` and `.main` as
    # selectors and is injected into every page, so a looser match is answered
    # by the stylesheet on precisely the page that has none of the structure.
    #
    # There is no opt-out marker and there is deliberately none: a page that
    # wants to be full-bleed overrides `.page { max-width: none }` in its own
    # <style> and keeps the grid, the rail and the responsive collapse.
    # --- one wrap per document (BL-414) -----------------------------------------
    # Counted, not detected by shape: a page legitimately carries many <style>
    # blocks and many <meta name="consult-round"> (five on the field page), so
    # neither can key this. The kit stamp and the composer are emitted exactly
    # once per wrap and by nothing else.
    stamps = len(KIT_STAMP.findall(flat))
    try:
        composers = composer_copies(text)
    except Exception as e:                          # noqa: BLE001 — fail closed
        report("double-wrap", f"the composer scan did not run ({e})")
        composers = 0
    if stamps > 1 or composers > 1:
        report("double-wrap", f"{stamps} kit stamp(s) and {composers} copy/ies of "
               f"composer.js — this page was wrapped more than once (an "
               f"already-wrapped page fed back in as the body). Both composers "
               f"append to the same #raillist, so the reader sees the index "
               f"twice. Wrap the page's CONTENT, never the file on disk: take "
               f"the body from .aidex-artifact-prev/<page>.body, or extract "
               f"what is inside <body> minus the kit's injected <style>/"
               f"<script>, and wrap that once")

    if KIT_STAMP.search(flat):
        contained = True
        for cls in ("page", "main"):
            if not re.search(r'class=["\'](?:[^"\']*\s)?' + cls
                             + r'(?:\s[^"\']*)?["\']', flat):
                contained = False
                report("layout", f'no element with class="{cls}" — the content '
                       f'is outside the kit\'s layout container, so the page '
                       f'renders full-bleed with no reading measure. Wrap it '
                       f'the way assets/artifact-kit/skeleton.html does: '
                       f'<div class="page"><main class="main">…</main>'
                       f'<aside class="rail">…</aside></div>')
        # --- the rail (D4, 2026-09-13) -------------------------------------------
        # composer.js builds the index at load from `.main > section[id]` (one
        # entry per section that holds an h2) into #raillist. Nothing static
        # rendered it, so two shipped pages passed with no index: one had no
        # <aside class="rail"> at all, one had 9 h2s and 3 id'd sections.
        # Static approximation: #raillist must exist, and every <h2> in the
        # document must be preceded by an id'd <section> open tag that is still
        # open (depth-counted), which is what the composer can index.
        # Only inside the container: a page that already fails `layout` has no
        # column for a rail to sit beside, and a second finding for the same
        # missing structure would defeat a waiver of the first (census fixture).
        if not contained:
            pass
        elif not re.search(r'id=["\']raillist["\']', flat):
            report("rail", 'no element with id="raillist" — composer.js builds '
                   'the page index into it, so the page opens with no rail. Add '
                   'the skeleton\'s <aside class="rail"> after </main>, or wrap '
                   'with wrap-report.sh which injects it')
        else:
            orphan = h2s_outside_id_sections(flat)
            if orphan:
                report("rail", f"{orphan} <h2> heading(s) not inside an id'd "
                       f"<section> that is a DIRECT child of .main — the rail "
                       f"indexes `.main > section[id]` only (an unclosed tag "
                       f"above them nests them somewhere else), so those "
                       f"headings are missing from the index. Give each h2 its "
                       f"own <section id=\"…\"> directly under <main>")
        try:
            bad = unwrapped_tables(text)
        except Exception as e:                      # noqa: BLE001 — fail closed
            report("layout", f"the table-wrapper scan did not run ({e})")
            bad = 0
        if bad:
            report("layout", f"{bad} table(s) outside any scrolling container "
                   f"— a table cannot be capped, so a wide one renders over "
                   f"the rail with no scrollbar to show it. Wrap each in "
                   f'<div class="tw">…</div>, or in any wrapper this page '
                   f"declares with overflow-x: auto")

    # --- § 8: the page is a CONSULTATION, not a read -----------------------------
    # Detection is an OR over four arms, and it has to stay one:
    #   a reply surface in the MARKUP — a page that never copied the template
    #     has no `.consult-item` to key on (BL-168: 9 reply boxes, 0 stable ids)
    #   a data-id item              — a radio/select item carries no textarea
    #   the composer button id       — a page that offers to compose a reply
    #   the item CLASS in an attribute — reply boxes built at runtime
    # A report meant to be read hits none of the four and this stays silent.
    #
    # One BOUNDED exemption: a page whose only match is a closed control — no
    # free text, no consultation structure — may declare the controls as
    # filters with a reason (`consult-surfaces`, checked below). A dashboard's
    # row-filter <select> is not a question, and without the declaration that
    # page collected the whole §8 battery with no way to comply.
    if CONSULT_GATE.search(flat):
        declared = ""
        # CONSULT_ITEMS, not CONSULT_STRUCTURE: a copy bar with nothing to copy
        # must not veto the declaration (BL-331). A page carrying a single real
        # item still cannot declare its way out — that is the half of this the
        # test pins in the other direction.
        if not FREE_TEXT.search(flat) and not CONSULT_ITEMS.search(flat):
            try:
                declared = surfaces_declaration(text)
            except Exception:                       # noqa: BLE001 — fail closed
                declared = ""
            if PLACEHOLDER_REASON.search(declared):
                declared = ""
        if not declared:
            fails.extend(check_consultation(path, text, flat))

    # --- the gallery row's own completeness --------------------------------
    # Outside the consultation gate on purpose: a gallery item IS a question,
    # so it can never be one of the pages that declare their controls to be
    # filters, and a page with no `consult-gallery` item reports nothing here.
    try:
        for msg in gallery_findings(text):
            report("gallery", msg)
    except Exception as e:                          # noqa: BLE001 — fail closed
        report("gallery", f"the gallery-row scan did not run ({e})")

    # --- the page contract: contract_defects.py's source classes (LOOP-006) ---
    # That module is the ONE owner of each rule (BL-468's optionless-item
    # warning used to live here as a second copy); this only reports its
    # findings, one FAIL per finding, keyed by the class slug.
    try:
        for slug, line, msg in contract_defects.findings(path):
            report(slug, f"line {line}: {msg}")
    except Exception as e:                          # noqa: BLE001 — fail closed
        report("contract", f"the contract-defects scan did not run ({e})")

    # Colour, last, and on EVERY page — a read's figures are read too. A page
    # whose figure text nobody can see does not ship. Failing here rather than
    # warning is v15 and was the owner's call (Q3): a warning that fired on 26
    # of 26 figures is one the reader learns to discount, which is how the
    # defect BL-330 found survived three green gates. `--census` keeps the old
    # severity — see CENSUS_ADVISORY.
    fails.extend(svg_contrast_reports(text, os.path.basename(path))[0])

    return fails


# --- § 8.4 as a fact of the DOM: the block shape (BL-247) ---------------------
# "The explanation lives inside the item" was declared not machine-checked
# because every proxy for item QUALITY is satisfiable without satisfying it.
# BL-240 kept the letter — items of 350-700 words — under a 1,553-word preamble
# two questions depended on. What is checkable without being a proxy is WHERE
# things sit: every item inside a block (`.consult-group` — one context with
# the decisions it yields), every block with at least one decision, no prose
# section between the first block and the general-notes item, and before the
# first block only the header, a visual section and the ledger. Reference
# material goes AFTER the questions. Word counts stay out (BL-243).

GROUP_CLASS = re.compile(r'\bclass\s*=\s*["\'][^"\']*\bconsult-group\b', re.I)
GROUP_OPEN = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*\bclass\s*=\s*["\'][^"\']*'
                        r'\bconsult-group\b[^>]*>', re.I | re.S)
NOTES_OPEN = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*\bclass\s*=\s*["\'][^"\']*'
                        r'\bconsult-notes\b[^>]*>', re.I | re.S)
SECTION_OPEN = re.compile(r'<section\b[^>]*>', re.I | re.S)
H2 = re.compile(r'<h2\b[^>]*>(.*?)</h2\s*>', re.I | re.S)
PROSE = re.compile(r'<(p|table|ul|ol|dl|blockquote|pre)\b', re.I)


def _tag_attr(tag, name):
    m = re.search(r'\b' + name + r'\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))',
                  tag, re.I | re.S)
    return next((g for g in m.groups() if g is not None), "") if m else ""


def _h2_text(fragment):
    m = H2.search(fragment)
    return " ".join(re.sub(r'<[^>]+>', '', m.group(1)).split()) if m else "(untitled)"


def _strip_subtrees(fragment, opener):
    """fragment with every subtree opened by `opener` removed."""
    out, pos = [], 0
    for m in opener.finditer(fragment):
        if m.start() < pos:
            continue
        body = _subtree(fragment, m.group(1), m.end())
        out.append(fragment[pos:m.start()])
        pos = m.end() + len(body)
        close = re.match(r'</' + re.escape(m.group(1)) + r'\s*>', fragment[pos:], re.I)
        if close:
            pos += close.end()
    out.append(fragment[pos:])
    return "".join(out)


FIGURE_OPEN = re.compile(r'<(figure)\b[^>]*>', re.I)
LEDGER_SUB = re.compile(r'<(div)\b[^>]*\bclass\s*=\s*["\'][^"\']*\bledger\b[^>]*>', re.I)
SECHEAD_SUB = re.compile(r'<(div)\b[^>]*\bclass\s*=\s*["\'][^"\']*\bsec-head\b[^>]*>', re.I)

MAIN_OPEN = re.compile(r'<main\b[^>]*>', re.I)
SECTION_SUB = re.compile(r'<(section)\b[^>]*>', re.I)
HEADER_SUB = re.compile(r'<(header)\b[^>]*>', re.I)
# The page title and the two header lines are the header even when no <header>
# wraps them: the report pages put them straight under <main>.
TITLE_LINE = re.compile(
    r'<h1\b[^>]*>.*?</h1\s*>'
    r'|<p\b[^>]*\bclass\s*=\s*["\'][^"\']*\b(?:standfirst|eyebrow)\b[^"\']*'
    r'["\'][^>]*>.*?</p\s*>', re.I | re.S)

ELEM_OPEN = re.compile(r'<([a-zA-Z][\w:-]*)\b[^>]*?(/?)>', re.S)
VOID_TAGS = {"area", "base", "br", "col", "embed", "hr", "img", "input",
             "link", "meta", "param", "source", "track", "wbr"}
CLASS_VAL = re.compile(r'\bclass\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^\s>]+))', re.I)
# A grid cell is a heading or a table away from the layout BL-426 reports, at
# any depth: `.v` is a cell, and a table inside one cannot be capped either.
LEDGER_BANNED = re.compile(r'<(h[1-6]|table)\b', re.I)


def _child_nodes(fragment):
    """(tag, open_tag, inner) per top-level element of `fragment`, and
    (None, "", text) for the text between them. Comments are the caller's to
    strip: this walk reads a commented-out `<p>` as markup."""
    out, pos = [], 0
    while True:
        m = ELEM_OPEN.search(fragment, pos)
        if not m:
            out.append((None, "", fragment[pos:]))
            return out
        out.append((None, "", fragment[pos:m.start()]))
        tag = m.group(1)
        if m.group(2) == "/" or tag.lower() in VOID_TAGS:
            out.append((tag, m.group(0), ""))
            pos = m.end()
            continue
        inner = _subtree(fragment, tag, m.end())
        out.append((tag, m.group(0), inner))
        pos = m.end() + len(inner)
        close = re.match(r'</' + re.escape(tag) + r'\s*>', fragment[pos:], re.I)
        if close:
            pos += close.end()


def _class_tokens(open_tag):
    """The class attribute split on whitespace. Tokens, never substrings:
    `k-1`, `v-align`, `key` and `kv` are not `k` and not `v`."""
    m = CLASS_VAL.search(open_tag)
    if not m:
        return set()
    return set(next(g for g in m.groups() if g is not None).split())


def _ledger_row_ok(inner):
    """True when a row's element children are only `.k`/`.v` cells, one of each
    at least. What sits INSIDE a cell is free: `.v` carries inline markup."""
    seen = set()
    for tag, open_tag, _ in _child_nodes(inner):
        if tag is None:
            continue
        cells = _class_tokens(open_tag) & {"k", "v"}
        if not cells:
            return False
        seen |= cells
    return {"k", "v"} <= seen


def _ledger_shape(body):
    """Empty when `body` is a ledger, else the shapes in it that are not rows.
    `.ledger` is a grid of rows, each a `<div>` of a `.k` key and a `.v` value
    (components.css); anything else laid in it becomes a grid cell of its own,
    side by side with the next. An EMPTY ledger is a ledger — the row count is
    not the shape."""
    body = strip_html_comments(body)
    bad = []
    for tag, _open, inner in _child_nodes(body):
        if tag is None:
            if inner.strip():
                bad.append("loose text")
        elif tag.lower() in VOID_TAGS:
            continue
        elif tag.lower() != "div" or not _ledger_row_ok(inner):
            bad.append(tag.lower())
    bad.extend(m.group(1).lower() for m in LEDGER_BANNED.finditer(body))
    return ", ".join(dict.fromkeys(bad))


def check_shape(path, text):
    """The block shape, judged on the ITEM-bearing page only: a read has no
    blocks and no rules here."""
    fails = []

    def report(msg):
        fails.append(("consult-shape", os.path.basename(path), msg))

    groups = []   # (id, open_start, body_start, body_end)
    for m in GROUP_OPEN.finditer(text):
        body = _subtree(text, m.group(1), m.end())
        ident = _tag_attr(m.group(0), "data-id") or _tag_attr(m.group(0), "id") or "?"
        groups.append((ident, m.start(), m.end(), m.end() + len(body)))

    def in_group(pos):
        return any(a <= pos < b for _, _, a, b in groups)

    # Every item lives inside a block — the general-notes item excepted, it is
    # the one item that answers to no context.
    for m in ITEM_OPEN.finditer(text):
        tag = m.group(0)
        if GROUP_CLASS.search(tag) or NOTES_OPEN.match(tag):
            continue
        ident = next(g for g in m.groups()[1:] if g is not None)
        if not in_group(m.start()):
            report(f"item '{ident}' sits outside any block — every decision "
                   f"lives inside a <section class=\"consult-group\"> with "
                   f"the context it comes from (02-local-first-artifacts.md "
                   f"§ 8.4). A block may carry one decision or several")

    # Every block carries a decision: a context with nothing to answer is the
    # old preamble wearing a class.
    for ident, _, a, b in groups:
        if not any(a <= m.start() < b and not GROUP_CLASS.search(m.group(0))
                   for m in ITEM_OPEN.finditer(text)):
            report(f"block '{ident}' carries no decision — a context with "
                   f"nothing to answer is prose. Move it into the block whose "
                   f"decisions need it, or after the questions if it is "
                   f"reference material")

    # The general-notes item closes the question set (BL-457): no block and no
    # item after it. Reference sections after it stay allowed — they carry no
    # data-id and no consult-group class. The class TOKEN, never the word:
    # `\bconsult-notes\b` also matches `consult-notes-hint`.
    notes_m = next((m for m in NOTES_OPEN.finditer(text)
                    if "consult-notes" in _class_tokens(m.group(0))), None)
    if notes_m:
        after = notes_m.end() + len(_subtree(text, notes_m.group(1), notes_m.end()))
        nxt = [m for m in (ITEM_OPEN.search(text, after), GROUP_OPEN.search(text, after))
               if m]
        if nxt:
            m = min(nxt, key=lambda m: m.start())
            ident = (_tag_attr(m.group(0), "data-id") or _tag_attr(m.group(0), "id")
                     or "?")
            report(f"the general-notes item is followed by '{ident}' — the "
                   f"notes close the question set and are the last consult "
                   f"item; move them after '{ident}' (reference material may "
                   f"still follow them)")

    if not groups:
        return fails
    first = min(s for _, s, _, _ in groups)
    end = notes_m.start() if notes_m else len(text)

    # Nothing but blocks between the first block and the general notes.
    for m in H2.finditer(text, first, end):
        if not in_group(m.start()):
            report(f"prose between blocks: \"{_h2_text(m.group(0))}\" — the "
                   f"context a decision needs sits in its block, above the "
                   f"decision; there is no place for a section between blocks")

    # Before the first block: the header, a visual section, the ledger, and the
    # section that merely contains the blocks. Anything else is the preamble
    # the reader scrolls back to.
    def judge_preamble(fragment):
        label = _h2_text(fragment)
        rest = _strip_subtrees(fragment, SECHEAD_SUB)
        rest = _strip_subtrees(rest, FIGURE_OPEN)
        # The exemption belongs to the ledger's SHAPE, not to its class name: a
        # writer that meets this FAIL can otherwise wrap the prose in
        # `<div class="ledger">` and pass, and the grid then clips it (BL-426).
        pos = 0
        for lm in LEDGER_SUB.finditer(rest):
            if lm.start() < pos:               # a nested ledger reports once
                continue
            sub = _subtree(rest, lm.group(1), lm.end())
            pos = lm.end() + len(sub)
            shape = _ledger_shape(sub)
            if shape:
                report(f"the ledger before the first block is not a ledger: "
                       f"it holds {shape} — `.ledger` is a grid of rows, each "
                       f"a <div> of a .k key and a .v value, and nothing else. "
                       f"A summary before the first block is a real ledger of "
                       f".k/.v rows, never a table; anything else goes into "
                       f"the block that needs it or after the questions")
        rest = _strip_subtrees(rest, LEDGER_SUB)
        if PROSE.search(rest):
            report(f"prose before the first block: \"{label}\" — "
                   f"before the blocks only the header (title + standfirst), "
                   f"a figure and the ledger may appear. The strongest claim "
                   f"goes in the standfirst; context goes in the block that "
                   f"needs it; reference material goes after the questions")

    # The region before the first block that sits in NO section: the report
    # pages put the title, the standfirst and the ledger straight under <main>,
    # and a rule that only reads sections is one missing wrapper from silent.
    mm = MAIN_OPEN.search(text, 0, first)
    bare = strip_html_comments(strip_script_style(text[mm.end() if mm else 0:first]))
    bare = _strip_subtrees(bare, SECTION_SUB)
    bare = _strip_subtrees(bare, HEADER_SUB)
    judge_preamble(TITLE_LINE.sub(" ", bare))

    for m in SECTION_OPEN.finditer(text, 0, first):
        body = _subtree(text, "section", m.end())
        if m.end() + len(body) > first:        # contains the first block
            continue
        judge_preamble(strip_html_comments(body))
    return fails


def check_consultation(path, text, flat):
    fails = []

    def report(check, msg):
        fails.append((check, os.path.basename(path), msg))

    try:
        items = consult_items(text)
    except Exception as e:                          # noqa: BLE001 — fail closed
        report("consult", f"the consultation-item scan did not run ({e})")
        items = []

    # Requirement 1 — every claim is an item with a stable id. Without data-id
    # there is nothing to keep stable and nothing --prev can compare.
    if items:
        fails.extend(check_shape(path, text))
    if not items:
        n_surface = sum(1 for _ in SURFACE_PAT.finditer(flat))
        # A page with only closed controls has a second legitimate reading —
        # they are filters on a read — so the failure names the exit. A page
        # with free text does not get the offer: that is BL-168's shape.
        escape = ("" if FREE_TEXT.search(flat) else
                  ' — or, if these controls only filter what is shown, declare '
                  '<meta name="consult-surfaces" content="none: why"> and the '
                  'page is a read')
        report("consult", f"{n_surface} reply surface(s) but no data-id item — "
               f"every consultation item needs a stable id (copy "
               f"assets/templates/consultation-block.html.template)"
               f"{escape}")
    else:
        for ident, has_title, has_surface, has_notes, _decided in items:
            if not ident:
                continue
            # data-title is what the composed reply is headed with; without it
            # the paste says (### c3) and the reader must return to the page to
            # learn what c3 was.
            if not has_title:
                report("consult", f"item '{ident}' has no data-title — the "
                       f"composed reply would have an unnamed heading")
            # Any reply surface counts. An item with NONE is a claim the reader
            # cannot answer, which is the one shape that still fails.
            if not has_surface:
                report("consult", f"item '{ident}' has no reply surface — a "
                       f"consultation item the reader cannot answer")
            # ...and every item also carries FREE TEXT, whatever else it offers.
            # Reported from use: a closed list with no room to qualify the
            # choice makes the reader answer the question the page asked
            # instead of the one they have.
            if not has_notes:
                report("consult", f"item '{ident}' has no notes box — a closed "
                       f"choice with nowhere to qualify it loses everything "
                       f"the options do not cover. Add a <textarea> to the "
                       f"item (assets/templates/consultation-block.html."
                       f"template ships one in every block)")
        # Two claims answering to one id: a reply about that id points at both.
        seen, dupes = set(), []
        for ident, *_ in items:
            if ident in seen and ident not in dupes:
                dupes.append(ident)
            seen.add(ident)
        if dupes:
            report("consult", f"duplicate ids ({' '.join(dupes)}) — two claims "
                   f"answering to one id")

        # A decided item is summarised into the ledger, and the page then has
        # two ways to land it (02-local-first-artifacts.md § Update in place):
        # KEEP the item with `data-decided` — the default, so the page stays a
        # record of the reasoning — or remove it. What is not allowed is the
        # third shape: the answer recorded in the ledger while the item goes on
        # ASKING, live and undeclared. That is the obligation half-done, and it
        # is the only one this reports.
        # BL-359: "decided" IS a property of the markup after all, and the kit
        # had honoured it in CSS and in composer.js since v15 — this check was
        # the last reader that had not been told, and it failed the shape its
        # own reference calls the default. What stays out of reach is the other
        # half: an item decided and never written to the ledger at all, which
        # is what BL-190 observed and is not mechanically reachable from the
        # page alone.
        try:
            settled = ledger_ids(text)
        except Exception as e:                      # noqa: BLE001 — fail closed
            report("consult", f"the ledger scan did not run ({e})")
            settled = set()
        # `notes` is excluded: it is the ONE id the contract mandates be
        # present on every page, so it cannot leave the question set — a
        # ledger key whose trailing word happens to be it (keys carry bare
        # words in the field: `c11 · auth`, `AWS · blocker`) would raise a
        # failure no author could clear by complying.
        still_asked = sorted(
            {i for i, _t, _s, _n, decided in items
             if i and i != "notes" and not decided} & settled)
        if still_asked:
            report("consult", f"decided but still asked ({' '.join(still_asked)}"
                   f") — the ledger records these as settled while the question "
                   f"set still asks them live. Either mark the item decided "
                   f"WITH its verdict — data-decided=\"<the verdict>\" or the "
                   f"chosen option `checked` (a spec: decided=<the verdict>); "
                   f"prose in its body is folded away with it — (the default: "
                   f"the page keeps the reasoning), or remove it. "
                   f"(This sees only items the ledger names; one decided and "
                   f"never written there is invisible to any check.)")

    # ...and the page carries the general-notes item, always present (that it
    # is the last consult item is check_shape's rule, BL-457). Matched inside a class ATTRIBUTE, never as the bare word:
    # components.css DEFINES `.consult-notes` and is injected into every page,
    # so an unanchored match would be answered by the stylesheet on a page that
    # carries no such item — the lie-by-omission this contract exists to
    # prevent, and it has already happened twice inside this kit.
    if not re.search(r'class=["\'][^"\']*consult-notes', flat):
        report("consult", 'no general-notes item (class="consult-item '
               'consult-notes") — the answer that fits none of the questions '
               'has nowhere to go')

    # Requirement 2 — the page composes the reply, and says how many are blank.
    if not re.search(r'id\s*=\s*["\']consult-copy["\']', flat):
        report("consult", 'no compose-and-copy button (id="consult-copy") — '
               'the reader has to assemble the reply by hand')
    if not re.search(r'id\s*=\s*["\']consult-status["\']', flat):
        report("consult", 'no status line (id="consult-status") — nowhere to '
               'report how many items are still blank')
    # Read the COMPOSER, not the whole document: prose, CSS comments and
    # placeholder text satisfied the old whole-file grep on a page whose blank
    # accounting had been torn out, and a correct Spanish page failed it.
    try:
        code = script_code(text)
    except Exception as e:                          # noqa: BLE001 — fail closed
        report("consult", f"the composer scan did not run ({e})")
        code = "blank"
    if "blank" not in code.lower():
        report("consult", "the composer never counts blank items — a "
               "half-answered page must be visible BEFORE it is pasted. The "
               "check reads <script> content with comments stripped, so "
               "prose, CSS comments and placeholder text do not satisfy it")

    # A consultation carries a visual by DEFAULT (USAGE-19). No checker can
    # judge whether a topic has a shape worth drawing, so the check is on the
    # DECLARATION: carry a visual, or say in one line why there is none.
    # Silence is the only thing that fails.
    # No `class="mermaid"` (BL-328). It counted as a visual and nothing in the
    # kit or the wrapper renders it — a local artifact is a file:// document with
    # no external host allowed, so a mermaid block IS its own source text. The
    # page passed the check and showed the reader a wall of `graph TD`. A fleet
    # census on 2026-09-07 found zero pages using it, so removing the value costs
    # nothing and makes the route's retirement real in the code.
    has_visual = bool(re.search(r'<svg|<img|<canvas', text, re.I))
    try:
        reason = visual_declaration(text)
    except Exception as e:                          # noqa: BLE001 — fail closed
        report("consult", f"the visual-declaration scan did not run ({e})")
        reason = "scan failed"
    if not has_visual and not reason:
        report("consult", 'no visual and no <meta name="consult-visual" '
               'content="none: why"> — a consultation opens with the '
               'drawing when the subject has a shape, and states the '
               'reason when it does not')
    # The PLACEHOLDER is judged whether or not the page carries a visual, and
    # that is the half this rule was missing. A page can hold an image and
    # still declare `none: replace this with the reason` — the template does,
    # since the gallery block below it ships example tiles — and the old
    # placement read the image as the answer and let the un-answered
    # declaration through. A declaration that says "none" on a page that has
    # one is not a smaller violation than silence; it is a false statement the
    # next round is written from.
    elif reason and PLACEHOLDER_REASON.search(reason):
        report("consult", f'the consult-visual declaration is still the '
               f'template placeholder ("{reason}") — that is the '
               f'instruction to write a reason, not a reason. Replace it '
               f'with why this page has no drawing, or with svg/img')

    # The template's own recorded regression: with only the media query, an
    # explicitly-toggled dark page keeps the light sticky bar and the
    # blank-count lands at 1.31:1. A page derived from the template carries
    # both forms. `[^{]*` so the two tokens sit inside ONE selector — a comment
    # spelling them with a rule in between does not satisfy it.
    if not re.search(r'data-theme="dark"[^{]*consult-bar',
                     text.replace("\n", "").replace("\r", "")):
        report("consult", 'no :root[data-theme="dark"] rule for .consult-bar '
               '— the blank-count status is unreadable on an explicitly-dark '
               'page')

    return fails



# BL-504: every ask marker owes a checkable duty, judged against the page the
# reader actually answered — never against `.aidex-artifact-prev/<stem>.html`,
# which BL-475's `[show-me]` rule used and which is advanced on EVERY passing
# wrap (for id stability). A round shipped 7 [show-me] items and 0 figures
# because the first re-wrap inside the round (the visual grader's own fixes)
# already moved that baseline, so the mtime-vs-baseline test this replaces
# silently downgraded to a WARN before the reader ever saw the round.
#
# `save-reply.sh` (dash/save_reply.py) is the only writer of both files below:
# it snapshots the page being answered to `.aidex-artifact-prev/<stem>.answered.html`
# and the paste to `.aidex-artifact-prev/<stem>.reply.md`, at the moment the
# reply comes in — never touched by a wrap. So there is no mtime test here: once
# a reply is saved, EVERY later wrap of the page is judged against that same
# answered snapshot, until a newer reply replaces it.
REPLY_ITEM = re.compile(r"^### (\S+) · ", re.M)
# Generic — every marker in the 02-local-first-artifacts.md asks table pastes
# this shape (composer.js `readItem`/`markLabel`): `- [token]` on its own line.
ASK_LINE = re.compile(r"^- \[([a-z][a-z-]*)\]\s*$", re.M)
VISUAL_TAG = re.compile(r"<(?:svg|img|canvas|figure)\b", re.I)
FIGURE_BLOCK = re.compile(r"<figure\b[^>]*>.*?</figure\s*>", re.I | re.S)
BARE_VISUAL = re.compile(r"<(?:svg|img|canvas)\b", re.I)
EXAMPLE_BLOCK = re.compile(r'<table\b|class=["\'][^"\']*\bexample\b', re.I)
NORMALIZE_PUNCT = re.compile(r"[^\w\s]", re.U)

# What the next round OWES for each marker (02-local-first-artifacts.md, the
# asks table's "Gate" column). Printed by save-reply.sh, one line per marked
# item, and referenced in the check failures below so the two never drift.
MARKER_DUTIES = {
    "show-me": ("a figure, image or diagram inside the item — launch "
                "figure-sonnet or verify-browser-opus BEFORE the page brief, "
                "never more prose"),
    "more-examples": ("more visuals, tables or example blocks than the last "
                       "round carried"),
    "explain-simpler": "fewer words than the last round — cut, never expand",
    "reframe": ("a DIFFERENT question, not the same one re-explained — split "
                "it or drop it, and say in one line what changed"),
    "explain-state": ("the files by name and the current value printed from "
                       "the tree"),
    "explain-options": ("each option's consequence and cost, not a defence "
                         "of the recommendation"),
    "explain-why": "the evidence for the claim, not the recommendation again",
    "question": "the reader's own question, answered in the notes, first",
    "page-defect": "fix the page defect in place without re-asking",
    "not-now": "carry it open on the ledger; do not redraw it",
}
STACKED_DUTY = ("rewrite from the concrete situation with a figure; do not "
                "answer marker by marker")
# Markers whose duty is only judged by the item's normalised body changing —
# an ask answered with the identical item is the one shape every one of them
# fails the same way.
BODY_CHANGE_MARKERS = {"explain-state", "explain-options", "explain-why", "question"}
# `page-defect` and `not-now` are never a REASON to ask marker-by-marker: they
# report a defect in the page itself or a deferral, neither is a gap in the
# EXPLANATION, so neither counts toward the 3+ stack ceiling (review finding 2,
# 2026-09-29) and `page-defect` always gets its own printed duty even beside a
# stack that collapses the rest.
NO_STACK_MARKERS = {"page-defect", "not-now"}
# `page-defect` and `not-now` carry no per-item CHECK at all: neither of the
# `if markset & ...` branches below names them, and that omission IS the rule.


def marker_duties_of(reply_text):
    """[(id, [marker, ...])], each list the UNION of every mark that id has
    ever carried across the whole text, in first-seen order — not per block.

    A saved reply can hold more than one `### <id> · ...` block for the same
    id: `save_reply.save_reply` APPENDS a follow-up under a
    `<!-- reply saved ... -->` separator rather than replacing the file while
    a duty is still outstanding (BL-504 finding 1), so an id's marks must be
    read from the ENTIRE accumulated text, never from the block nearest the
    end — a later block that happens to mark fewer things must not silently
    drop what an earlier block asked for."""
    order = []
    marks_by_id = {}
    heads = list(REPLY_ITEM.finditer(reply_text))
    for k, h in enumerate(heads):
        end = heads[k + 1].start() if k + 1 < len(heads) else len(reply_text)
        ident = h.group(1)
        marks = ASK_LINE.findall(reply_text, h.end(), end)
        if not marks:
            continue
        if ident not in marks_by_id:
            marks_by_id[ident] = []
            order.append(ident)
        for m in marks:
            if m not in marks_by_id[ident]:
                marks_by_id[ident].append(m)
    return [(i, marks_by_id[i]) for i in order]


def _example_count(body):
    """Visuals + tables + example blocks inside one item's body HTML, with
    comments/script/style stripped first (a commented-out example, or the
    literal string "example" sitting in a `<style>`/`<script>` block, is not
    a worked example the reader can see) — the instrument `[more-examples]`
    asks for more of. A `<figure>` wrapping its own `<svg>`/`<img>`/`<canvas>`
    counts ONCE: re-wrapping the SAME image in a `<figure>` must not look like
    a second example (review finding 3, 2026-09-29)."""
    clean = strip_html_comments(strip_script_style(body))
    figures = FIGURE_BLOCK.findall(clean)
    remainder = FIGURE_BLOCK.sub(" ", clean)
    return (len(figures) + len(BARE_VISUAL.findall(remainder))
            + len(EXAMPLE_BLOCK.findall(remainder)))


def _reframe_key(text):
    """A STRICTER fingerprint than the plain body-changed comparison every
    other marker uses: lower-cased, with punctuation removed — a comma added
    or a capital changed is still the SAME question, and `[reframe]` demands
    a genuinely different one, never a copy-edit of the old one (review
    finding 4, 2026-09-29)."""
    return re.sub(r"\s+", " ", NORMALIZE_PUNCT.sub("", text.casefold())).strip()


def check_marker_duties(new_path):
    """(fails, warns) for the round built at new_path, one FAIL per item whose
    marked duty the new round does not carry out, judged against
    `.aidex-artifact-prev/<stem>.answered.html` (save_reply.marker_duties_of
    reads the paste; save-reply.sh writes both files). With no reply saved for
    this page at all, the check cannot run and says so instead of passing
    silently. An item decided in the new round (data-decided) is exempt — it
    left the question set, so nothing about it is being re-asked."""
    name = os.path.basename(new_path)
    text = open(new_path, encoding="utf-8", errors="replace").read()
    bodies = dict(consult_item_bodies(text))
    if not bodies:
        return [], []
    prev_dir = os.path.join(os.path.dirname(os.path.abspath(new_path)),
                            ".aidex-artifact-prev")
    stem = os.path.splitext(name)[0]
    reply = os.path.join(prev_dir, stem + ".reply.md")
    answered = os.path.join(prev_dir, stem + ".answered.html")
    if not os.path.isfile(reply) or not os.path.isfile(answered):
        return [], [("consult-marker-duties", name,
                     f"no reply saved for this page ({os.path.relpath(reply)} "
                     f"or {os.path.relpath(answered)} is missing) — run "
                     f"save-reply.sh with the reader's paste before rewriting, "
                     f"so every marked item is checked")]
    paste = open(reply, encoding="utf-8", errors="replace").read()
    answered_text = open(answered, encoding="utf-8", errors="replace").read()
    answered_bodies = dict(consult_item_bodies(answered_text))
    decided_now = decided_ids(text)
    try:
        import wrap_report
        new_texts = wrap_report.question_texts(text)
        answered_texts = wrap_report.question_texts(answered_text)
    except Exception as e:                          # noqa: BLE001 — fail closed
        return [("consult-marker-duties", name,
                 f"the item-text scan did not run ({e})")], []

    fails, warns = [], []
    for ident, marks in marker_duties_of(paste):
        if ident in decided_now:
            continue
        if ident not in bodies or ident not in answered_bodies:
            where = "the new page" if ident not in bodies else "the answered snapshot"
            warns.append(("consult-marker-duties", name,
                f"the reply marks {ident}, which is not in {where} — the "
                f"reply may have been saved against the wrong page"))
            continue
        new_body, old_body = bodies[ident], answered_bodies[ident]
        new_txt, old_txt = new_texts.get(ident, ""), answered_texts.get(ident, "")
        markset = set(marks)
        # `page-defect`/`not-now` report a page defect or a deferral, neither
        # a gap in the explanation, so neither counts toward the 3+ ceiling
        # (review finding 2) — only the REAL asks stack.
        stack_eligible = markset - NO_STACK_MARKERS
        stacked = len(stack_eligible) >= 3
        if stacked or "show-me" in markset:
            if not VISUAL_TAG.search(new_body):
                fails.append(("consult-marker-duties", name,
                    f"{ident} was marked [show-me]"
                    f"{' among 3+ stacked asks' if stacked else ''} and this "
                    f"round answers it with no figure, image or diagram inside "
                    f"the item — the ask is for a different instrument (a "
                    f"mockup, a diagram, a before/after, an example), not more "
                    f"prose"))
        if stacked:
            if new_txt == old_txt:
                fails.append(("consult-marker-duties", name,
                    f"{ident} carries 3+ stacked asks ({', '.join(sorted(stack_eligible))}) "
                    f"and this round is not rewritten — {STACKED_DUTY}"))
            continue                       # stacked overrides the per-marker rules
        if "more-examples" in markset:
            if _example_count(new_body) <= _example_count(old_body):
                fails.append(("consult-marker-duties", name,
                    f"{ident} was marked [more-examples] and this round "
                    f"carries no more visuals, tables or example blocks than "
                    f"the last one"))
        if "explain-simpler" in markset:
            if len(new_txt.split()) >= len(old_txt.split()):
                fails.append(("consult-marker-duties", name,
                    f"{ident} was marked [explain-simpler] and this round is "
                    f"not shorter than the last one — explain plainer, not "
                    f"longer"))
        if "reframe" in markset:
            # Stricter than the explain-* comparison below: a punctuation- or
            # case-only edit is still the SAME question (review finding 4).
            if _reframe_key(new_txt) == _reframe_key(old_txt):
                fails.append(("consult-marker-duties", name,
                    f"{ident} was marked [reframe] and this round asks the "
                    f"same question (a copy-edit is not a reframe) — reframe "
                    f"it into a different question, never just re-explain it"))
        body_marks = markset & BODY_CHANGE_MARKERS
        if body_marks and new_txt == old_txt:
            which = ", ".join(f"[{m}]" for m in sorted(body_marks))
            fails.append(("consult-marker-duties", name,
                f"{ident} was marked {which} and this round answers it with "
                f"the identical item — the ask was for what is missing, not a "
                f"re-render of the same text"))
    return fails, warns


def decided_ids(text):
    """The `data-id`s of items carrying `data-decided` (BL-359's own mark). An
    item decided in the round being checked left the question set, so a
    marker duty against it is answered and exempt (BL-504)."""
    out = set()
    for m in ITEM_OPEN.finditer(text):
        if ITEM_DECIDED.search(m.group(0)):
            ident = next(g for g in m.groups()[1:] if g is not None)
            out.add(ident)
    return out


def check_prev(new_path, prev_path):
    """Requirement 1 across regenerations: an id kept between two versions
    still names the same claim, and no id disappears. A SHIFT is an id whose
    title moved; a DROP is an id the previous version had and this one lacks.
    BL-396: the drop was documented as "a claim may be closed out" and the
    check stayed green while a string-slice rewrite of one block removed two
    decided items from a live consultation for two rounds. A closed claim
    stays on the page (§8.1: ids are never removed); the one exit is the page
    declaring `consult-surfaces: none`, which is a closed page, not a round.

    Fails CLOSED: a diff that did not run is indistinguishable from a diff
    that passed, which is BL-126 reproduced inside the checker written to
    close it."""
    fails, notes = [], []
    if not os.path.isfile(prev_path) or not os.access(prev_path, os.R_OK):
        fails.append(("consult-ids", os.path.basename(prev_path),
                      "--prev is not a readable file (missing, a directory, "
                      "or unreadable) — nothing to compare against"))
        return fails, notes
    try:
        old, new = id_title_map(prev_path), id_title_map(new_path)
        translated = _page_lang(prev_path) != _page_lang(new_path)
    except Exception as e:                          # noqa: BLE001 — fail closed
        fails.append(("consult-ids", os.path.basename(new_path),
                      f"the id-stability diff did not run ({e}) — a check "
                      f"that is skipped is indistinguishable from a check "
                      f"that passed, so this fails rather than reporting no "
                      f"change"))
        return fails, notes
    moved = [i for i in sorted(set(old) & set(new)) if old[i] != new[i]]
    dropped = sorted(set(old) - set(new))
    if dropped:
        new_text = open(new_path, encoding="utf-8", errors="replace").read()
        if not surfaces_declaration(new_text):
            for i in dropped:
                fails.append(("consult-ids", os.path.basename(new_path),
                              f'id dropped between rounds — {i} ("{old[i]}") '
                              f'was on the previous version and is not on this '
                              f'one. Ids are never removed: keep the item and '
                              f'mark it decided or closed; only a page declaring '
                              f'consult-surfaces: none may drop ids'))
    # BL-323: a TRANSLATION changes every title by definition, and that is not
    # the failure this check exists for. On a real 12-item page it produced 12
    # FAILs at once, and the remedy the message proposes — append a new id — is
    # wrong precisely here: the claim behind each id is unchanged, and the
    # page's own ledger and the brief beside it anchor on those ids by name.
    # Waivers were no help either: split_waived() runs only in the census, never
    # on the authoring-time check wrap_report.py invokes, so the FAIL could not
    # be waived at the moment it fired; unblocking it meant moving
    # .aidex-artifact-prev/ out of the tree by hand and resetting the round meta.
    #
    # Downgraded, never silenced. The reader still has to see which ids moved,
    # because a translation is also the easiest place to change a claim without
    # noticing. And the discriminant is the LANGUAGE PAIR: within one language
    # this is a failure exactly as before.
    for i in moved:
        if translated:
            notes.append(("consult-ids", os.path.basename(new_path),
                          f'{i}: the title changed with the page\'s language '
                          f'({_page_lang(prev_path)} → {_page_lang(new_path)}) '
                          f'— was "{old[i]}", now "{new[i]}". Read as a '
                          f'translation, not a moved claim; check it is one'))
        else:
            fails.append(("consult-ids", os.path.basename(new_path),
                          f'id reused for a different claim — {i}: was '
                          f'"{old[i]}", now "{new[i]}". Append a new id '
                          f'instead; a reply about that id now points '
                          f'somewhere else'))
    return fails, notes


# --- census: the contract, re-judged after the fact ---------------------------
# The contract used to be evaluated exactly once, at the moment of the wrap, and
# never again. Two holes, both observed: a page that PASSED and then the
# contract evolved past it the same evening (a field report fails today with
# rules that landed ten hours after it was written), and a page that never went
# through the wrapper at all (BL-168), which no check ever saw. An absence
# claim needs a census.
#
# Waivers make the census livable: retroactive drift is EXPECTED, and a sweep
# whose failures cannot be settled becomes noise nobody reads. The format and
# semantics are validate.py's (.aidex-waivers, `<rule> | <path> | <anchor> |
# <reason> [| <date>]`, path project-root-relative, sha256-prefix anchors that
# resurface the finding when the file changes) with the rule spelled
# `artifact-<check>`, e.g. `artifact-layout | .context/reports/x.html | - |
# accepted full-bleed`.

WAIVER_ANCHOR = re.compile(r"^sha256:([0-9a-f]{8,64})$")
ISO_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def load_waivers(context_dir):
    """[(rule, path, anchor, reason)] from <context>/.aidex-waivers."""
    out = []
    wp = os.path.join(context_dir, ".aidex-waivers")
    if not os.path.isfile(wp):
        return out
    for raw in open(wp, encoding="utf-8", errors="replace").read().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) < 4 or not parts[0] or not parts[1]:
            continue
        tail = parts[3:]
        reason = " | ".join(tail[:-1]) if (len(tail) > 1
                                           and ISO_DATE.match(tail[-1])) \
            else " | ".join(tail)
        out.append((parts[0], parts[1], parts[2] or "-", reason))
    return out


def _anchor_matches(anchor, project_root, relpath):
    """"-" always matches; a sha256 prefix matches while the file's content
    still starts with it — any change resurfaces the finding."""
    if anchor in ("", "-"):
        return True
    m = WAIVER_ANCHOR.match(anchor)
    if not m:
        return False
    target = os.path.join(project_root, relpath)
    if not os.path.isfile(target):
        return False
    import hashlib
    try:
        digest = hashlib.sha256(open(target, "rb").read()).hexdigest()
    except OSError:
        return False
    return digest.startswith(m.group(1))


def split_waived(failures, context_dir, project_root):
    """(active, n_waived) — a waiver keys on (artifact-<check>, relpath)."""
    keys = set()
    for rule, path, anchor, _ in load_waivers(context_dir):
        if _anchor_matches(anchor, project_root, path):
            keys.add((rule, path))
    active, waived = [], 0
    for check, relpath, msg in failures:
        if ("artifact-" + check, relpath) in keys:
            waived += 1
        else:
            active.append((check, relpath, msg))
    return active, waived


def _resolve_census_root(arg):
    """(walk_root, context_dir, project_root). The waiver base is the project
    root — the same base validate.py prints paths against."""
    if arg:
        root = os.path.realpath(arg)
        if os.path.basename(root) == ".context":
            return root, root, os.path.dirname(root)
        if os.path.isdir(os.path.join(root, ".context")):
            ctx = os.path.join(root, ".context")
            return ctx, ctx, root
        return root, root, root
    # No argument: the project the cwd belongs to, via the shared resolver.
    import wrap_report                              # lazy — avoids an import cycle
    ctx = wrap_report.find_context_dir(os.getcwd())
    if not ctx or not os.path.isdir(ctx):
        return None, None, None
    return ctx, ctx, os.path.dirname(ctx)


def _skip_part(path):
    parts = path.split(os.sep)
    return ".aidex-artifact-prev" in parts or "_archive" in parts


# The age at which a build lock stops meaning "an agent is working on this page".
# artifact-open-once.sh stops refusing the open at the same 20 minutes; the two must
# not drift, or the sweep calls residue what the hook still treats as a live build.
BUILD_LOCK_STALE_AFTER = 20 * 60


def baseline_hygiene(walk_root):
    """Dead .aidex-artifact-prev content, as note strings with the exact rm to
    run. Report-only, never deletes: a baseline is dead when its artifact is
    gone (nothing will ever compare against it) or when the whole set was moved
    into _archive/ (the artifact is closed, so no wrap runs at that path
    again). Without this, every report is silently doubled on disk forever —
    field-observed following archived items into _archive/."""
    notes = []
    for dirpath, dirnames, filenames in os.walk(walk_root):
        for d in list(dirnames):
            if d != ".aidex-artifact-prev":
                continue
            bdir = os.path.join(dirpath, d)
            if "_archive" in dirpath.split(os.sep):
                notes.append(f"dead baseline (archived artifact): rm -r "
                             f"'{bdir}'")
                dirnames.remove(d)
                continue
            entries = os.listdir(bdir)
            # Five spellings live here and all of them are the PAGE's, not files with
            # a life of their own: the baseline `<page>`, its source `<page>.body`
            # (`.body.md`), and the last attempt that did not pass — `<page>.failed`
            # and its own source `<page>.failed.body` (`.failed.body.md`). So an
            # entry is keyed to the page its name reduces to, and every one of them
            # is dead state once that page is gone.
            #
            # There is no exemption for "the page never existed". One was tried on
            # 2026-09-20 and removed the same day: it used "no baseline entry" as a
            # proxy for "first build in progress", which is also the shape of a page
            # written before baselines existed that failed once and was then deleted
            # (88 KB, silent forever), and it was not idempotent — running the `rm`
            # the note asked for removed the baseline entry and turned the other two
            # into exempt ones. What the author needs is not silence but the truth
            # about WHAT each entry is, which is what the notes say below.
            # `.building` is the sixth spelling (2026-09-20): the lock a delegated
            # build keeps while it is still writing the page. It reduces to the same
            # page, so a live build is not residue and is not reported.
            def page_of(entry):
                entry = re.sub(r"\.building$", "", entry)
                return re.sub(r"\.(failed)?(\.?body(\.md)?)?$", "", entry)

            for e in sorted(entries):
                page = page_of(e)
                path = os.path.join(bdir, e)
                page_there = os.path.exists(os.path.join(dirpath, page))
                # A lock is judged on its AGE, not on whether the page is there:
                # nothing removes it but `--done`, and once it is older than the
                # window the hook stops honouring it, so an abandoned lock beside a
                # perfectly good page is exactly as invisible as one beside no page.
                # The page's presence only changes what the note has to say.
                if e.endswith(".building"):
                    # A lock with no page beside it is the ORDINARY shape of a build
                    # in progress: the page does not exist until the first wrap
                    # passes, and a first wrap that fails rolls it back off disk
                    # while the agent keeps working. This sweep runs on every wrap,
                    # so reporting a fresh one would fire on every failing build.
                    # Only an abandoned lock is residue, and abandoned is the same
                    # 20 minutes artifact-open-once.sh stops blocking at — one
                    # definition, two consumers.
                    try:
                        age = time.time() - os.path.getmtime(path)
                    except OSError:
                        continue
                    if -BUILD_LOCK_STALE_AFTER <= age <= BUILD_LOCK_STALE_AFTER:
                        continue
                    where = ("the page is there, so the build landed and never ran "
                             "--done" if page_there else
                             "with no page beside it — the build was abandoned")
                    notes.append(f"build lock nobody cleared ({where}): rm '{path}'")
                    continue
                # Every other spelling is keyed to its page and is dead only once
                # that page is gone.
                if page_there:
                    continue
                if e.endswith(".body") or e.endswith(".body.md"):
                    if e.startswith(page + ".failed"):
                        # Work, not residue: nobody else has this content, and the
                        # page it was meant to become was never published (or is
                        # gone). `rm` as the only advice would throw away the draft.
                        notes.append(f"unfinished attempt (no page at "
                                     f"'{os.path.join(dirpath, page)}'): wrap it again "
                                     f"with --in '{path}', or rm it")
                    else:
                        notes.append(f"source of a deleted artifact: rm '{path}' (it is "
                                     f"the only copy of that page's content)")
                else:
                    # The baseline and the failing render are both DERIVED: whatever
                    # they were made from is either beside them or already gone.
                    notes.append(f"orphaned baseline (its artifact is gone): rm "
                                 f"'{path}'")
            if not entries:
                notes.append(f"empty baseline directory: rmdir '{bdir}'")
    return notes


def sweep_directory(dirpath, exclude=(), context_dir=None, project_root=None):
    """Re-judge the .html files sitting next to a just-written artifact.
    Returns (active_failures, n_waived) with project-root-relative names.
    Depth 1 only — the census walks trees, this keeps a wrap honest about the
    directory it just touched."""
    if _skip_part(os.path.abspath(dirpath)):
        return [], 0
    failures = []
    # realpath, not abspath: the context dir comes back from the shared
    # resolver in PHYSICAL form (pwd -P), while the caller's outdir may be the
    # logical spelling of the same place (/var vs /private/var on macOS) — and
    # a relpath across the two is ../../ garbage that no waiver key can match.
    base = os.path.realpath(project_root or dirpath)
    excluded = {os.path.realpath(x) for x in exclude}
    for e in sorted(os.listdir(dirpath)):
        p = os.path.join(dirpath, e)
        if (not e.endswith(".html") or not os.path.isfile(p)
                or os.path.realpath(p) in excluded):
            continue
        rel = os.path.relpath(os.path.realpath(p), base)
        # A neighbour is a page nobody is editing: like the census, the sweep
        # does not report the contract classes on it (ruling 2026-09-28).
        failures.extend((c, rel, m) for c, _, m in check_file(p)
                        if c != "contract" and c not in contract_defects.CHECKS)
    if context_dir:
        return split_waived(failures, context_dir, base)
    return failures, 0


def run_census(arg):
    walk_root, ctx, project_root = _resolve_census_root(arg)
    if not walk_root or not os.path.isdir(walk_root):
        print("ERROR: --census found no directory to walk (pass one, or run "
              "inside a project with a .context/)", file=sys.stderr)
        return 2
    failures, advisory, n_files = [], [], 0
    for dirpath, dirnames, filenames in os.walk(walk_root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".aidex-artifact-prev", "_archive")]
        for e in sorted(filenames):
            if not e.endswith(".html"):
                continue
            p = os.path.join(dirpath, e)
            n_files += 1
            rel = os.path.relpath(p, project_root)
            for c, _, m in check_file(p):
                (advisory if c in CENSUS_ADVISORY else failures).append((c, rel, m))
    active, waived = split_waived(failures, ctx, project_root)
    # Waived here too, and counted into the same total: a page that answered a
    # finding once should not keep saying it, whichever channel it comes out of.
    adv_active, adv_waived = split_waived(advisory, ctx, project_root)
    waived += adv_waived
    for check, name, msg in active:
        print(f"  FAIL [{check}] {name}: {msg}")
    for check, name, msg in adv_active:
        print(f"  WARN [{check}] {name}: {msg}")
    for note in baseline_hygiene(walk_root):
        print(f"  NOTE [baselines] {note}")
    if waived:
        print(f"waived: {waived}")
    if active:
        print(f"{len(active)} contract violation(s) across {n_files} file(s). "
              f"Fix by re-wrapping, or waive a retroactive drift with "
              f"'artifact-<check> | <path> | - | <reason>' in "
              f"{os.path.join(ctx, '.aidex-waivers')}")
        return 1
    print(f"artifact census OK ({n_files} file(s))")
    return 0


def main(argv):
    prev = None
    census = False
    census_arg = None
    files = []
    args = list(argv)
    while args:
        a = args.pop(0)
        if a == "--prev":
            if not args:
                print("ERROR: --prev needs a file", file=sys.stderr)
                return 2
            prev = args.pop(0)
        elif a == "--census":
            census = True
            if args and not args[0].startswith("--"):
                census_arg = args.pop(0)
        else:
            files.append(a)

    if census:
        if files or prev is not None:
            print("ERROR: --census takes at most a directory, not files or "
                  "--prev", file=sys.stderr)
            return 2
        return run_census(census_arg)

    if not files:
        print("ERROR: usage: check-artifact.sh <file.html> [...] "
              "[--prev <old.html>]", file=sys.stderr)
        return 2
    # --prev compares ONE page against its own previous version; with several
    # files there is no way to say which prior belongs to which, and guessing
    # would report a renumbering that never happened.
    if prev is not None and len(files) != 1:
        print("ERROR: --prev takes exactly one file to compare against",
              file=sys.stderr)
        return 2

    failures, warnings = [], []
    for f in files:
        failures.extend(check_file(f))
        try:
            warnings.extend(warn_file(f))
        except Exception as e:                      # noqa: BLE001 — advisory
            print(f"  NOTE [warnings] the advisory scan did not run ({e})")

    prev_notes = []
    if prev is not None:
        prev_fails, prev_notes = check_prev(files[0], prev)
        failures.extend(prev_fails)
        duty_fails, duty_warns = check_marker_duties(files[0])
        failures.extend(duty_fails)
        warnings.extend(duty_warns)

    for check, name, msg in failures:
        print(f"  FAIL [{check}] {name}: {msg}")
    for check, name, msg in prev_notes:
        print(f"  NOTE [{check}] {name}: {msg}")
    # Printed on a passing file too, and that is the whole point: a warning
    # about a page that failed is drowned by the failure the author is fixing,
    # while the two shapes these catch ship on pages that pass everything.
    for check, name, msg in warnings:
        print(f"  WARN [{check}] {name}: {msg}")
    if not failures:
        print(f"artifact contract OK ({len(files)} file(s))"
              + (f" — {len(warnings)} warning(s), exit unaffected"
                 if warnings else ""))
        return 0
    print(f"{len(failures)} contract violation(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

