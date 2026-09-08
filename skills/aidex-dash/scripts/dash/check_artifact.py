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
  layout       a kit page keeps its content inside .page / .main (BL-177),
               and every table inside a scrolling wrapper
  consult      a page the reader must ANSWER carries the §8 shape
  consult-shape every decision inside a block (`.consult-group`), every block
               with a decision, nothing but blocks between the first block and
               the general notes, only header/figure/ledger before them (BL-247)
  consult-ids  with --prev: an id kept between two regenerations still names
               the same claim
  svg-contrast figure text below 4.5:1 against what it is painted on, in either
               theme (BL-330). The one check with two severities: it FAILS a
               named file — the wrap — and only WARNS in `--census`, because a
               page being written must not ship unreadable text while the same
               finding on a page nobody is editing is noise no one can clear.

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
  consult-facts a paragraph inside a block context or an item body carrying four
               or more `<code>` tokens or semicolon-separated clauses — the shape
               of "N things with their state and verdict" written as prose, which
               the reader returns unread; rows, not a paragraph (BL-269, BL-270)
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
import html as _html
import os
import re
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


def visible_text(text):
    """The page as a reader sees it: no scripts, styles, comments or tags."""
    own = strip_html_comments(strip_script_style(text))
    return re.sub(r'<[^>]+>', ' ', own)


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
    """Every data-id item: (id, has_title, has_surface, has_notes). The unit is
    the ITEM, never the box count: v1 counted `<textarea` occurrences against
    data-id, which told a radio-only page it had ids for boxes that did not
    exist."""
    items = []
    for m in ITEM_OPEN.finditer(text):
        # A block (`.consult-group`) carries data-id/data-title so --prev can
        # hold its id stable, but it is a context, not a claim: it has no
        # reply surface of its own and is judged by check_shape instead.
        if GROUP_CLASS.search(m.group(0)):
            continue
        tag = m.group(1)
        ident = next(g for g in m.groups()[1:] if g is not None)
        body = _subtree(text, tag, m.end())
        # The open tag itself may BE the surface (an <input data-id=...>).
        items.append((
            ident,
            bool(ITEM_TITLE.search(m.group(0))),
            bool(ITEM_SURFACE.search(body) or ITEM_SURFACE.search(m.group(0))),
            bool(ITEM_NOTES.search(body) or ITEM_NOTES.search(m.group(0))),
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
    neither reports."""
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


def consult_item_bodies(text):
    """[(id, body)] for every data-id item. A second walk rather than a wider
    return from `consult_items`: that one answers the contract in booleans and
    is read by the failure path, and warnings must not be able to change it."""
    out = []
    for m in ITEM_OPEN.finditer(text):
        ident = next(g for g in m.groups()[1:] if g is not None)
        out.append((ident, _subtree(text, m.group(1), m.end())))
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
    FACTS_MIN or more <code> tokens or semicolon-separated clauses."""
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
        if codes >= FACTS_MIN or clauses >= FACTS_MIN:
            excerpt = ' '.join(prose.split())
            out.append((codes, clauses, excerpt[:60]))
    return out


# --- svg-text: label geometry estimated from viewBox coordinates (BL-310) ------
# Per-character advance as a fraction of font-size, calibrated on 2026-09-03
# against getBBox() of 52 labels in system-ui: digits and capitals ~0.6, the
# narrow glyphs ~0.3, everything else ~0.52. A single 0.55 constant reported a
# 26 px gap as a 13 px collision; the table lands within ±5 % of the rendering.
SVG_TAG = re.compile(r'<(/?)([a-zA-Z][\w:-]*)([^>]*?)(/?)>', re.S)
SVG_ATTR = re.compile(r'([\w:-]+)\s*=\s*(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))')
SVG_BLOCK = re.compile(r'<svg\b([^>]*)>(.*?)</svg>', re.S | re.I)
SVG_NARROW = set("iljtfIr.,:;'|!()[] ")
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


def svg_css_fonts(text):
    """{'.cls': (size|None, bold, mono), 'text': ...} from every <style>
    block. Pages set label sizes in CSS classes at least as often as in
    attributes, and a class read as 16 px reported 10 px labels colliding."""
    fonts = {}
    for style in re.findall(r'<style\b[^>]*>(.*?)</style>', text, re.S | re.I):
        style = re.sub(r'/\*.*?\*/', '', style, flags=re.S)
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
        elif ch in SVG_WIDE:
            w += 0.85
        elif ch.isdigit() or ch.isupper():
            w += 0.6
        else:
            w += 0.52
    return w * size * (1.04 if bold else 1.0)


def svg_geometry(svg, fonts=None, fills=None):
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
    fills = fills or {}
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
    for m in SVG_TAG.finditer(svg):
        closing, tag, raw, selfclosed = m.group(1), m.group(2).lower(), m.group(3), m.group(4)
        if cur is not None:
            if tag == 'tspan' and not closing and not selfclosed:
                if not tsp:
                    bare.append(svg[last:m.start()])
                tsp.append((m.end(), _svg_tspan_fill(_svg_attrs(raw), cur[9], fills)))
            elif tag == 'tspan' and closing and tsp:
                st, tfl = tsp.pop()
                if re.sub(r'<[^>]+>', ' ', svg[st:m.start()]).strip():
                    glyph_fills.add(cur[8] if tfl is None else tfl)
                if not tsp:
                    last = m.end()
            elif closing and tag == 'text':
                start, f, an, x, y, sk, b, mo, fl, _cls = cur
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
        nfl = fill
        if tag in ('text', 'rect') and tag in fills:
            nfl = fills[tag]
        for cls in d.get('class', '').split():
            if '.' + cls in fills:
                nfl = fills['.' + cls]
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
                   d.get('class', '').split())
            tsp, glyph_fills, bare, last = [], set(), [], m.end()
        elif tag == 'rect' and not nsk:
            rx, ry = _svg_num(d.get('x'), 0.0) + tx + dx, _svg_num(d.get('y'), 0.0) + ty + dy
            rects.append((rx, ry, rx + _svg_num(d.get('width'), 0.0),
                          ry + _svg_num(d.get('height'), 0.0), nfl))
        elif tag in SVG_CONTAINERS and not selfclosed:
            stack.append((fs, anchor, tx, ty, skip, bold, mono, fill))
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
    v = v.strip().strip('"\'')
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
    return None


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
    """{'.cls': rgb | SVG_UNREADABLE, 'text': …} for one CSS source.

    Two rules, and the second is what keeps the leak honest in both directions.
    A selector carrying an `#id` applies ONLY to that figure, so it is kept when
    `own_id` matches and dropped otherwise — modelling every id-scoped rule as
    page-wide is what made a correctly scoped page look broken. And a fill we
    cannot read is recorded as SVG_UNREADABLE rather than omitted, so it
    overrides an inherited literal instead of falling through to it."""
    out = {}
    for rule in SVG_CSS_RULE.finditer(css):
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
            # BL-347: a `…>tspan` (or `… tspan`) selector lands on the GLYPHS,
            # one level below the <text> a plain leaf key models. It is keyed
            # with the compound it hangs off — `.actor>tspan` — and never flat
            # on `tspan`: mermaid's stylesheet ends with
            # `.noteText>tspan{fill:#fff}`, and a flat key would let that last
            # rule paint every label in the figure white. ONE level only; the
            # full ancestor chain, source order and specificity are BL-348.
            # Descendant and child combinators are split together so
            # `text.actor > tspan` cannot read `>` as its own scope.
            # The leaf must be a BARE `tspan`. A class-qualified `tspan.legend`
            # is the same flat-key trap seen from the other side: the class
            # would be discarded and the rule handed to every tspan in the
            # figure. It falls through to the leaf path below and is dropped,
            # exactly as it was before this scoping existed — matching a
            # tspan by its own class is BL-348's job, with the rest of the
            # cascade.
            toks = [t for t in re.split(r'\s*>\s*|\s+', sel)
                    if t and not t.startswith('#')]
            if toks and toks[-1] == 'tspan':
                out[svg_tspan_key(toks[-2] if len(toks) > 1 else None)] = colour
                continue
            leaf = sel.split()[-1]                  # what the declaration lands on
            if re.fullmatch(r'\.[\w-]+', leaf) or leaf in SVG_PAINTED:
                out[leaf] = colour
    return out


def svg_tspan_key(scope):
    """The `fills` key for a tspan rule hanging off `scope` (the compound
    immediately before it, or None). A class in the scope wins over its element
    name, because that is what the figures in the field are written with."""
    if not scope:
        return 'tspan'
    classes = re.findall(r'\.[\w-]+', scope)
    if classes:
        return classes[-1] + '>tspan'
    m = re.match(r'^[\w-]+', scope)
    return (m.group(0) + '>tspan') if m else 'tspan'


def _svg_tspan_fill(d, parent_classes, fills):
    """The fill DECLARED on one <tspan>, or None when nothing declares one and
    the tspan simply inherits its <text>. Same cascade as the <text> one level
    up, weakest first: a bare `tspan` rule, a rule scoped to the parent's
    element then to one of its classes, the tspan's own class rule, then its
    own attribute."""
    fl = fills.get('tspan')
    if 'text>tspan' in fills:
        fl = fills['text>tspan']
    for cls in parent_classes:
        if '.' + cls + '>tspan' in fills:
            fl = fills['.' + cls + '>tspan']
    for cls in d.get('class', '').split():
        if '.' + cls in fills:
            fl = fills['.' + cls]
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
        for rule in SVG_CSS_RULE.finditer(block.group(1)):
            m = CSS_BG.search(rule.group(2))
            colour = svg_literal_colour(m.group(1).split()[0]) if m else None
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
            for rule in SVG_CSS_RULE.finditer(block.group(1)):
                for sel in rule.group(1).split(','):
                    sel = sel.strip()
                    if not sel or '#' in sel:
                        continue
                    head = sel.split()[0]
                    if head in SVG_PAINTED:
                        out.append(
                            f"svg #{n}: '{sel}' — an embedded <style> is a "
                            f"stylesheet in the PAGE, not in the figure, so "
                            f"this paints every <{head}> in the document and "
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
    leaked = {}
    for block in SVG_STYLE_BLOCK.finditer(body):
        leaked.update(svg_css_fills(block.group(1)))
    backgrounds = page_backgrounds(text)
    measured = unmeasured = 0
    for n, m in enumerate(SVG_BLOCK.finditer(body), 1):
        own_id = _svg_attrs(m.group(1)).get('id')
        wrap = wrapper_ground(body[:m.start()], backgrounds)
        fills = dict(leaked)
        for block in SVG_STYLE_BLOCK.finditer(m.group(2)):
            fills.update(svg_css_fills(block.group(1), own_id))
        texts, rects = svg_geometry(m.group(2), fonts, fills)
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
                if rx0 <= cx <= rx1 and ry0 <= cy <= ry1 and (x1 - x0) > (rx1 - rx0) + slack:
                    out.append(f"svg #{n}: '{label}' is wider than the box it sits in "
                               f"(estimated {x1 - x0:.0f} px in a {rx1 - rx0:.0f} px rect)")
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


# Checks that FAIL a named file but only WARN in the census. One entry today.
CENSUS_ADVISORY = ("svg-contrast",)


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
    if KIT_STAMP.search(flat):
        for cls in ("page", "main"):
            if not re.search(r'class=["\'](?:[^"\']*\s)?' + cls
                             + r'(?:\s[^"\']*)?["\']', flat):
                report("layout", f'no element with class="{cls}" — the content '
                       f'is outside the kit\'s layout container, so the page '
                       f'renders full-bleed with no reading measure. Wrap it '
                       f'the way assets/artifact-kit/skeleton.html does: '
                       f'<div class="page"><main class="main">…</main>'
                       f'<aside class="rail">…</aside></div>')
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

    if not groups:
        return fails
    first = min(s for _, s, _, _ in groups)
    notes_m = NOTES_OPEN.search(text)
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
    for m in SECTION_OPEN.finditer(text, 0, first):
        body = _subtree(text, "section", m.end())
        if m.end() + len(body) > first:        # contains the first block
            continue
        rest = _strip_subtrees(body, SECHEAD_SUB)
        rest = _strip_subtrees(rest, FIGURE_OPEN)
        rest = _strip_subtrees(rest, LEDGER_SUB)
        if PROSE.search(rest):
            report(f"prose before the first block: \"{_h2_text(body)}\" — "
                   f"before the blocks only the header (title + standfirst), "
                   f"a figure and the ledger may appear. The strongest claim "
                   f"goes in the standfirst; context goes in the block that "
                   f"needs it; reference material goes after the questions")
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
        for ident, has_title, has_surface, has_notes in items:
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

        # A decided item LEAVES the question set and is summarised into the
        # ledger (02-local-first-artifacts.md § Update in place). An id sitting
        # in both is that obligation half-done: the answer was recorded and the
        # question is still being asked. What this can see is bounded, and the
        # bound is worth stating — "decided" is not a property of the markup,
        # so the ledger IS the declaration, and an item decided and never
        # written to the ledger at all stays invisible here. That half is the
        # one BL-190 actually observed and it is not mechanically reachable
        # from the page alone.
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
        still_asked = sorted({i for i, *_ in items if i and i != "notes"}
                             & settled)
        if still_asked:
            report("consult", f"decided but still asked ({' '.join(still_asked)}"
                   f") — the ledger records these as settled while the question "
                   f"set still carries them. A decided item leaves the "
                   f"questions and lives in the ledger only. (This sees only "
                   f"items the ledger names; one decided and never written "
                   f"there is invisible to any check.)")

    # ...and the page carries the general-notes item, always last, always
    # present. Matched inside a class ATTRIBUTE, never as the bare word:
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
    if not re.search(r'<svg|<img|<canvas', text, re.I):
        try:
            reason = visual_declaration(text)
        except Exception as e:                      # noqa: BLE001 — fail closed
            report("consult", f"the visual-declaration scan did not run ({e})")
            reason = "scan failed"
        if not reason:
            report("consult", 'no visual and no <meta name="consult-visual" '
                   'content="none: why"> — a consultation opens with the '
                   'drawing when the subject has a shape, and states the '
                   'reason when it does not')
        elif PLACEHOLDER_REASON.search(reason):
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


def check_prev(new_path, prev_path):
    """Requirement 1 across regenerations: an id kept between two versions
    still names the same claim. The failure is a SHIFT — the ids all still
    exist, the titles moved. An id that DISAPPEARS is not flagged: ids are
    never renumbered, but a claim is allowed to be closed out.

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
            orphans = [e for e in entries
                       if not os.path.exists(os.path.join(dirpath, e))]
            for e in orphans:
                notes.append(f"orphaned baseline (its artifact is gone): rm "
                             f"'{os.path.join(bdir, e)}'")
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
        failures.extend((c, rel, m) for c, _, m in check_file(p))
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
