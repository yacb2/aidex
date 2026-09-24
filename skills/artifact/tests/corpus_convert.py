#!/usr/bin/env python3
"""Draft a `.spec.md` from a corpus page. A DRAFTING AID, not a converter.

Usage:
    python3 corpus_convert.py <page.html> > draft.spec.md

What it is for: the sampled pages carry 6,000-56,000 words each, and
re-typing them by hand is how a word gets lost in a way `corpus_diff.py` then
has to find. This walks the page's authored region and writes the spec a human
then FIXES. It is expected to be wrong; `corpus_diff.py` is the judge, and a
spec is converted only when that exits 0.

It is deliberately NOT wired into `goal-gate.sh`. The gate reads the `.spec.md`
files that are committed, whoever wrote them — if the aid were the gate, the
gate would be measuring the aid against itself.

## The mapping it knows

| Page shape | Spec block |
|---|---|
| `<header>` / `.masthead` | `masthead` |
| `section.consult-group` | `group` (recursing) |
| `section.consult-item.consult-notes` | `notes` |
| `section.consult-item` | `item` with its option list |
| `.ledger` | `ledger` |
| `div.verdict`, `.verdicts`, `.kpis` | `verdict` (the figure/label/caption triple) |
| `.callout` | `callout` |
| `.note` | `note` (`.warn` kept as a class) |
| `<table>`, `<ul>`, `<ol>`, `<dl>`, `<p>`, `<h2>`…, `<pre>` | prose |
| `<figure>` holding `<svg>`/`<img>` | dropped — Phase 6 |
| anything else | recursed into |

The scoreboard row is matched on the TAG as well as the class. One sampled page
writes `<p class="verdict">` for a closing sentence — a paragraph, not a
scoreboard — and matching the class alone turned that sentence into a one-cell
table and dropped the words around the `<b>` inside it.

Everything a page's own era invented (`div.sheet`, `.kpi`, `.case-head`,
`.qgrid`, `.journey`, `.figpair`) falls through the last row and reaches the
page as its text, in its order. That is the phase's claim being tested: the
vocabulary is about what the page MEANS, and a decade of bespoke wrappers has
nothing under it but prose, tables and lists.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))

import corpus_html                                       # noqa: E402
import spec_parser                                       # noqa: E402

HEADINGS = ("h1", "h2", "h3", "h4", "h5", "h6")
SPAN_TYPES = ("pill", "chip")

# A container whose element children are all INLINE is one paragraph, not a run
# of them. Pre-kit pages wrap a sentence in `<div class="ev"><span>…</span>`,
# and recursing into that split the sentence at every `<b>`: the words survived
# and their reading order did not, which is a divergence `corpus_diff.py`
# reports as six separate runs and a human then reads as noise.
INLINE_TAGS = {"span", "code", "b", "strong", "em", "i", "a", "small", "br",
               "sup", "sub", "abbr", "u", "s", "mark", "kbd", "time", "var",
               "cite", "q", "label", "#text"}


# --- inline ------------------------------------------------------------------
# Every character `md_body._inline` reads as a marker, escaped so the page gets
# the character back. `[` only when a `]{…}` follows on the same line, which is
# the only shape `SPAN` matches — escaping every `[` in prose would double the
# backslashes in a spec for a construct almost no line contains.
MARKERS = re.compile(r"([\\`*_])")
BRACKET = re.compile(r"\[([^\]\n]+)\]\{")


def escape(text):
    return BRACKET.sub(r"\\[\1]{", MARKERS.sub(r"\\\1", text))


def inline(node):
    """A node's children as markdown inline text."""
    out = []
    for child in node.children:
        if child.tag == "#text":
            out.append(escape(child.text))
        elif child.tag in corpus_html.DROP_TAGS:
            continue
        elif corpus_html.DROP_CLASSES.intersection(child.classes):
            continue
        elif child.tag == "br":
            out.append(" ")
        elif child.tag == "code":
            # NOT escaped: a code span is literal to `md_body`, so a backslash
            # written here would reach the reader as a backslash.
            out.append(" `%s` " % _flat(child))
        elif child.tag in ("b", "strong", "i", "em"):
            # An EMPTY one emits nothing. `<i class="ghost"></i>` is a colour
            # swatch in a legend on two of the sampled pages, and wrapping its
            # nothing in markers wrote a bare `__` into the page — two
            # underscores the reader sees and the original never had.
            body = inline(child).strip()
            if body:
                mark = "**" if child.tag in ("b", "strong") else "_"
                out.append(" %s%s%s " % (mark, body, mark))
        elif child.tag == "span" and child.classes[:1] and \
                child.classes[0] in SPAN_TYPES:
            out.append(" [%s]{%s} " % (inline(child).strip(),
                                       " ".join("." + c for c in child.classes)))
        else:
            # A SPACE at every tag boundary, exactly as `corpus_html._collect`
            # does. Without it `<div class="ftitle">Veredicto</div><p>El…` came
            # back as the single word `VeredictoEl`: the page and the build
            # then tokenize differently and the diff blames the wrong line.
            out.append(" %s " % inline(child))
    return re.sub(r"\s+", " ", "".join(out)).strip()


def _flat(node):
    return " ".join(corpus_html.tokens(node))


def _text(node):
    return _flat(node)


# --- blocks ------------------------------------------------------------------
def attr(value):
    """An attr value, quoted — by `spec_parser.quote_value` and by nothing else.

    This function used to REWRITE a `"` into a typographic `”` and mention it on
    stderr. That is a drafting aid changing the author's VISIBLE text: one
    sampled page (`dynamic_sites_ws` 2026-09-03) carries a straight quote in a
    `group` heading, the note on stderr was read by nobody, and the `”` shipped.
    The grammar grew the escape instead (`03-spec-grammar.md` § Values and
    quoting), so the aid now writes what the page says — faithfully, or not at
    all: any value it cannot spell is the tokenizer's to refuse on the line this
    function wrote, never this function's to quietly repair.
    """
    return spec_parser.quote_value(value)


# One masthead per page, and it is the FIRST one found — not "a `<header>` that
# happens to be a direct child of the content root". Three of the sampled pages
# wrap everything in a `div.sheet` / `div.wrap`, so the page's own opening block
# is a grandchild, and requiring it at the top level silently demoted it to
# prose: the h1 shipped as an `<h1>` inside `<main>` with no masthead anywhere,
# which `check-artifact` has nothing to say about.
_STATE = {"masthead": False}


def convert(page_text):
    root = corpus_html.content_root(page_text)
    _STATE["masthead"] = False
    out = []
    _children(root, out, top=True)
    return _join(out)


def _join(parts):
    text = "\n\n".join(p for p in parts if p.strip())
    return re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"


def _children(node, out, top=False, in_group=False):
    for child in node.children:
        if child.tag == "#text":
            if child.text.strip():
                out.append(escape(re.sub(r"\s+", " ", child.text).strip()))
            continue
        _block(child, out, top=top, in_group=in_group)


def _block(el, out, top=False, in_group=False):
    cls = el.classes

    if el.tag in corpus_html.DROP_TAGS or \
            corpus_html.DROP_CLASSES.intersection(cls):
        return
    if el.tag == "figure" and any(n.tag in ("svg", "img") for n in el.walk()):
        return                                   # Phase 6 owns diagrams

    if not _STATE["masthead"] and (el.tag == "header" or "masthead" in cls
                                   or "mast" in cls):
        _STATE["masthead"] = True
        out.append(_masthead(el))
        return
    if "consult-group" in cls:
        out.append(_group(el))
        return
    if "consult-notes" in cls:
        out.append("::: notes {title=%s}\n:::"
                   % attr(el.attrs.get("data-title", "Notas generales")))
        return
    if "consult-item" in cls:
        out.append(_item(el))
        return
    if "ledger" in cls:
        out.append(_ledger(el))
        return
    if {"verdict", "verdicts", "kpis"}.intersection(cls) and \
            el.tag in ("div", "section", "aside") and el.elements:
        out.append(_verdict(el))
        return
    if "callout" in cls:
        out.append(_framed("callout", el))
        return
    if "note" in cls:
        out.append(_framed("note", el))
        return
    if el.tag == "table":
        # A `<caption>` becomes the LEAD-IN PARAGRAPH, because a markdown pipe
        # table has no caption slot and `04-block-vocabulary.md` refuses a
        # `table` fence on purpose. The text and its reading order survive; the
        # `<caption>` element does not. 4 of the 30 sampled pages carry one.
        cap = el.find(tag="caption")
        if cap is not None:
            out.append(inline(cap))
        out.append(_table(el))
        return
    if el.tag in ("ul", "ol"):
        out.append(_list(el))
        return
    if el.tag == "dl":
        out.append(_dl(el))
        return
    if el.tag == "pre":
        out.append("```\n%s\n```" % _text(el))
        return
    if el.tag in HEADINGS:
        level = min(int(el.tag[1]) if top else max(int(el.tag[1]), 2), 6)
        out.append("#" * level + " " + inline(el))
        return
    if el.tag in ("p", "blockquote"):
        body = inline(el)
        if body:
            out.append(body)
        return

    if el.elements and all(c.tag in INLINE_TAGS for c in el.elements):
        body = inline(el)
        if body:
            out.append(body)
        return

    _children(el, out, in_group=in_group)


def _para_lines(el, skip=()):
    """A framed block's body: its children as prose lines."""
    parts = []
    _children(el, parts)
    return [p for p in parts if p not in skip]


def _framed(kind, el):
    extra = [c for c in el.classes if c == "warn"]
    head = "::: %s%s" % (kind, " {.warn}" if extra else "")
    return "%s\n%s\n:::" % (head, "\n\n".join(_para_lines(el)))


def _masthead(el):
    eyebrow = el.find(cls="eyebrow")
    h1 = el.find(tag="h1")
    byline = el.find(cls="byline") or el.find(cls="colophon")
    attrs = []
    if eyebrow is not None:
        attrs.append("eyebrow=%s" % attr(inline(eyebrow)))
    if byline is not None:
        attrs.append("byline=%s" % attr(inline(byline)))
    head = "::: masthead" + (" {%s}" % " ".join(attrs) if attrs else "")
    body = ["# " + inline(h1)] if h1 is not None else []
    for child in el.children:
        if child.tag == "#text" or child in (eyebrow, h1, byline):
            continue
        if child.tag in HEADINGS and child.tag == "h1":
            continue
        parts = []
        _block(child, parts)
        body.extend(parts)
    return "%s\n%s\n:::" % (head, "\n\n".join(p for p in body if p.strip()))


def _sec_head(el):
    """`(eyebrow, heading, consumed)` from a `.sec-head` or a bare `h2`."""
    head = el.find(cls="sec-head")
    if head is not None:
        eb = head.find(cls="eyebrow")
        h2 = head.find(tag="h2")
        return (inline(eb) if eb is not None else ""), \
               (inline(h2) if h2 is not None else ""), head
    eb = None
    for child in el.elements:
        if "eyebrow" in child.classes:
            eb = child
        elif child.tag in HEADINGS:
            return (inline(eb) if eb is not None else ""), inline(child), child
    return "", "", None


def _group(el):
    eyebrow, heading, consumed = _sec_head(el)
    title = el.attrs.get("data-title") or heading
    attrs = ["#%s" % el.attrs.get("data-id", el.attrs.get("id", "G1")),
             "title=%s" % attr(title)]
    if heading and heading != title:
        attrs.append("heading=%s" % attr(heading))
    if eyebrow:
        attrs.append("eyebrow=%s" % attr(eyebrow))
    body = []
    for child in el.children:
        if child.tag == "#text" or child is consumed:
            continue
        if consumed is None and ("eyebrow" in child.classes
                                 or child.tag in HEADINGS):
            continue
        _block(child, body, in_group=True)
    return "::: group {%s}\n%s\n:::" % (" ".join(attrs),
                                        "\n\n".join(b for b in body if b.strip()))


def _item(el):
    ident = el.attrs.get("data-id", "Q")
    title = el.attrs.get("data-title", "")
    attrs = ["#%s" % ident, "title=%s" % attr(title)]
    if "data-decided" in el.attrs:
        # QUOTED: `data-decided` carries a whole sentence on 4 of the sampled
        # pages ("Cerrar los tres y registrar el nivel vivo"), and an unquoted
        # attr value cannot hold a space — the tokenizer read the second word
        # as a malformed attr item and named a column, not the sentence.
        attrs.append("decided=%s" % attr(el.attrs["data-decided"] or "yes"))

    h3 = el.find(tag="h3")
    body = []
    if h3 is not None:
        body.append(inline(h3))
    for child in el.children:
        if child.tag == "#text" or child is h3:
            continue
        if "opts" in child.classes:
            body.append(_options(child))
            continue
        _block(child, body)
    return "::: item {%s}\n%s\n:::" % (" ".join(attrs),
                                       "\n\n".join(b for b in body if b.strip()))


def _options(el):
    lines = []
    for label in el.find_all(tag="label"):
        rec = " {recommended}" if any(
            "data-recommended" in n.attrs for n in label.walk()) else ""
        hint = label.find(cls="hint")
        if hint is not None:
            text = inline(label)
            hint_text = inline(hint)
            if text.endswith(hint_text):
                text = text[:-len(hint_text)].strip()
            lines.append("- %s — %s%s" % (text, hint_text, rec))
        else:
            lines.append("- %s%s" % (inline(label), rec))
    return "\n".join(lines)


def _ledger(el):
    rows = []
    for row in el.elements:
        k = row.find(cls="k")
        v = row.find(cls="v")
        if k is None or v is None:
            rows.append("- %s" % inline(row))
            continue
        rows.append("- %s — %s" % (inline(k), inline(v)))
    return "::: ledger\n%s\n:::" % "\n".join(rows)


def _cell_parts(cell):
    """A scoreboard cell's three slots, taken POSITIONALLY.

    The corpus writes the same triple four ways — `<b>/text/<small>` (kit),
    `.n/.l/.s` (pre-kit KPI), `.k/.v/.n` (one project's own), and a bare run of divs —
    and the class names collide across them: `.n` is the FIGURE in one and the
    CAPTION in another. Reading the slots by name got the order wrong on every
    page of the second family. Reading them by position is right on all four,
    because what the reader sees is the order they were written in.
    """
    parts = []
    for child in cell.children:
        if child.tag == "#text":
            if child.text.strip():
                parts.append(escape(re.sub(r"\s+", " ", child.text).strip()))
        elif child.tag == "br" or child.tag in corpus_html.DROP_TAGS:
            continue
        else:
            got = inline(child)
            if got:
                parts.append(got)
    if len(parts) > 3:
        parts = parts[:2] + [" ".join(parts[2:])]
    return parts + [""] * (3 - len(parts))


def _verdict(el):
    rows = ["| n | qué | detalle |", "|---|---|---|"]
    for cell in el.elements:
        rows.append("| %s | %s | %s |" % tuple(_cell_parts(cell)))
    return "::: verdict\n%s\n:::" % "\n".join(rows)


def _cells(row):
    return [inline(c) for c in row.elements if c.tag in ("td", "th")]


def _table(el):
    rows = [r for r in el.walk() if r.tag == "tr"]
    if not rows:
        return ""
    grid = [_cells(r) for r in rows]
    width = max(len(r) for r in grid)
    grid = [r + [""] * (width - len(r)) for r in grid]
    out = ["| %s |" % " | ".join(grid[0]), "|" + "---|" * width]
    for r in grid[1:]:
        out.append("| %s |" % " | ".join(r))
    return "\n".join(out)


def _list(el):
    marker = "1." if el.tag == "ol" else "-"
    out = []
    for li in el.elements:
        if li.tag != "li":
            continue
        out.append("%s %s" % (marker, inline(li)))
    return "\n".join(out)


def _dl(el):
    """A `<dl>` becomes a bullet list with a bold term — markdown's own way of
    writing a definition list, and the only one that adds no word.

    NOT a `ledger`: that block means "what earlier rounds settled", and the
    corpus `<dl>`s are per-item field lists (`Residual`, `Mi lectura`). The
    k/v markup would have matched and the meaning would not. It also cost a
    word: a ledger row is `- key — value` and the ` — ` is a SEPARATOR the
    builder eats, but writing one here put a literal em dash in the page.
    """
    out = []
    for child in el.elements:
        if child.tag == "dt":
            out.append("- **%s**" % inline(child))
        elif child.tag == "dd" and out:
            out[-1] += " " + inline(child)
    return "\n".join(out)


def main(argv):
    if len(argv) != 1:
        sys.stderr.write(__doc__.split("\n\n")[1] + "\n")
        return 2
    with open(argv[0], encoding="utf-8") as fh:
        sys.stdout.write(convert(fh.read()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
