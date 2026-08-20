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
  consult-ids  with --prev: an id kept between two regenerations still names
               the same claim

Exit 0 = every file passes. Exit 1 = at least one violation (each printed).
Exit 2 = usage error.
"""
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
    Only a `none:` declaration carries a reason — anything else (svg / mermaid /
    img) is a claim to have a visual, which the tag check adjudicates."""
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


# --- Requirement 1, across regenerations (--prev) -----------------------------

ID_TAG = re.compile(r'<[^>]*\bdata-id\s*=[^>]*>', re.I | re.S)
ID_ATTR = re.compile(r'\bdata-(id|title)\s*=\s*'
                     r'(?:"([^"]*)"|\x27([^\x27]*)\x27|([^\s>]+))', re.I | re.S)


def _norm_title(s):
    """A retyped title must not read as a moved claim: collapse whitespace,
    drop accents and case. Only a genuinely different claim behind a kept id
    fails."""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    return " ".join(s.split()).casefold()


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
        if not FREE_TEXT.search(flat) and not CONSULT_STRUCTURE.search(flat):
            try:
                declared = surfaces_declaration(text)
            except Exception:                       # noqa: BLE001 — fail closed
                declared = ""
            if PLACEHOLDER_REASON.search(declared):
                declared = ""
        if not declared:
            fails.extend(check_consultation(path, text, flat))

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
    if not re.search(r'<svg|<img|class="mermaid"|<canvas', text, re.I):
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
                   f'with why this page has no drawing, or with svg/mermaid/img')

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
    fails = []
    if not os.path.isfile(prev_path) or not os.access(prev_path, os.R_OK):
        fails.append(("consult-ids", os.path.basename(prev_path),
                      "--prev is not a readable file (missing, a directory, "
                      "or unreadable) — nothing to compare against"))
        return fails
    try:
        old, new = id_title_map(prev_path), id_title_map(new_path)
    except Exception as e:                          # noqa: BLE001 — fail closed
        fails.append(("consult-ids", os.path.basename(new_path),
                      f"the id-stability diff did not run ({e}) — a check "
                      f"that is skipped is indistinguishable from a check "
                      f"that passed, so this fails rather than reporting no "
                      f"change"))
        return fails
    for i in sorted(set(old) & set(new)):
        if old[i] != new[i]:
            fails.append(("consult-ids", os.path.basename(new_path),
                          f'id reused for a different claim — {i}: was '
                          f'"{old[i]}", now "{new[i]}". Append a new id '
                          f'instead; a reply about that id now points '
                          f'somewhere else'))
    return fails


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
    failures, n_files = [], 0
    for dirpath, dirnames, filenames in os.walk(walk_root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".aidex-artifact-prev", "_archive")]
        for e in sorted(filenames):
            if not e.endswith(".html"):
                continue
            p = os.path.join(dirpath, e)
            n_files += 1
            rel = os.path.relpath(p, project_root)
            failures.extend((c, rel, m) for c, _, m in check_file(p))
    active, waived = split_waived(failures, ctx, project_root)
    for check, name, msg in active:
        print(f"  FAIL [{check}] {name}: {msg}")
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

    failures = []
    for f in files:
        failures.extend(check_file(f))
    if prev is not None:
        failures.extend(check_prev(files[0], prev))

    for check, name, msg in failures:
        print(f"  FAIL [{check}] {name}: {msg}")
    if not failures:
        print(f"artifact contract OK ({len(files)} file(s))")
        return 0
    print(f"{len(failures)} contract violation(s)")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
