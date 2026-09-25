#!/usr/bin/env python3
"""spec_build.py — a page spec becomes artifact-kit HTML.

The second of the two layers `references/03-spec-grammar.md` describes. The
tokenizer (`spec_parser.py`) knows shape only; this file knows MEANING: which
block types exist (`references/04-block-vocabulary.md`), which attrs each one
takes, which are required, and what may nest inside what. Every rejection names
the block type and the attribute, and carries the spec line it came from.

Three properties this file is written to keep, in the order they are load-bearing:

1. **It emits the kit's own markup, verbatim.** Every emitter mirrors a shape
   that already exists — `assets/templates/consultation-block.html.template`,
   `scripts/dash/gallery_items.py`, the corpus pages `04-block-vocabulary.md`
   quotes — so the output passes `check-artifact.sh` for the same reasons a
   hand-written page does. No rule of the contract is special-cased for a
   spec-built page and none may be.

2. **Ids are preserved byte-exactly.** A `#id` becomes `id=`, `data-id=` and the
   anchor the rail links to, unchanged: not lowercased, not slugged, not
   re-numbered. Phase 3's corpus conversion asserts exact preservation, and §8.1
   of the artifact reference is why — a reply that says "on Q3 I disagree" has to
   still mean the same claim after the next round.

3. **The build is deterministic.** Same spec in, byte-identical HTML out: no
   clock, no `id()`, no set or dict iteration order that the spec did not write.
   `attrs` is an insertion-ordered dict and every list is the document's own.
   The only non-determinism on the page comes from the WRAP
   (`artifact-built`, BL-439), which is a stamp the reader asked for, deliberate, and outside
   `build()`.

Prose is rendered by `dash/md_body.py` and by nothing else (Q7 of the plan). Two
cases the corpus needed and that module lacked were added THERE, in place, not
forked: a right-aligned separator cell (`---:`) marks a `num` column, and
`[text]{.pill .high}` is the inline form of `pill` and `chip`.

Registering a block type
------------------------
`register("chart", emit_chart)` — that is the whole seam, and `@emitter("chart")`
is the decorator spelling of it. Give the emitter the signature
`fn(node, ctx) -> str` and, if it may only live in certain parents, one entry in
`PARENTS`; nothing in the dispatch, the nesting table or the CLI has to be
reshaped. The two blocks that DRAW — `chart` (Phase 2) and `diagram` (Phase 6) —
register from here and keep their grammar and their geometry in a module of
their own (`chart_svg.py`, `diagram_layout.py` + `diagram_svg.py`): the emitter
is the attr vocabulary and the refusals that name the FENCE's line, and nothing
else. Everything about a row or a box is over there.
"""

import argparse
import base64
import contextlib
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "dash"))

import chart_svg                                # noqa: E402
import check_artifact                           # noqa: E402
import diagram_layout                           # noqa: E402
import diagram_svg                              # noqa: E402
import gallery_items                            # noqa: E402
import graph_svg                                # noqa: E402
import md_body                                  # noqa: E402
from spec_parser import SpecSyntaxError, parse   # noqa: E402,F401

esc = md_body.esc

WRAP = os.path.join(HERE, "wrap-report.sh")
CHECK = os.path.join(HERE, "check-artifact.sh")

LANGS = ("es", "en")

# Kit chrome, in the page's language. Same two languages `gallery_items.py`
# carries, and the strings are its neighbours: a page half in each is what a
# third source of these would produce.
STRINGS = {
    "es": {
        "item_notes": "Notas sobre esto",
        "item_placeholder": "Lo que las opciones no cubren…",
        "notes_label": "Lo que no encaja arriba",
        "notes_placeholder": "Lo que sea…",
        "copy": "Copiar mis respuestas",
    },
    "en": {
        "item_notes": "Notes on this one",
        "item_placeholder": "Anything the options do not cover…",
        "notes_label": "Anything that does not fit above",
        "notes_placeholder": "Whatever it is…",
        "copy": "Copy my answers",
    },
}

# The option-line separator: ` — ` splits the LABEL the composer pastes from the
# HINT the page shows beside it. The corpus writes every option that way
# (04-block-vocabulary.md § item), and the label has to stay short because it is
# what travels in the reply.
HINT_SEP = " — "
RECOMMENDED = "{recommended}"
# What `data-label` carries is TEXT: the composer copies that attribute into the
# reply, so a backtick or a `**` written for the page's own rendering would
# travel into the paste as punctuation the reader never wrote. Backticks and
# asterisks only — `_` is stripped by NO rule here, because `md_body` italicises
# it only in pairs and a label naming `a_file.py` must not come back as
# `afile.py`.
PLAIN = re.compile(r"[`*]")

# The two inline types. They are NOT fences: a one-word span in the middle of a
# sentence cannot be a block, and a fence for it would only be a way to get it
# wrong. Same for `num`, which is a column marker. Naming them here turns
# "unknown block type" into the sentence that says where they really live.
INLINE_HINT = {
    "pill": 'write it inline in prose: `[confianza alta]{.pill .high}`',
    "chip": 'write it inline in prose: `[deferred]{.chip .chip-kill}`',
    "num": "mark the column right-aligned in the table's separator row "
           "(`|---:|`); `num` is a column marker, not a block",
}


class SpecBuildError(Exception):
    """A spec whose SHAPE is fine and whose MEANING is not.

    Separate from `SpecSyntaxError` on purpose: an unknown block type, an
    unknown attr key and a missing required attr all tokenize, and this is the
    layer that knows enough to say which alternatives exist.
    """

    def __init__(self, line, message):
        self.line = line
        self.message = message
        super().__init__("line %d: %s" % (line, message))


class BuildContext:
    """What every emitter may read: the page's language and where the spec sits.

    `base_dir` is the spec file's directory — a `rows=` path is relative to the
    spec, never to the cwd, because the same spec must build from anywhere.
    """

    def __init__(self, lang="es", base_dir="."):
        if lang not in LANGS:
            raise SpecBuildError(0, "unknown page language %r (known: %s)"
                                 % (lang, ", ".join(LANGS)))
        self.lang = lang
        self.base_dir = os.path.abspath(base_dir)
        self.s = STRINGS[lang]


# --- the dispatch table ------------------------------------------------------
EMITTERS = {}
# Where a block type may appear. `None` is the document's top level. A type with
# no entry may appear anywhere. Keep an entry here only for a type whose
# placement the CONTRACT cares about — check_artifact.py's consult-shape rules
# are the reason every one of these exists.
#
# `item` used to be `("group",)` only. It is not, since Phase 3: 4 of the 30
# sampled pages (13%) write a decision outside any block, and a spec that
# cannot say what a real page says is a spec that cannot convert the corpus.
# The RULE has not gone anywhere — check_artifact.py's `check_shape` fails
# exactly this, names the item, and cites § 8.4, and `wrap-report.sh --out`
# runs it before the page lands, so an ungrouped item still cannot ship. What
# went is the SECOND copy of the rule, here, which refused the page before the
# owner of the rule could speak. One owner per rule; this is not it.
PARENTS = {
    "masthead": (None,),
    "group": (None,),
    "notes": (None,),
    "gallery": (None,),
    "item": (None, "group"),
}


def register(block_type, fn, parents=None):
    """Add a block type to the dispatch table. The seam Phases 2 and 6 use."""
    EMITTERS[block_type] = fn
    if parents is not None:
        PARENTS[block_type] = tuple(parents)


def emitter(block_type, parents=None):
    def deco(fn):
        register(block_type, fn, parents)
        return fn
    return deco


# --- attr plumbing -----------------------------------------------------------
def _attrs(node, allowed, required=(), need_id=False, forbid_id=False,
           id_why=None):
    """Validate a node's attrs against one block type's vocabulary.

    `id_why` replaces the default reason an #id is required. `section` needs
    one for the rail and for nothing else — its id is not a `data-id`, no reply
    names it — and a refusal that says otherwise sends the author looking for a
    paste key that does not exist.
    """
    for key in node.attrs:
        if key not in allowed:
            raise SpecBuildError(
                node.line,
                "`%s` takes no attr %r (it takes: %s)"
                % (node.block_type, key,
                   ", ".join(sorted(allowed)) or "none"))
    for key in required:
        if not node.attrs.get(key, "").strip():
            raise SpecBuildError(
                node.line, "`%s` needs a non-empty %s=\"…\""
                % (node.block_type, key))
    if need_id and not node.id:
        raise SpecBuildError(
            node.line,
            "`%s` needs an #id — %s"
            % (node.block_type,
               id_why or "it becomes the block's id, its data-id and the "
                         "rail's anchor, and it is what a reply names"))
    if forbid_id and node.id:
        raise SpecBuildError(
            node.line, "`%s` takes no #id" % node.block_type)
    return node.attrs


def _refuse_prose_fence(node):
    """`::: prose` is not an authorable fence. Raised, never rendered.

    `prose` is registered because it is the type the TOKENIZER gives a run of
    markdown outside any fence, and registering it is what makes that run build.
    Spelling it as a fence is a different node: its body lives in a prose CHILD,
    so `node.text` is empty and the whole body — paragraphs, lists, tables —
    left the page with no error and no line number, on a page `check-artifact`
    then passed. `04-block-vocabulary.md` already says `prose` is "Not a fence.";
    `pill`, `chip` and `num` get a refusal naming where they really go, and this
    is the same sentence for the fourth. REFUSING rather than rendering the
    children, because a `::: prose` fence means the author thought prose needed
    a wrapper: the honest answer is that it does not, and a builder that quietly
    made it work would keep that misunderstanding alive in every later spec.
    """
    raise SpecBuildError(
        node.line,
        "`prose` is not a fence — a run of markdown outside any block IS "
        "prose, and this one has no wrapper to add. Delete the `::: prose` "
        "line and its closing `:::`; the body stays exactly where it is")


def _no_children(node):
    for child in node.children:
        if child.block_type == "prose" and child.authored:
            _refuse_prose_fence(child)
        if child.block_type != "prose" or child.text.strip():
            raise SpecBuildError(
                node.line, "`%s` takes no body" % node.block_type)


def _prose_lines(node):
    """The node's body as markdown lines, refusing any nested fence.

    For the types whose body is prose and nothing else. A nested fence there is
    not a richer block, it is a block in the wrong place, and letting it through
    would put a `<section>` inside an `<h3>`.
    """
    out = []
    for child in node.children:
        # An authored `::: prose` is a FENCE, not one of this body's prose runs:
        # its lines are in its own children, so folding it in here would take
        # the empty `raw_body` and drop the body.
        if child.block_type == "prose" and child.authored:
            _refuse_prose_fence(child)
        if child.block_type != "prose":
            # The PLACEMENT message first when there is one: "`item` may only
            # appear in `group`" tells the author where the block belongs, and
            # "this body is prose" only tells them where it does not.
            _check_parent(child, node.block_type)
            raise SpecBuildError(
                child.line, "`%s` cannot contain a `%s` block — its body is "
                "prose" % (node.block_type, child.block_type))
        out.extend(child.raw_body)
    return out


def _classes(base, node):
    return " ".join([base] + list(node.classes))


def _unwrap_p(html):
    """`<p>x</p>` -> `x`, when that is the whole fragment.

    The corpus writes a one-paragraph `.note` as bare text inside the div, and
    `<p>` inside it picks up a margin the kit never styles away.
    """
    if html.startswith("<p>") and html.endswith("</p>") \
            and "</p>" not in html[:-4]:
        return html[3:-4]
    return html


# --- the emitters ------------------------------------------------------------
@emitter("prose")
def emit_prose(node, ctx):
    if node.authored:
        _refuse_prose_fence(node)
    return md_body.fragment(node.text)


@emitter("section", parents=(None,))
def emit_section(node, ctx):
    """A page section that is not a `group`: an id, an eyebrow, an h2, a body.

    19 of the 30 sampled pages open their visual section, their ledger section
    or a reference section with `<section id="…"><div class="sec-head">` — 106
    of them in all — and until this block the grammar had no spelling for it, so
    the conversion wrote the head's two strings as loose prose at the document's
    top level. That is not merely untidy markup, it fails the page twice:

      * `check_artifact.check_shape` strips a `.sec-head` subtree before it
        looks for a preamble, so the same strings as a bare `<p>` + `<h3>` are
        "prose before the first block";
      * `check_artifact`'s `rail` rule indexes `.main > section[id]`, so an
        `<h2>` that is not inside one is a heading missing from the rail.

    Nine of the sampled pages failed the first and, once the head was a real
    `.sec-head`, the second — on pages whose ORIGINALS pass both.

    The `#id` is required for that second reason and for no other: it is the
    rail's anchor, it is not a `data-id`, and nothing composes a reply from it.
    `group` emits the same `.sec-head` and keeps its own attrs, because a
    group's head also carries the block's NAME (`data-title`), which a section
    does not have.
    """
    a = _attrs(node, {"eyebrow", "heading"}, required=("heading",),
               need_id=True,
               id_why="the rail indexes `.main > section[id]`, so a section "
                      "without one keeps its <h2> out of the page's index. It "
                      "is not a data-id and no reply names it")
    classes = " ".join(node.classes)
    out = ['<section%s id="%s">'
           % (' class="%s"' % esc(classes) if classes else "", esc(node.id))]
    out.append('  <div class="sec-head">')
    if a.get("eyebrow"):
        out.append('    <p class="eyebrow">%s</p>' % md_body._inline(a["eyebrow"]))
    out.append("    <h2>%s</h2>" % md_body._inline(a["heading"]))
    out.append("  </div>")
    out.extend(emit_children(node, ctx))
    out.append("</section>")
    return "\n".join(out)


@emitter("masthead")
def emit_masthead(node, ctx):
    a = _attrs(node, {"title", "eyebrow", "byline", "visual", "lang"},
               forbid_id=True)
    # A masthead may carry a framed aside, in the position it was written. One
    # sampled page opens with
    # two `.note` divs under its standfirst, and both are about the page as a
    # whole rather than about any one block — which is exactly the opening
    # block's job. `_segments`, not `_prose_lines`, because the asides sit AFTER
    # the standfirst and a joined body loses that.
    segments = _segments(node, ASIDES)
    title = a.get("title", "").strip()
    # A `# ` line in the body is the title when no attr gives one — that is how
    # the worked example writes it, and it keeps the spec readable as markdown.
    #
    # BOTH forms on one masthead is REFUSED rather than resolved. `title=` used
    # to "win" only the h1: the `# ` line stayed in the body, rendered as a
    # stray <h3> under the real title, and — being a heading rather than a
    # paragraph — it also blocked the standfirst promotion, so the next
    # paragraph shipped as bare text. Consuming it instead would delete a line
    # the author wrote, which is the drop this renderer's whole contract is
    # against. Two titles on one masthead is not a precedence question, it is
    # the author having written the title twice; only they know which one they
    # meant.
    stripped = []
    for kind, payload in segments:
        if kind != "prose":
            stripped.append((kind, payload))
            continue
        rest = []
        for ln in payload:
            if ln.startswith("# "):
                if title:
                    raise SpecBuildError(
                        node.line,
                        "`masthead` carries both title=%r and a `# ` line (%r) "
                        "— write the title ONCE: as the attr, or as the `# ` "
                        "line, not both" % (title, ln[2:].strip()))
                title = ln[2:].strip()
                continue
            rest.append(ln)
        stripped.append(("prose", rest))
    if not title:
        raise SpecBuildError(
            node.line, "`masthead` needs a title — either title=\"…\" or a "
            "`# ` line in its body")
    out = ['<header class="%s">' % _classes("masthead", node)]
    if a.get("eyebrow"):
        out.append('<p class="eyebrow">%s</p>' % md_body._inline(a["eyebrow"]))
    out.append("<h1>%s</h1>" % md_body._inline(title))
    standfirst_taken = False
    for kind, payload in stripped:
        if kind == "block":
            out.append(emit_node(payload, ctx, parent="masthead"))
            continue
        parts = md_body.blocks("\n".join(payload))
        if not parts:
            continue
        if not standfirst_taken:
            # The first paragraph is the standfirst: the strongest thing the
            # page has to say, on the first screen. Same promotion
            # `md_body.render()` already does for a wrapped report. It is the
            # first paragraph of the masthead's OWN prose — an aside written
            # above it is not the page's strongest claim, it is an aside, and
            # promoting whatever came first would have made it one.
            standfirst_taken = True
            first = parts[0]
            out.append(first.replace("<p>", '<p class="standfirst">', 1)
                       if first.startswith("<p>") else first)
            out.extend(parts[1:])
            continue
        out.extend(parts)
    if a.get("byline"):
        out.append('<div class="byline">%s</div>' % md_body._inline(a["byline"]))
    out.append("</header>")
    return "\n".join(out)


@emitter("group")
def emit_group(node, ctx):
    """`title` is the block's NAME; `heading` is the sentence over it.

    They are two different strings on most corpus blocks, and they are read by
    two different audiences: `data-title` is what the rail lists and what the
    composed reply is headed with, so it is short and stable across rounds,
    while the `<h2>` is a full sentence that says what this round found. One
    attr for both shipped the sentence into the reply — 92 characters of prose
    where the paste needs a label — and, on the pages that write only a name,
    an `<h2>` that says nothing. `heading` is optional: without it the h2 is the
    title, which is the one-string page this originally assumed.
    """
    a = _attrs(node, {"title", "eyebrow", "heading"}, required=("title",),
               need_id=True)
    heading = a.get("heading", "").strip() or a["title"]
    out = ['<section class="%s" id="%s" data-id="%s" data-title="%s">'
           % (_classes("consult-group", node), esc(node.id), esc(node.id),
              esc(a["title"]))]
    out.append('  <div class="sec-head">')
    if a.get("eyebrow"):
        out.append('    <p class="eyebrow">%s</p>' % md_body._inline(a["eyebrow"]))
    out.append("    <h2>%s</h2>" % md_body._inline(heading))
    out.append("  </div>")
    out.extend(emit_children(node, ctx))
    out.append("</section>")
    return "\n".join(out)


def _split_options(lines):
    """`(before, options, after)` — the first top-level `-` list of a body.

    An item's options are a bullet list and nothing else: a numbered list stays
    prose (it is a sequence, not a choice), and only the FIRST list is read as
    the option group so an item may still show a list of evidence below its
    options. Continuation lines follow `md_body`'s rule — indented, folded into
    the item above — because the two must agree about where an option ends.

    A ``` / ~~~ CODE FENCE is tracked, with `md_body.FENCE` itself and not a
    second copy of that regex (the same borrowing `spec_parser.CODE_FENCE`
    does). Without it this was the third line-scanner over one text and the only
    one blind to fences: an item that pasted a `git log` run above its options
    turned the log's `- fix: …` lines into the RADIO BUTTONS and degraded the
    author's real options into a `<pre>` — a reader answering a question that
    was never asked, on a page `check-artifact` passes. An unclosed fence takes
    the rest of the body as code, which is `md_body._blocks`' rule for the same
    input and the reason the two still agree about where an option ends.
    """
    i, fence = 0, None
    while i < len(lines):
        ln = lines[i]
        fm = md_body.FENCE.match(ln)
        if fence is not None:
            if fm and fm.group(1) == fence:
                fence = None
        elif fm:
            fence = fm.group(1)
        elif md_body.MARKER.match(ln) and not md_body.ORDERED.match(ln) \
                and not ln[:1].isspace():
            break
        i += 1
    else:
        return lines, [], []
    before, opts = lines[:i], []
    while i < len(lines):
        cur = lines[i]
        if md_body.MARKER.match(cur) and not cur[:1].isspace():
            opts.append(md_body.MARKER.sub("", cur, count=1).strip())
        elif (opts and cur.strip() and cur[:1].isspace()
              and not cur.lstrip().startswith("|")
              and not md_body.HEADING.match(cur.lstrip())):
            # The same three guards `md_body`'s list branch carries. They have
            # to agree: a line this folded into an option and that one did not
            # would leave the text in the page twice, or in neither.
            opts[-1] += " " + cur.strip()
        else:
            break
        i += 1
    return before, opts, lines[i:]


def _option(text):
    """`(label, hint, recommended)` from one option line."""
    rec = False
    if text.rstrip().endswith(RECOMMENDED):
        rec = True
        text = text.rstrip()[:-len(RECOMMENDED)].rstrip()
    label, _, hint = text.partition(HINT_SEP)
    return label.strip(), hint.strip(), rec


# The framed aside: what `item`, `masthead` and `note` may carry BESIDES their
# own prose. Three of the 30 sampled pages put one inside a decision (11 in
# all), one puts two inside its MASTHEAD, one nests a note inside a note — and
# every occurrence is there for the same reason: the aside qualifies THIS block,
# and moving it out — the only other way to write it — detaches it from what it
# qualifies and, on a page with several decisions, from which one.
#
# One list for the three, because it is one shape. `note` and `callout` are the
# same construct at two volumes (`04-block-vocabulary.md`), so a host that
# accepts the quieter one and refuses the louder one would be an asymmetry with
# no reason behind it. Not an open door either: everything else these could nest
# is refused by `PARENTS` (an item, a group, a masthead, the notes item, a
# gallery), so this list is the whole of what the refusal below has left to say
# no to.
ASIDES = ("note", "callout")

# What an `item` carries on top of an aside: a drawing of the choice it asks.
# Four corpus decisions hold one (a z-index ladder, a before/after, two graphs),
# and placing it before the item detached it from the decision it illustrates.
# All four figure blocks, uniformly — which rung draws it is the ladder's call,
# not the host's. Item only: a masthead or note with a drawing is a page-level
# figure in the wrong place.
FIGURE_BLOCKS = ("figure", "chart", "graph", "diagram")


def _segments(node, nests, carries="prose"):
    """A body in WRITTEN ORDER: `("prose", [line, …])` runs and `("block",
    node)` asides, interleaved.

    `_prose_lines` cannot be used for a body that nests: it joins every run into
    one list and so loses where a nested aside sat. An item that wrote a caveat
    between its question and its options would have had it re-emitted after the
    options — below the thing it was warning about — and a masthead's two asides
    would have come out above its own standfirst.
    """
    out = []
    for child in node.children:
        if child.block_type == "prose":
            if child.authored:
                _refuse_prose_fence(child)
            out.append(("prose", list(child.raw_body)))
            continue
        _check_parent(child, node.block_type)
        if child.block_type not in nests:
            raise SpecBuildError(
                child.line,
                "`%s` cannot contain a `%s` block — it carries %s and an "
                "aside (%s)"
                % (node.block_type, child.block_type, carries,
                   ", ".join("`%s`" % t for t in nests)))
        out.append(("block", child))
    return out


@emitter("item")
def emit_item(node, ctx):
    a = _attrs(node, {"title", "decided"}, required=("title",), need_id=True)
    segments = _segments(node, ASIDES + FIGURE_BLOCKS,
                         "prose, its options, a figure")
    # The option list is the FIRST one in the body, wherever it sits, and the
    # segments before and after it keep their order around it.
    head, opts, tail = [], [], []
    seen = False
    for kind, payload in segments:
        if kind == "block":
            (tail if seen else head).append(("block", payload))
            continue
        if seen:
            tail.append(("prose", payload))
            continue
        before, found, after = _split_options(payload)
        if found:
            seen = True
            head.append(("prose", before))
            opts = found
            if any(ln.strip() for ln in after):
                tail.append(("prose", after))
        else:
            head.append(("prose", payload))
    def render(segments, ctx=ctx):
        out = []
        for kind, payload in segments:
            if kind == "block":
                out.append(emit_node(payload, ctx, parent="item"))
            else:
                out.extend(md_body.blocks("\n".join(payload)))
        return out

    parts = render(head)
    # The h3 is the QUESTION and data-title is the short name the composed reply
    # is headed with — two different strings on every corpus item. The first
    # paragraph of the body is the question; an item that opens with something
    # else keeps it and asks its title instead.
    if parts and parts[0].startswith("<p>") and parts[0].endswith("</p>"):
        question, parts = _unwrap_p(parts[0]), parts[1:]
    else:
        question = md_body._inline(a["title"])

    decided = a.get("decided", "").strip()
    flag = ""
    if decided:
        flag = (" data-decided" if decided in ("yes", "true")
                else ' data-decided="%s"' % esc(decided))
    out = ['<section class="%s" data-id="%s" data-title="%s"%s>'
           % (_classes("consult-item", node), esc(node.id), esc(a["title"]),
              flag)]
    out.append('  <h3><span class="consult-id">%s</span>%s</h3>'
               % (esc(node.id), question))
    out.extend("  " + p for p in parts)
    if opts:
        out.append('  <div class="opts one">')
        for text in opts:
            label, hint, rec = _option(text)
            if not label:
                raise SpecBuildError(node.line, "an option with no label")
            span = md_body._inline(label)
            if hint:
                span += ' <span class="hint">%s</span>' % md_body._inline(hint)
            out.append('    <label><input type="radio" name="%s" '
                       'data-label="%s"%s><span>%s</span></label>'
                       % (esc(node.id), esc(PLAIN.sub("", label)),
                          " data-recommended" if rec else "", span))
        out.append("  </div>")
    out.extend("  " + p for p in render(tail))
    # The notes box is not optional on any item: a closed choice with nowhere to
    # qualify it loses everything the options do not cover, and check-artifact
    # fails an item without one.
    out.append('  <p class="fieldlabel">%s</p>' % esc(ctx.s["item_notes"]))
    out.append('  <textarea placeholder="%s"></textarea>'
               % esc(ctx.s["item_placeholder"]))
    out.append("</section>")
    return "\n".join(out)


@emitter("notes")
def emit_notes(node, ctx):
    a = _attrs(node, {"title"}, required=("title",))
    _no_children(node)
    ident = node.id or "notes"
    return "\n".join([
        '<section class="%s" data-id="%s" data-title="%s">'
        % (_classes("consult-item consult-notes", node), esc(ident),
           esc(a["title"])),
        '  <h3><span class="consult-id">%s</span>%s</h3>'
        % (esc(ident), esc(a["title"])),
        '  <p class="fieldlabel">%s</p>' % esc(ctx.s["notes_label"]),
        '  <textarea placeholder="%s"></textarea>'
        % esc(ctx.s["notes_placeholder"]),
        "</section>"])


@emitter("gallery")
def emit_gallery(node, ctx):
    a = _attrs(node, {"title", "rows", "lang", "root"},
               required=("title", "rows"), need_id=True)
    _no_children(node)
    lang = a.get("lang", ctx.lang)
    if lang not in gallery_items.LANGS:
        raise SpecBuildError(node.line, "`gallery` lang=%r is not one of %s"
                             % (lang, ", ".join(gallery_items.LANGS)))
    # `rows=` is relative to the SPEC (the same spec must build from anywhere).
    # `root=` is a different thing and defaults differently: `gallery_items`
    # documents every tile path as relative to the CHECKOUT ROOT and refuses an
    # absolute one for that reason, so defaulting root to the spec's own
    # directory made every tile of every spec that does not sit at the checkout
    # root resolve to a file:// URL that does not exist — silently, because
    # `check-artifact` never stats a linked image. The default is the checkout
    # the spec is in; `root=` overrides it for a rows document whose paths are
    # relative to something else.
    rows = a["rows"]
    if not os.path.isabs(rows):
        rows = os.path.join(ctx.base_dir, rows)
    root = a.get("root")
    if root is None:
        root = _checkout_root(node, ctx.base_dir)
    elif not os.path.isabs(root):
        root = os.path.join(ctx.base_dir, root)
    # `gallery_items` is a CLI module: its refusals go through `die()`, which
    # writes a line and raises SystemExit. SystemExit is a BaseException, so it
    # escaped `build()` past `except Exception` — a bad `rows=` path killed the
    # caller instead of being a refusal it could report, and no gallery refusal
    # was testable at all (the suite's own helper catches SpecBuildError). The
    # line it wrote is captured and carried into the documented exception, with
    # the spec line every other refusal names.
    err = io.StringIO()
    try:
        with contextlib.redirect_stderr(err):
            doc = gallery_items.load(rows)
            html = gallery_items.render(doc, os.path.normpath(root), node.id,
                                        a["title"], lang)
    except SystemExit:
        said = [ln for ln in err.getvalue().splitlines() if ln.strip()]
        raise SpecBuildError(
            node.line,
            "`gallery` rows=%r was refused: %s"
            % (a["rows"], said[-1].strip() if said
               else "the rows document is not usable")) from None
    return html.rstrip("\n")


def _checkout_root(node, base_dir):
    """The git checkout `base_dir` is in — the default `root` of a gallery.

    The one environment dependency in this file, and it is explicit on purpose:
    a rows document's tile paths are relative to the checkout root, so the
    builder either knows where that is or must say that it does not. It never
    guesses. For a given spec and a given checkout the answer is fixed, so the
    build stays deterministic; outside a checkout the block is refused with the
    attr that fixes it, rather than emitting tiles that point nowhere.
    """
    try:
        r = subprocess.run(["git", "-C", base_dir, "rev-parse",
                            "--show-toplevel"],
                           capture_output=True, text=True)
        top = r.stdout.strip() if r.returncode == 0 else ""
    except OSError:
        top = ""
    if not top:
        raise SpecBuildError(
            node.line,
            "`gallery` rows are relative to the CHECKOUT ROOT and %r is not "
            "inside a git checkout (or git is unavailable) — give the block an "
            "explicit root=\"…\"" % base_dir)
    return top


@emitter("ledger")
def emit_ledger(node, ctx):
    _attrs(node, set(), forbid_id=True)
    rows = []
    for ln in _prose_lines(node):
        if not ln.strip():
            continue
        if not md_body.MARKER.match(ln):
            raise SpecBuildError(
                node.line,
                "a ledger is a list of `- key — what was settled` rows; %r is "
                "not one of them" % ln.strip())
        text = md_body.MARKER.sub("", ln, count=1).strip()
        key, sep, value = text.partition(HINT_SEP)
        if not sep:
            # A row with no ` — ` is a row with no KEY: it ships as a `.v` cell
            # alone. It used to be refused, and the refusal was wrong about the
            # contract — `check_artifact.ledger_ids` names the key-less grid as
            # a legitimate `.ledger` in its own docstring ("`.ledger` is also
            # used as a plain grid whose rows have no `.k` key … neither is a
            # violation"), so refusing made a page the contract ACCEPTS
            # unbuildable. 3 of the 30 sampled pages write one.
            #
            # The cell that survives is `.v`, not `.k`: the text is the row's
            # VALUE, and `.ledger .k` is a short mono accent for an id, which
            # would have restyled a sentence into a key and — worse — offered
            # `ledger_ids` a key to harvest item ids out of. A row with no key
            # names no decision, and it must not start to.
            rows.append('  <div><span class="v">%s</span></div>'
                        % md_body._inline(text))
            continue
        rows.append('  <div><span class="k">%s</span><span class="v">%s</span></div>'
                    % (md_body._inline(key.strip()),
                       md_body._inline(value.strip())))
    # An EMPTY ledger is a ledger — the row count is not the shape (the same
    # reading check_artifact.py's `_ledger_shape` takes).
    return "\n".join(['<div class="%s">' % _classes("ledger", node)] + rows
                     + ["</div>"])


@emitter("verdict")
def emit_verdict(node, ctx):
    a = _attrs(node, {"win"}, forbid_id=True)
    rows = [ln for ln in _prose_lines(node) if ln.strip()]
    if len(rows) < 2:
        raise SpecBuildError(
            node.line, "`verdict` takes a pipe table of cells: a header row, "
                       "then one row per cell")
    body = rows[2:] if md_body.SEP_ROW.match(rows[1]) else rows[1:]
    win = a.get("win", "").strip()
    seen_win = False
    out = ['<div class="%s">' % _classes("verdict", node)]
    for row in body:
        cells = md_body._cells(row)
        if len(cells) not in (2, 3):
            raise SpecBuildError(
                node.line,
                "a verdict cell is `| figure | label |` or `| figure | label | "
                "caption |`; this row has %d columns" % len(cells))
        is_win = bool(win) and cells[1].strip() == win
        seen_win = seen_win or is_win
        cell = "<b>%s</b>%s" % (md_body._inline(cells[0]),
                                md_body._inline(cells[1]))
        if len(cells) == 3 and cells[2].strip():
            cell += "<br><small>%s</small>" % md_body._inline(cells[2])
        out.append('  <div%s>%s</div>'
                   % (' class="win"' if is_win else "", cell))
    if win and not seen_win:
        raise SpecBuildError(
            node.line,
            "win=%r names no cell of this verdict — the winner is one of the "
            "labels in the table's second column" % win)
    out.append("</div>")
    return "\n".join(out)


@emitter("callout")
def emit_callout(node, ctx):
    _attrs(node, set(), forbid_id=True)
    return '<div class="%s">\n%s\n</div>' % (
        _classes("callout", node),
        md_body.fragment("\n".join(_prose_lines(node))))


def _data_lines(node):
    """A leaf block's body as `[(spec_line, text)]`.

    `_prose_lines` joins the runs and loses which line each one was, which is
    exactly what a `chart` refusal needs: "the value in column 2 is not a
    number" is only useful with the line the author reads it on. The refusals
    for a nested fence and for `::: prose` are the same ones `_prose_lines`
    raises, and for the same reasons.
    """
    out = []
    for child in node.children:
        if child.block_type == "prose" and child.authored:
            _refuse_prose_fence(child)
        if child.block_type != "prose":
            _check_parent(child, node.block_type)
            raise SpecBuildError(
                child.line, "`%s` cannot contain a `%s` block — its body is "
                "data rows" % (node.block_type, child.block_type))
        for i, ln in enumerate(child.raw_body):
            out.append((child.line + i, ln))
    return out


@emitter("chart")
def emit_chart(node, ctx):
    """`::: chart {type=bar title="…" unit="…"}` — bars, lines or stacked bars.

    `type` is the one spelling, here and in both references. An earlier draft
    also accepted `kind=`; two spellings of one attr is how a vocabulary and
    the code that reads it start to disagree, and the lockstep test Phase 4
    adds cannot see a synonym that only lives in an emitter.

    There is no default. A chart whose kind is missing is refused, not drawn as
    a bar chart: the two kinds say different things about the same rows (a line
    claims the categories are ordered and the gaps between them are real), and
    guessing which claim the page makes is not this file's to guess.
    """
    a = _attrs(node, {"type", "title", "unit"})
    kind = (a.get("type") or "").strip()
    if not kind:
        raise SpecBuildError(
            node.line,
            "`chart` needs type=\"bar\", type=\"line\" or type=\"stacked\" — "
            "there is no default, because a line claims the rows are ordered "
            "and a bar does not")
    if kind not in chart_svg.KINDS:
        raise SpecBuildError(
            node.line, "`chart` type=%r is not one of: %s"
            % (kind, ", ".join(chart_svg.KINDS)))

    rows = _data_lines(node)
    if not any(ln.strip() for _n, ln in rows):
        raise SpecBuildError(
            node.line,
            "`chart` has no data rows — its body is `label,value` lines or a "
            "pipe table, and an empty chart is a block with nothing to draw")
    labels, series = chart_svg.parse_data(rows, kind)
    if kind == "stacked":
        room = chart_svg.stacked_plot_width(labels, series,
                                            a.get("unit", "").strip())
        if room < chart_svg.MIN_STACK_PLOT:
            raise SpecBuildError(
                node.line,
                "`chart` type=stacked: the totals written past the bars (with "
                "`unit`) leave %d px of room for the bars, and the least a "
                "stacked chart draws is %d — shorten `unit`"
                % (room, chart_svg.MIN_STACK_PLOT))
    if len(series) > chart_svg.MAX_SERIES:
        # Unreachable through `parse_data`, which refuses the wide header at
        # the header's own line. Kept because the bound belongs to the COLOUR
        # vocabulary, not to the table syntax: tokens.css stops at `--s8` and
        # says a ninth series folds into "other" or faceted, never cycles back
        # onto `--s1`. A second series wearing the first one's colour is a
        # chart that lies where the reader cannot check it.
        raise SpecBuildError(
            node.line,
            "`chart` has %d series and the kit has %d series tokens "
            "(--s1..--s8)" % (len(series), chart_svg.MAX_SERIES))
    return chart_svg.figure(kind, labels, series,
                            title=a.get("title", "").strip(),
                            unit=a.get("unit", "").strip(),
                            classes=" ".join(node.classes),
                            ident=node.id or "")


@emitter("diagram")
def emit_diagram(node, ctx):
    """`::: diagram {shape=row title="…"}` — boxes and arrows, kit classes.

    `shape` is required and has no default, for `chart`'s reason: the three
    shapes say different things about the same boxes (a `cycle` claims the last
    step feeds the first; a `before-after` claims the two lanes are the same
    thing at two times), and guessing which claim the page makes is not this
    file's to guess.

    The three refusals HERE are the three an author fixes at the fence: a
    missing or unknown shape, and a body with nothing in it. Everything about a
    line of the body — an unknown box name, a self-arrow, an empty label, a
    lane in the wrong shape — is refused by `diagram_layout.parse_body` at the
    line INSIDE the fence, with `SpecSyntaxError`, exactly as `chart` does.
    """
    a = _attrs(node, {"shape", "title"})
    shape = (a.get("shape") or "").strip()
    if not shape:
        raise SpecBuildError(
            node.line,
            "`diagram` needs shape=\"%s\" — there is no default, because a "
            "`cycle` claims the last box feeds the first and a `row` does not"
            % '" or "'.join(diagram_layout.SHAPES))
    if shape not in diagram_layout.SHAPES:
        raise SpecBuildError(
            node.line, "`diagram` shape=%r is not one of: %s"
            % (shape, ", ".join(diagram_layout.SHAPES)))

    rows = _data_lines(node)
    if not any(ln.strip() for _n, ln in rows):
        raise SpecBuildError(
            node.line,
            "`diagram` has no body — its body is `name: Label` boxes and "
            "`A -> B` arrows, and a diagram with no boxes is a block with "
            "nothing to draw")
    boxes, arrows, titles = diagram_layout.parse_body(rows, shape)
    if not boxes:
        # UNREACHABLE through `parse_body`, which refuses every non-blank line
        # that is not a box, and refuses an arrow naming a box no line
        # declares. Kept because `diagram_layout.layout()` divides by the box
        # count and raises a bare `ValueError` on zero — a type no caller of
        # `build()` catches. Same bargain `emit_chart` keeps with its ninth
        # series: the guard the renderer needs is stated at the layer that
        # holds the fence's line.
        raise SpecBuildError(
            node.line,
            "`diagram` declares no box — an arrow needs two boxes and a "
            "picture needs one")
    if diagram_layout.SHAPE_ALIASES[shape] == "cycle" and len(boxes) < 2:
        raise SpecBuildError(
            node.line,
            "`diagram` shape=%r has one box — a cycle of one is a box, and "
            "the ring it would be placed on has no second point to turn "
            "around" % shape)
    lay = diagram_layout.layout(shape, boxes, arrows, titles)
    return diagram_svg.figure(lay,
                              title=a.get("title", "").strip(),
                              classes=" ".join(node.classes),
                              ident=node.id or "")


# The file types a `figure` embeds, and the MIME type of the raster ones.
FIGURE_RASTER = {".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
FIGURE_TYPES = (".svg",) + tuple(FIGURE_RASTER)


@emitter("figure")
def emit_figure(node, ctx):
    """`::: figure {#id src="rel/path.svg" title="…"}` — a drawing from a file.

    The third rung of the figure ladder: what neither a closed block (`chart`,
    `diagram`) nor an engine can draw — a hand SVG from figure-opus, a
    screenshot — enters the page here, still on the spec route. An `.svg` is
    INLINED, after `check_artifact.svg_embed_violations` (the owner of the rules;
    no copy lives here) finds nothing to refuse; a `.png`/`.jpg` becomes an
    `<img>` with a data URI and a required `alt`, because a picture of a screen
    says nothing to a reader who cannot see it. `src` is relative to the SPEC,
    for `gallery rows=`'s reason: the same spec must build from anywhere.

    The file is embedded byte for byte. A file that breaks a rule is refused,
    never repaired: a builder that rewrote a colour would ship a drawing its
    author never saw.
    """
    a = _attrs(node, {"src", "title", "alt"}, required=("src",))
    _no_children(node)
    src = a["src"].strip()
    if os.path.isabs(src):
        raise SpecBuildError(
            node.line, "`figure` src=%r is absolute — write it relative to the "
            "spec, so the spec builds from any checkout" % src)
    ext = os.path.splitext(src)[1].lower()
    if ext not in FIGURE_TYPES:
        raise SpecBuildError(
            node.line, "`figure` src=%r has type %r; a figure embeds %s"
            % (src, ext or "(none)", ", ".join(FIGURE_TYPES)))
    path = os.path.join(ctx.base_dir, src)
    if not os.path.isfile(path):
        raise SpecBuildError(
            node.line, "`figure` src=%r: no such file (looked in %s)"
            % (src, ctx.base_dir))
    alt = a.get("alt", "").strip()
    if ext == ".svg":
        if alt:
            raise SpecBuildError(
                node.line, "`figure` alt= is for a png/jpg; an inline SVG "
                "carries its own text")
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError) as exc:
            raise SpecBuildError(
                node.line, "`figure` src=%r cannot be read as UTF-8 SVG "
                "text (%s)" % (src, exc)) from None
        why, drawing = check_artifact.svg_embed_sanitize(text)
        if any("not <svg>" in w for w in why):
            raise SpecBuildError(
                node.line, "`figure` src=%r holds no <svg> root element (%s)"
                % (src, "; ".join(why)))
        if why:
            raise SpecBuildError(
                node.line, "`figure` src=%r is refused: %s"
                % (src, "; ".join(why)))
        # `drawing` is the PARSED tree re-serialised, never a slice of the
        # file: what the browser reads is exactly what was checked.
    else:
        if not alt:
            raise SpecBuildError(
                node.line, "`figure` src=%r needs alt=\"…\" — say what the "
                "picture shows for a reader who cannot see it" % src)
        try:
            with open(path, "rb") as fh:
                data = base64.b64encode(fh.read()).decode("ascii")
        except OSError as exc:
            raise SpecBuildError(
                node.line, "`figure` src=%r cannot be read (%s)"
                % (src, exc)) from None
        drawing = '<img src="data:%s;base64,%s" alt="%s">' % (
            FIGURE_RASTER[ext], data, esc(alt))
    head = "<figure"
    if node.id:
        head += ' id="%s"' % esc(node.id)
    if node.classes:
        head += ' class="%s"' % esc(" ".join(node.classes))
    out = [head + ">", drawing]
    title = a.get("title", "").strip()
    if title:
        out.append("<figcaption>%s</figcaption>" % esc(title))
    out.append("</figure>")
    return "\n".join(out)


@emitter("graph")
def emit_graph(node, ctx):
    """`::: graph {title="…"}` — a DOT body, laid out by Graphviz, kit classes.

    Rung 2 of the figure ladder: boxes and edges whose layout `diagram` cannot
    express (a star, a layered mapping, labelled edges, two edge kinds,
    containment). Everything about the DOT and its SVG is `graph_svg.py`'s;
    here are the refusals that name the fence's line — an empty body, no `dot`
    on PATH (with the install line), and Graphviz's own error, which carries
    the spec line of the DOT line it names.
    """
    a = _attrs(node, {"title"})
    rows = _data_lines(node)
    if not any(ln.strip() for _n, ln in rows):
        raise SpecBuildError(
            node.line,
            "`graph` has no body — its body is a DOT graph (`digraph { a -> b "
            "}`), and a graph with nothing in it is a block with nothing to "
            "draw")
    try:
        svg, version = graph_svg.render("\n".join(ln for _n, ln in rows),
                                        first_line=rows[0][0])
    except graph_svg.GraphError as exc:
        raise SpecBuildError(node.line, "`graph`: %s" % exc) from None
    return graph_svg.figure(svg, version, title=a.get("title", "").strip(),
                            classes=" ".join(node.classes),
                            ident=node.id or "")


@emitter("note")
def emit_note(node, ctx):
    # `note` takes `.warn`: components.css styles `.note.warn` and nothing else
    # about a note, so the class list is the whole vocabulary here.
    #
    # A note may nest a note (or a callout), in the position it was written. One
    # sampled page closes an aside with
    # a second, quieter one inside it; the alternative spellings both lie about
    # the page — two siblings say the second aside qualifies the prose around
    # it rather than the first, and folding them into one says the author wrote
    # one frame where they drew two.
    _attrs(node, set(), forbid_id=True)
    parts = []
    for kind, payload in _segments(node, ASIDES):
        if kind == "block":
            parts.append(emit_node(payload, ctx, parent="note"))
        else:
            parts.extend(md_body.blocks("\n".join(payload)))
    # `_unwrap_p` still fires on the one-paragraph note the corpus writes as
    # bare text inside the div; a note holding a nested one ends in `</div>`,
    # so it cannot match and is not unwrapped.
    return '<div class="%s">%s</div>' % (
        _classes("note", node), _unwrap_p("\n".join(parts)))


# --- the walk ----------------------------------------------------------------
def _check_parent(node, parent):
    """Refuse a block whose PARENTS entry does not list where it was written.

    Every entry exists because check_artifact.py's consult-shape rules have
    something to say about that placement: an item outside a block, a block
    inside a block, a masthead that is not the page's opening.
    """
    allowed = PARENTS.get(node.block_type)
    if allowed is None or parent in allowed:
        return
    where = ", ".join("the document" if p is None else "`%s`" % p
                      for p in allowed)
    raise SpecBuildError(
        node.line,
        "`%s` may only appear in %s, not in %s"
        % (node.block_type, where,
           "the document" if parent is None else "`%s`" % parent))


def emit_node(node, ctx, parent=None):
    if node.block_type not in EMITTERS:
        hint = INLINE_HINT.get(node.block_type)
        if hint:
            raise SpecBuildError(
                node.line, "`%s` is not a block: %s" % (node.block_type, hint))
        raise SpecBuildError(
            node.line,
            "unknown block type %r (known: %s)"
            % (node.block_type, ", ".join(sorted(EMITTERS))))
    _check_parent(node, parent)
    return EMITTERS[node.block_type](node, ctx)


def emit_children(node, ctx):
    """The children of a block that HOLDS blocks — `group` today.

    A blank prose run between two fences is dropped: the grammar makes it a
    node (a blank line is a content line) and an empty `<p>` on the page is not
    what it meant.
    """
    out = []
    for child in node.children:
        if _blank_prose(child):
            continue
        out.append(emit_node(child, ctx, node.block_type))
    return out


def _blank_prose(node):
    """A BLANK implicit prose run — the node a blank line between two fences
    makes, dropped because an empty `<p>` is not what it meant.

    An authored `::: prose` fence is never one of these, however empty it looks:
    its body lives in a child, so `text` is "" for a fence that may hold three
    paragraphs. Reading it as a blank run is how that body left the page
    silently, which is the one outcome `_refuse_prose_fence` exists to prevent.
    """
    return (node.block_type == "prose" and not node.authored
            and not node.text.strip())


def _walk(nodes):
    for node in nodes:
        yield node
        for sub in _walk(node.children):
            yield sub


# What makes a page a consultation: an item, the general-notes item, or a
# gallery row. All three carry a reply surface, and the kit chrome the reader
# needs to ANSWER — the two copy bars — is injected here rather than written by
# an author, exactly as the template says ("they arrive by wrapping, so a page
# cannot ship without them and an author cannot get them wrong").
ANSWERABLE = ("item", "notes", "gallery")


def spec_lang(spec_text):
    """The page's OWN language, from the masthead's `lang=`; "" when unset.

    The language is a property of the page, not of the command that builds it.
    Two of the 30 sampled pages are written in English; with the language fixed
    at the CLI's `es` default they built into `<html lang="es">` over an English
    body, which `check_artifact`'s `lang` rule fails (BL-279) — on pages whose
    originals pass. No spec could clear that, because no spec could say it.

    The declaration WINS over the `lang=` argument and over `--lang`: one owner
    per fact. The argument is the default for a spec that stays silent.
    """
    for node in parse(spec_text):
        if node.block_type == "masthead":
            value = node.attrs.get("lang", "").strip()
            if value and value not in LANGS:
                raise SpecBuildError(
                    node.line, "`masthead` lang=%r is not one of %s"
                    % (value, ", ".join(LANGS)))
            if value:
                return value
    return ""


def _refuse_links(spec_text):
    """Refuse a `[text](target)` whose target is not a relative path, a
    `#fragment` or `https:`, naming the spec line it is on.

    `md_body._inline` is the owner of what becomes an `<a>`; this only reads its
    verdict (`md_body.refused_links`) line by line, outside ``` / ~~~ fences,
    so the author gets a line number instead of a literal link on the page.
    """
    fence = None
    for n, ln in enumerate(spec_text.split("\n"), 1):
        fm = md_body.FENCE.match(ln)
        if fm and (fence is None or fm.group(1) == fence):
            fence = None if fence else fm.group(1)
            continue
        if fence:
            continue
        for target in md_body.refused_links(ln):
            raise SpecBuildError(
                n, "link target %r is refused: a spec links only to a "
                "relative path, a #fragment, https:, http: or mailto: "
                "(javascript:, data:, file:, every other scheme and a "
                "backslash escape in the target are refused)" % target)


def _refuse_title_links(tree):
    """A `[x](y)` in `title=` is refused: the title also reaches the rail and a
    decided item's <summary> as `data-title`, raw, where no link is rendered."""
    for node in _walk(tree):
        title = node.attrs.get("title", "")
        if md_body.LINK.search(md_body.CODE.sub(" ", title)):
            raise SpecBuildError(
                node.line, "`%s` title= holds a link, %r: the title is also the "
                "rail entry and shows there as raw text. Put the link in the "
                "body" % (node.block_type, title))


def build(spec_text, lang=None, base_dir="."):
    """The spec as an artifact-kit page BODY (no doctype, no head).

    Deterministic: same text in, byte-identical HTML out. Wrapping the body into
    a document is `wrap-report.sh`'s job and is where the build stamp lives.
    """
    lang = spec_lang(spec_text) or lang or "es"
    ctx = BuildContext(lang=lang, base_dir=base_dir)
    tree = parse(spec_text)
    _refuse_links(spec_text)
    _refuse_title_links(tree)
    answerable = any(n.block_type in ANSWERABLE for n in _walk(tree))

    head = []
    for node in tree:
        if node.block_type == "masthead":
            visual = node.attrs.get("visual", "").strip()
            if visual:
                head.append('<meta name="consult-visual" content="%s">'
                            % esc(visual))

    body = [emit_node(n, ctx) for n in tree if not _blank_prose(n)]

    out = list(head)
    out.append('<div class="page">')
    out.append('<main class="main">')
    out.extend(body)
    if answerable:
        out.append('<div class="endbar">')
        out.append('  <button type="button" id="consult-copy-end">%s</button>'
                   % esc(ctx.s["copy"]))
        out.append('  <span class="consult-status" id="consult-status-end"></span>')
        out.append("</div>")
    out.append("</main>")
    out.append('<aside class="rail">')
    out.append('  <p class="railhead">Contents</p>')
    out.append('  <nav class="raillist" id="raillist"></nav>')
    if answerable:
        out.append('  <div class="consult-bar">')
        out.append('    <button type="button" id="consult-copy">%s</button>'
                   % esc(ctx.s["copy"]))
        out.append('    <span class="consult-status" id="consult-status"></span>')
        out.append("  </div>")
    out.append("</aside>")
    out.append("</div>")
    return "\n".join(out) + "\n"


def page_title(spec_text):
    """The title the wrap puts in `<title>`: the masthead's, or "" when there
    is no masthead to take it from."""
    for node in parse(spec_text):
        if node.block_type == "masthead":
            if node.attrs.get("title", "").strip():
                return node.attrs["title"].strip()
            # `_segments`, the same walk `emit_masthead` uses, and NOT
            # `_prose_lines`: a masthead may nest an aside, and `_prose_lines`
            # refuses one. This is the CLI's own reader of the masthead body,
            # it runs before the wrap, and the two must agree about what a
            # masthead may hold — while they did not, `spec_build.py <spec>`
            # refused with "`masthead` cannot contain a `note` block" a page
            # that `build()` had just produced without complaint.
            for kind, payload in _segments(node, ASIDES):
                if kind != "prose":
                    continue
                for ln in payload:
                    if ln.startswith("# "):
                        return ln[2:].strip()
    return ""


# --- CLI ---------------------------------------------------------------------
def main(argv):
    p = argparse.ArgumentParser(
        prog="spec_build.py",
        description="Build a page spec into artifact-kit HTML.")
    p.add_argument("spec", metavar="<spec.md>", help="the page spec")
    p.add_argument("-o", dest="out", metavar="<out.html>",
                   help="write the WRAPPED page here (wrap-report.sh supplies "
                        "the document envelope, the kit and the build stamp). "
                        "Without it the page BODY goes to stdout")
    p.add_argument("--check", action="store_true",
                   help="run check-artifact.sh on the result and exit with its "
                        "status. Needs -o: the contract cannot be checked "
                        "against a pipe (BL-126)")
    p.add_argument("--lang", default=None, choices=LANGS,
                   help="the page's language when the masthead does not "
                        "declare one with lang=\u2026 (default: es). A "
                        "declaration wins: the language is the page's, not the "
                        "command's")
    p.add_argument("--title", default=None,
                   help="the document title. Default: the masthead's")
    args = p.parse_args(argv)

    try:
        with open(args.spec, encoding="utf-8") as fh:
            spec_text = fh.read()
    except OSError as exc:
        sys.stderr.write("spec-build: %s\n" % exc)
        return 2
    if args.check and not args.out:
        sys.stderr.write("spec-build: --check needs -o <out.html>\n")
        return 2

    try:
        lang = spec_lang(spec_text) or args.lang or "es"
        body = build(spec_text, lang=lang,
                     base_dir=os.path.dirname(os.path.abspath(args.spec)))
        title = args.title or page_title(spec_text)
    except (SpecSyntaxError, SpecBuildError) as exc:
        sys.stderr.write("%s:%d: %s\n" % (args.spec, exc.line, exc.message))
        return 1

    if not args.out:
        sys.stdout.write(body)
        return 0
    if not title:
        sys.stderr.write("spec-build: no document title — give the masthead a "
                         "title, or pass --title\n")
        return 2

    # Through STDIN, not a temp file: `--in` would leave a path beside the page
    # for the window of the wrap, and the wrap keeps the author's source itself
    # (`<baseline>.body`). Content on stdin is page markup, which is what this is.
    rc = subprocess.run(["bash", WRAP, "--title", title, "--lang", lang,
                         "--out", args.out],
                        input=body.encode("utf-8")).returncode
    if rc != 0:
        return rc
    if args.check:
        # wrap-report.sh --out already verified the contract; re-running it is
        # what makes --check an INDEPENDENT gate whose status this command
        # propagates, which is what Task 1.4 asks for. It is cheap and it does
        # not depend on the wrap having been the thing that wrote the file.
        return subprocess.call(["bash", CHECK, args.out])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
