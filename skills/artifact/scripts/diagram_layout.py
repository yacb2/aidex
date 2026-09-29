#!/usr/bin/env python3
"""diagram_layout.py — the `::: diagram` body grammar and its box/arrow layout.

The parse-and-place half of Phase 6. `diagram_svg.py` is the other half and
does nothing but serialise what comes out of here, so every number a reader can
be wrong about is decided in this file and is testable without parsing SVG.

Why hand-rolled at all
----------------------
`.context/research/2026-09-23-deterministic-diagrams-prior-art.md` compared
Graphviz, D2, Pikchr, Mermaid, PlantUML, svgbob, Kroki and ELK and recommended
the "hand-rolled stdlib grid/flow layout" row for exactly the shapes the corpus
draws: all 71 flow figures it measured are a row of boxes, a before/after split
or a small ring, none of which needs Sugiyama layering or edge-crossing
minimisation. Graphviz stays the documented fallback for anything that outgrows
this grid; it is NOT adopted, and this module adds no binary dependency (the
plan's Non-goals).

Text-first sizing (the plan's Q10)
----------------------------------
A box is sized to its LABEL (and its sublabel), measured before anything is
placed. Nothing here has a fixed box width, and a label is never truncated or
clipped — the prior-art note names "text past box edges" as the failure a
layout engine removes by construction, and the acceptance is 0 `svg-text`
warnings.

Labels are drawn in the kit's SANS stack (artifact-quality Phase 4: the
monospace labels read as forced, at twice the body size). A proportional font
has no single table, so `text_width` sums a PER-CHARACTER table holding the
widest advance across the stack's real fonts (SF Pro, Segoe UI, Roboto, DejaVu
Sans, Liberation Sans: `diagram_widths.py`, derived by
`derive_glyph_widths.py`), and takes the LARGER of that and
`check_artifact.svg_text_width`, the checker's own estimate (`MMMM` is 0.85 em
there): a box is never narrower than the checker measures its label. A
character outside the table falls back to `chart_svg._text_width`'s generous
0.62 em, doubled for an East-Asian Wide or Fullwidth one. It counts
CHARACTERS, never bytes: `señor` is 6 bytes and 5 characters.

Direction (`row` only)
----------------------
A `row` is ranked in declaration order (`_ranks`): each box one past the
previous one, or further when a box pointing FORWARD at it (declared earlier)
is further on. Two consecutive boxes that one box points at share a rank — a
branch, stacked in one column; nothing else is stacked.
`lr` places ranks left to right and is the default when that drawing fits the
page (`MAX_BOX_W`); otherwise the columns wrap into `lr` rows (`_wrap_lr`, cross
arrows in `_layout_lr`), and only when one column alone is over the page, `tb`,
one box per line in declaration order.
A wide `lr` drawing also gets a `tb` twin for narrow screens (`drawings()`):
the kit stretches a figure to its column, and a 700-unit flow in a 294 px
column draws 13-unit text at 5 px.

Everything is refused, or laid out. Nothing is silently clipped.
"""

import copy
import itertools
import math
import os
import re
import sys
import unicodedata

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, _HERE)
sys.path.insert(0, os.path.join(_HERE, "dash"))
from spec_parser import SpecSyntaxError            # noqa: E402
from chart_svg import _text_width                  # noqa: E402
from check_artifact import svg_text_width          # noqa: E402
from diagram_widths import GLYPH_WIDTHS            # noqa: E402

# --- the shape vocabulary ----------------------------------------------------
# `pipeline` is a spelling of `row`, not a fourth shape: the corpus writes both
# words for the same picture. Resolved once, here, so nothing downstream carries
# two names for one layout.
SHAPE_ALIASES = {"row": "row", "pipeline": "row",
                 "before-after": "before-after", "cycle": "cycle",
                 "tree": "tree", "compare": "compare"}
SHAPES = tuple(SHAPE_ALIASES)

NAME = re.compile(r"^[A-Za-z0-9_-]+$")
BOX_LINE = re.compile(r"^([A-Za-z0-9_-]+)\s*:(.*)$")
ARROW_LINE = re.compile(r"^([A-Za-z0-9_-]+)\s*->\s*([A-Za-z0-9_-]+)$")
# `lane` is a reserved first word, with or without a colon, so `lane: Antes`
# and `lane Antes` are one thing and neither can be read as a box named
# `lane`. The negative lookahead keeps `lane-1: x` a BOX: a name is allowed to
# start with the letters `lane`, only to BE them is not.
LANE_LINE = re.compile(r"^lane(?![A-Za-z0-9_-])\s*:?\s*(.*)$")
# The C0 controls XML 1.0 forbids in character data — everything below 0x20
# except tab, LF and CR (neither of the last two can reach a label: a body row
# is one physical line). `esc()` is `html.escape`, which passes them through
# RAW, so one of these in a label makes the emitted <svg> not well-formed:
# `xml.dom.minidom.parseString` refuses it and a browser's XML parser can drop
# the figure. `check_artifact` never sees it — its SVG rules are regexes over
# text. Refused rather than stripped, because this module's contract is
# "everything is refused, or laid out", and a silent strip would draw a label
# the author did not write.
CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f]")
# A `tree` mark line: `badge name: text`, `lock name`, `acc name`, `flg name`.
# Read AFTER the box and arrow rules, so `badge: x` stays a box named badge and
# `lock -> x` stays an arrow; only a first word followed by a space is a mark.
MARK_LINE = re.compile(r"^(badge|lock|acc|flg)\s+(\S.*)$")
BADGE_REST = re.compile(r"^([A-Za-z0-9_-]+)\s*:\s*(.*)$")
# A `compare` line: `panel tree Title`, `outcome text`, `recommended`. Read only
# AFTER the box and arrow rules, like the tree marks, so `outcome: x` is still a
# box named outcome; only a first word followed by a space (or nothing) counts.
PANEL_LINE = re.compile(r"^(panel|outcome|recommended)(?![A-Za-z0-9_-])\s*(.*)$")

# --- geometry, in viewBox units ----------------------------------------------
FS = 13.0              # the box label
SUB_FS = 12.0          # a sublabel: 11 px at 390 in a drawing NARROW_W wide
TITLE_FS = 11.0        # a lane title
PAD_X = 14.0           # inside a box, each side. Also the whole svg-text margin
BOX_H = 44.0
SUB_BOX_H = 52.0       # every box of a diagram where any box has a sublabel
# A decision's extra width, for its round ends. A one-line label's glyph box
# spans about +-8 units around the middle, where a half circle of radius 22-26
# gives up under 3 units per side; 12 keeps the label clear of the curve.
DEC_X = 12.0
VGAP = 14.0            # between two boxes stacked in one `lr` column
TB_GAP = 28.0          # between two boxes of a `tb` drawing: the arrow corridor
# A drawing is shown at most this many px per viewBox unit (a max-width on the
# root): 13-unit labels at 13 px, the size a hand figure's text is drawn at (its
# viewBox is its display width). Without it the kit's `figure svg { width: 100% }`
# blew a short row up to twice body size; at 1.2 the engine's text read 15.6 px
# beside the page's 13 px hand figures (BL-515 phase 4).
MAX_SCALE = 1.0
# A drawing at most this wide keeps 12-unit sublabels at 11 px in the kit's
# 294 px column at 390 (294 * 12 / 11); a wider `lr` gets a `tb` twin.
NARROW_W = 320.0
GAP = 32.0             # between two adjacent boxes in a row. Never 0: this is
                       # the corridor a straight arrow is drawn in, and the
                       # author cannot set it, so "adjacent boxes with zero gap"
                       # is not a state this layout can reach.
LANE_V = 46.0          # between the two lanes' rows of a before-after
TITLE_DROP = 9.0       # a lane title's baseline above its boxes' top edge
ARC = 34.0             # how far a before-after's curved arrow bows out
# A `row`'s detours are orthogonal and ONE LANE PER ARROW: a lane is the
# stretch of line one arrow runs along outside the boxes, and no two arrows
# that could be confused share one (`_lanes`).
DETOUR = 16.0          # the first lane's distance from the boxes it clears
LANE = 8.0             # between two lanes, and between two tracks in a gap
TRACK0 = 14.0          # a gap track's distance from the face it serves: the
                       # head is capped at half its last segment (`diagram_svg.
                       # _head`), so a head always fits its stub
SEP = 24.0             # two detours closer than this along their run take two
                       # lanes: more than the 2 * PORT_X between one box's
                       # in-port and out-port, so an arrow into a box and one
                       # out of it never read as one line through it
PORT = 7.0             # a side port's offset from the face's middle
PORT_X = 10.0          # a top/bottom port's offset from the box's middle
LINE_H = 16.0          # between two lines of a wrapped label
MARGIN = 16.0          # canvas margin around everything drawn
MIN_BOX_W = 72.0       # a one-character label still gets a box an arrow can
                       # point at without the head covering the glyph
# A box wider than the kit's page has no readable size left once
# `figure svg { width: 100% }` scales it down, so the label is refused rather
# than drawn at 3 px. 720 is chart_svg.W, the same page width.
MAX_BOX_W = 720.0
# The widest the kit's content column ever gets: `.page` at its 78rem cap less
# the 15rem rail and the 3.5rem gap (`components.css`), 59.5rem. The column is
# 632 px at a 1024 viewport and 888 at 1280, so a row wider than MAX_BOX_W but
# no wider than this ships its one-row drawing too, shown only where the
# figure is that wide (`one_row`, `diagram_svg.figure`; BL-525).
COL_MAX = 952.0
# The density cap: more boxes than this and the picture stops being read at a
# glance. Set from the reference set (`.context/proofs/consult-diagram-engine/
# reference-set/`): its 7 `engine.diagram` files hold 4, 4, 8, 5, 8, 5, 8 boxes,
# so 8 admits every figure the set draws and refuses the next one up. Refused
# at the fence's line by `spec_build.emit_diagram`.
MAX_BOXES = 8

# --- the `tree` shape, in viewBox units ---------------------------------------
LEVEL_GAP = 56.0       # between one level's bottom faces and the next's tops
BUS = 16.0             # an edge's horizontal run, below its parent's bottom face:
                       # the last leg is then LEVEL_GAP - BUS = 40, so the head
                       # (capped at half of it) is drawn at its full 16.25
SIB_GAP = 24.0         # between two neighbouring footprints on one level
BADGE_H = 18.0
BADGE_PAD = 8.0        # inside a badge pill, each side
BADGE_UP = 12.0        # a pill's top edge above its box's top edge: the pill
                       # straddles the border, 12 above and 6 below, so its text
                       # centre is OUTSIDE the box rect (the svg-text checker
                       # would otherwise read the badge as a label of the box)
BADGE_INSET = 24.0     # top-down: the pill starts this far right of the box's
                       # middle: the arrowhead there is 5.6 wide either side, so
                       # the pill clears it by 18 and never covers it
BADGE_LINE = 14.0      # a wrapped badge's line step (outline only)
BADGE_OUT = 12.0       # outline: the pill starts this far right of the box's left
LOCK_W = 10.0          # the lock glyph: a body LOCK_W x LOCK_H and a shackle
LOCK_H = 8.0
LOCK_RESERVE = 20.0    # what a locked box grows by, and its label moves left by
                       # half of: the glyph sits in the right-hand strip
INDENT = 44.0          # outline: one level's step right
SPINE = 16.0           # outline: the spine's distance from its parent's left face;
                       # the last leg is INDENT - SPINE = 28, head 14
OUT_GAP = 28.0         # outline: between two rows (a pill needs 12 of it)
PANEL_PAD = 12.0       # compare: inside a panel frame, each side
PANEL_GAP = 20.0       # compare: between the two frames, side by side or stacked
MIN_PANEL_W = 200.0    # compare: the narrowest content a panel gets, so an
                       # outcome sentence never wraps to a word a line
PANEL_TEXT_MAX = MAX_BOX_W - 2 * (PANEL_PAD + MARGIN)  # the widest title or
                       # outcome word a frame can hold inside the page's 720
PANEL_BODY_GAP = 12.0  # compare: title to body, and body to outcome


def columns(label):
    """The label's width in monospace COLUMNS.

    Wide and Fullwidth (CJK, fullwidth punctuation, most emoji) take two cells
    in every monospace font; everything else takes one. Combining marks are
    counted as one rather than zero ON PURPOSE: `check_artifact.svg_text_width`
    counts them through `len()`, and a metric that went below the checker's
    would size a box the checker then calls too small.
    """
    n = 0
    for ch in label:
        n += 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1
    return n


def text_width(label, size=FS):
    """The label's rendered width in viewBox units: never below the checker's.

    Per character, the widest advance any font of the `--sans` stack gives it
    (`diagram_widths.GLYPH_WIDTHS`, 1/1000 em, derived by
    `derive_glyph_widths.py`). A character the table lacks falls back to the
    generous 0.62 em estimate the chart legend uses (`chart_svg._text_width`),
    twice that for an East-Asian Wide or Fullwidth one. The result is floored
    at `check_artifact.svg_text_width`, so a box is never narrower than the
    checker measures its label.
    """
    em = 0.0
    for ch in label:
        w = GLYPH_WIDTHS.get(ch)
        if w is not None:
            em += w / 1000.0
        else:
            em += _text_width(ch, 1.0) * (
                2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1)
    return max(em * float(size), svg_text_width(label, float(size)))


def box_width(label, sub="", decision=False):
    w = max(text_width(label, FS), text_width(sub, SUB_FS)) + 2 * PAD_X
    return max(MIN_BOX_W, w) + (DEC_X if decision else 0.0)


# --- the parsed model --------------------------------------------------------
class Box(object):
    # `tone` is the kit class the renderer paints this box with — `acc`, `mut`
    # or `flg` of `components.css`. It is a LAYOUT fact, not a style choice:
    # which lane of a `before-after` a box is in is decided here and nowhere
    # else, so deciding it twice is what would let the two disagree.
    # `sub` is the second, smaller, muted line (`name: Label | sub`), "" when
    # absent. `decision` is a label ending in `?`: drawn as a rounded box.
    # A `tree` box may also carry a `badge` (text, drawn as a pill on its top
    # edge: `pill` is that pill's (x, y, w, h) once placed), a `lock` (a glyph
    # in its right-hand strip: `lock_at` is the body's top-left corner) and
    # `text_dx`, how far its label sits left of the middle to leave the strip.
    __slots__ = ("name", "label", "sub", "decision", "line", "lane", "w", "h",
                 "x", "y", "tone", "lines", "sub_lines", "badge", "lock",
                 "pill", "badge_lines", "lock_at", "text_dx")

    def __init__(self, name, label, line, lane, sub=""):
        self.name, self.label, self.line, self.lane = name, label, line, lane
        self.sub = sub
        self.decision = label.endswith("?")
        self.w, self.h = box_width(label, sub, self.decision), BOX_H
        self.x, self.y = 0.0, 0.0
        self.tone = "acc"
        # The label as drawn, one entry per line: a `tb` drawing wraps a label
        # too wide for 390 px (`_fit_tb`); everything else draws it whole.
        self.lines = [label]
        self.sub_lines = [sub] if sub else []
        self.badge, self.lock = "", False
        self.pill, self.lock_at, self.text_dx = None, None, 0.0
        self.badge_lines = []

    @property
    def cx(self):
        return self.x + self.w / 2.0

    @property
    def cy(self):
        return self.y + self.h / 2.0


class Arrow(object):
    __slots__ = ("src", "dst", "line")

    def __init__(self, src, dst, line):
        self.src, self.dst, self.line = src, dst, line


class Route(object):
    """One drawn arrow: 2 points for a straight line, 3 for a quadratic.

    `angle` is the direction the head points, in radians, computed from the
    last control point to the tip — for a straight line that is the segment's
    own direction, and for a curve it is the tangent at the end, which is what
    a quadratic's head has to follow to look attached to the line.
    """

    __slots__ = ("points", "angle", "tone")

    def __init__(self, points, angle, tone):
        self.points, self.angle, self.tone = points, angle, tone


class Panel(object):
    """One side of a `compare`: its option `title`, its body (`kind` is `tree`
    or `row`, `boxes` and `arrows` as `parse_body` reads them), its `outcome`
    sentence and whether it is the `recommended` one. `frame` (x, y, w, h),
    `title_at` (x, baseline y) and `outcome_lines` [(text, x, baseline y)] are
    set once the panel is placed."""

    __slots__ = ("kind", "title", "outcome", "recommended", "line", "boxes",
                 "arrows", "frame", "title_at", "outcome_lines", "rec_line")

    def __init__(self, kind, title, line):
        self.kind, self.title, self.line = kind, title, line
        self.outcome, self.recommended, self.rec_line = "", False, 0
        self.boxes, self.arrows = [], []
        self.frame, self.title_at, self.outcome_lines = None, None, []


class Layout(object):
    __slots__ = ("shape", "boxes", "routes", "titles", "divider", "view", "dir",
                 "panels")

    def __init__(self, shape, boxes, routes, titles, divider, view, dir=None,
                 panels=()):
        self.panels = list(panels)
        self.shape = shape          # the resolved shape
        self.dir = dir              # "lr" or "tb" for a `row`, else None
        self.boxes = boxes          # [Box], placed
        self.routes = routes        # [Route]
        self.titles = titles        # [(text, x, y)] — the lane titles
        self.divider = divider      # (x0, y, x1) or None
        self.view = view            # (min_x, min_y, width, height)


# --- the body grammar --------------------------------------------------------
def parse_body(rows, shape):
    """`(boxes, arrows, lane_titles)` from a `diagram` body.

    `rows` is `[(line_no, text)]`, every physical body line with the SPEC line
    it came from, exactly as `chart_svg.parse_data` takes it: a refusal names
    the line the author edits, inside the fence, never the fence itself.

    Three line kinds, blank lines ignored anywhere:

      `lane Antes`     opens a lane. `before-after` only, exactly two.
      `name: Label`    declares a box. The label is everything after the colon;
                       `name: Label | sub` adds a sublabel after the first `|`.
      `A -> B`         one arrow, from a declared box to another.

    A line is read as a BOX when it matches `name:` — before the arrow rule —
    so a label containing `->` (`step: build -> ship`) is a label and not an
    ambiguity. An arrow name cannot contain a colon, so nothing is lost.
    """
    shape = SHAPE_ALIASES[shape]
    if shape == "compare":
        return _parse_compare(rows)
    boxes, arrows, titles = [], [], []
    by_name = {}
    seen_arrow = set()
    marks = []                                     # tree: (kind, name, text, line)
    lane = None

    for n, raw in rows:
        line = raw.strip()
        if not line:
            continue

        m = LANE_LINE.match(line)
        if m:
            if shape != "before-after":
                raise SpecSyntaxError(
                    n, "`lane` is only a `before-after` line — shape=%r draws "
                       "one run of boxes, so there is no lane to open (`lane` "
                       "is a reserved first word; a box cannot be named it)"
                    % shape)
            title = m.group(1).strip()
            if not title:
                raise SpecSyntaxError(
                    n, "this `lane` has no title — the title is what tells a "
                       "reader which side of the comparison the lane is")
            _check_control(n, "this lane title", title)
            if len(titles) == 2:
                raise SpecSyntaxError(
                    n, "this is the 3rd `lane` and `before-after` has exactly "
                       "two — a third lane is a different picture, and the "
                       "shape that draws N runs is not in this vocabulary")
            if titles and not [b for b in boxes if b.lane == len(titles) - 1]:
                raise SpecSyntaxError(
                    n, "lane %r closed with no boxes in it — an empty lane "
                       "draws a title over nothing"
                    % titles[-1])
            titles.append(title)
            lane = len(titles) - 1
            continue

        m = BOX_LINE.match(line)
        if m:
            name, label = m.group(1), m.group(2).strip()
            sub = ""
            # `\|` is a literal bar; the first bare `|` opens the sublabel.
            parts = re.split(r"(?<!\\)\|", label, maxsplit=1)
            label = parts[0].replace("\\|", "|").strip()
            if len(parts) == 2:
                sub = parts[1].replace("\\|", "|").strip()
                if label and not sub:
                    raise SpecSyntaxError(
                        n, "box `%s` has an empty sublabel after `|` — write "
                           "the second line, or drop the `|`" % name)
                _check_control(n, "box `%s`'s sublabel" % name, sub)
            if not label:
                raise SpecSyntaxError(
                    n, "box `%s` has an empty label — a box is sized to its "
                       "label and a reader has nothing to read in an empty "
                       "one" % name)
            _check_control(n, "box `%s`'s label" % name, label)
            if name in by_name:
                raise SpecSyntaxError(
                    n, "box `%s` is already declared on line %d — a second "
                       "declaration would draw a second box under the same "
                       "name and every arrow naming it would be ambiguous"
                    % (name, by_name[name].line))
            box = Box(name, label, n, lane, sub)
            if box.w > MAX_BOX_W:
                raise SpecSyntaxError(
                    n, "box `%s` needs a %d-unit box for a %d-column label and "
                       "the page is %d wide — shorten the label or move the "
                       "sentence into prose next to the diagram"
                    % (name, round(box.w), columns(max(label, sub, key=len)),
                       int(MAX_BOX_W)))
            if shape == "before-after" and lane is None:
                raise SpecSyntaxError(
                    n, "box `%s` sits above the first `lane` line — every box "
                       "of a `before-after` belongs to one of the two lanes"
                    % name)
            boxes.append(box)
            by_name[name] = box
            continue

        m = ARROW_LINE.match(line)
        if m:
            src, dst = m.group(1), m.group(2)
            if src == dst:
                raise SpecSyntaxError(
                    n, "`%s -> %s` is an arrow from a box to itself — there is "
                       "no second box for it to reach, and a loop on one box "
                       "says nothing the box does not" % (src, dst))
            if (src, dst) in seen_arrow:
                raise SpecSyntaxError(
                    n, "`%s -> %s` is already declared — drawing it twice puts "
                       "two arrows on one another" % (src, dst))
            seen_arrow.add((src, dst))
            arrows.append(Arrow(src, dst, n))
            continue

        m = MARK_LINE.match(line)
        if m and m.group(1) != "badge" and "->" in line:
            m = None                # `lock -> b -> c` is a botched arrow line
        if m:
            marks.append(_parse_mark(n, shape, m.group(1), m.group(2).strip(),
                                     marks))
            continue

        if "->" in line:
            raise SpecSyntaxError(
                n, "%r is not an arrow — one arrow per line, `A -> B`, and "
                   "both names are box names (letters, digits, `_`, `-`); a "
                   "chain is written as one line per hop" % line)
        raise SpecSyntaxError(
            n, "%r is neither a box nor an arrow — a box is `name: Label`, an "
               "arrow is `A -> B`%s" % (line, ", and a lane is `lane Title`"
                                        if shape == "before-after" else
                                        ", and a tree also has `badge`, `lock`, "
                                        "`acc` and `flg` lines"
                                        if shape == "tree" else ""))

    _check_refs(boxes, arrows, by_name)
    if shape == "tree":
        _check_tree(boxes, arrows, by_name, marks)
    if shape == "before-after":
        if len(titles) < 2:
            raise SpecSyntaxError(
                rows[0][0] if rows else 0,
                "`before-after` needs two `lane` lines and this body has %d — "
                "the shape IS the comparison between them" % len(titles))
        if not [b for b in boxes if b.lane == 1]:
            raise SpecSyntaxError(
                rows[-1][0] if rows else 0,
                "lane %r has no boxes — an empty lane draws a title over "
                "nothing" % titles[1])
        _check_lanes(boxes, arrows, by_name)
    return boxes, arrows, titles


def _widest_word(text):
    """The widest run between spaces of `text`, the part `_wrap` cannot break."""
    return max(text_width(w, FS) for w in text.split(" "))


def _parse_compare(rows):
    """`(boxes, arrows, panels)` from a `compare` body.

    Three line kinds of its own, and every other line belongs to the panel it
    sits under, written exactly as a `tree` or a `row` body:

      `panel tree Title`   opens a panel (`row` for a row body). Exactly two.
      `outcome text`       the panel's outcome sentence. One per panel.
      `recommended`        the panel drawn in `acc`. At most one panel.

    Each panel's own lines go to `parse_body` under its body shape with their
    real line numbers, so every tree and row refusal still names the author's
    line. `boxes` and `arrows` are the panels' together (the fence counts them
    against the cap); each `Box.lane` is its panel's index.
    """
    panels, cur, cur_rows = [], None, []

    def close():
        if cur is None:
            return
        if not any(BOX_LINE.match(l.strip()) for _n, l in cur_rows):
            raise SpecSyntaxError(
                cur.line, "panel %r has no boxes — a panel draws a %s, so "
                          "write its `name: Label` lines under the `panel` line"
                          % (cur.title, cur.kind))
        if not cur.outcome:
            raise SpecSyntaxError(
                cur.line, "panel %r has no `outcome` line — the outcome is "
                          "where the reader learns what the option leads to, "
                          "and what a lock or a flagged box means" % cur.title)
        if cur.kind == "tree" and not cur.recommended:
            for n_, l_ in cur_rows:
                m_ = MARK_LINE.match(l_.strip())
                if m_ and m_.group(1) == "acc" and "->" not in l_:
                    raise SpecSyntaxError(
                        n_, "`acc` in panel %r, which is not `recommended` — "
                            "the accent belongs to the recommended panel; mark "
                            "what is affected with `flg`, or add `recommended` "
                            "to this panel" % cur.title)
        cur.boxes, cur.arrows, _t = parse_body(cur_rows, cur.kind)
        for b in cur.boxes:
            b.lane = len(panels) - 1
            if cur.kind == "row":
                b.tone = "mut"       # a row's boxes default to `acc`, which a
                                     # compare keeps for the recommended panel

    for n, raw in rows:
        line = raw.strip()
        if not line:
            continue
        m = None if (BOX_LINE.match(line) or ARROW_LINE.match(line)) \
            else PANEL_LINE.match(line)
        if m is None:
            if cur is None:
                raise SpecSyntaxError(
                    n, "%r sits above the first `panel` line — every line of "
                       "a `compare` belongs to one of its two panels" % line)
            cur_rows.append((n, raw))
            continue
        word, rest = m.group(1), m.group(2).strip()
        if word == "panel":
            close()
            if len(panels) == 2:
                raise SpecSyntaxError(
                    n, "this is the 3rd `panel` and `compare` has exactly two "
                       "— option A against option B; a third option is "
                       "another figure")
            kind, _sp, title = rest.partition(" ")
            title = title.strip()
            if kind not in ("tree", "row") or not title:
                raise SpecSyntaxError(
                    n, "a panel is `panel tree Title` or `panel row Title` — "
                       "the body shape, then the option's title; %r has %s"
                       % (rest, "no title" if kind in ("tree", "row")
                          else "no body shape (tree or row) first"))
            _check_control(n, "this panel title", title)
            if text_width(title, FS) > PANEL_TEXT_MAX:
                raise SpecSyntaxError(
                    n, "this panel title is wider than the %d units a frame "
                       "can hold on the page's %d — shorten it"
                    % (int(PANEL_TEXT_MAX), int(MAX_BOX_W)))
            cur, cur_rows = Panel(kind, title, n), []
            panels.append(cur)
        elif cur is None:
            raise SpecSyntaxError(
                n, "`%s` sits above the first `panel` line — it belongs to a "
                   "panel" % word)
        elif word == "outcome":
            if cur.outcome:
                raise SpecSyntaxError(
                    n, "panel %r already has an `outcome` — one sentence per "
                       "panel" % cur.title)
            if not rest:
                raise SpecSyntaxError(
                    n, "this `outcome` has no text — write the sentence after "
                       "the word")
            _check_control(n, "the outcome of %r" % cur.title, rest)
            if _widest_word(rest) > PANEL_TEXT_MAX:
                raise SpecSyntaxError(
                    n, "one word of this outcome is wider than the %d units a "
                       "frame can hold on the page's %d — shorten it"
                    % (int(PANEL_TEXT_MAX), int(MAX_BOX_W)))
            cur.outcome = rest
        else:
            if rest:
                raise SpecSyntaxError(
                    n, "`recommended` stands alone on its line, %r follows it"
                       % rest)
            others = [p for p in panels if p.recommended]
            if cur.recommended or others:
                raise SpecSyntaxError(
                    n, "panel %r is already `recommended` (line %d) — at most "
                       "one option is the recommended one"
                       % ((others or [cur])[0].title,
                          (others or [cur])[0].rec_line))
            cur.recommended, cur.rec_line = True, n
    close()
    if len(panels) != 2:
        raise SpecSyntaxError(
            panels[0].line if panels else (rows[0][0] if rows else 0),
            "`compare` needs two `panel` lines and this body has %d — the "
            "shape IS option A against option B" % len(panels))
    boxes = [b for p in panels for b in p.boxes]
    arrows = [a for p in panels for a in p.arrows]
    return boxes, arrows, panels


def _parse_mark(n, shape, kind, rest, marks):
    """One `tree` mark line as `(kind, name, text, line)`; refused elsewhere.

    `badge name: text` attaches a pill to a box; `lock name` puts a lock glyph
    in it; `acc name` / `flg name` paint it in that kit class. A box takes each
    kind once: a second badge would sit on the first, and two tones would leave
    the picture to say which one wins. Whether `name` is a declared box is
    checked once every box is known (`_check_tree`), at THIS line.
    """
    if shape != "tree":
        raise SpecSyntaxError(
            n, "`%s` is a `tree` line — shape=%r draws no marks on its boxes "
               "(`%s` is a reserved first word here, so a box cannot be "
               "written `%s name`)" % (kind, shape, kind, kind))
    text = ""
    if kind == "badge":
        m = BADGE_REST.match(rest)
        if not m or not m.group(2).strip():
            raise SpecSyntaxError(
                n, "a badge is `badge name: text` — the box it sits on, a "
                   "colon, and what it says; %r has %s" % (
                       rest, "no text after the colon" if m else
                       "no box name before a colon"))
        name, text = m.group(1), m.group(2).strip()
        _check_control(n, "the badge on `%s`" % name, text)
        if badge_w(text) > MAX_BOX_W:
            raise SpecSyntaxError(
                n, "the badge on `%s` needs a %d-unit pill and the page is %d "
                   "wide — shorten it" % (name, round(badge_w(text)),
                                          int(MAX_BOX_W)))
    else:
        if not NAME.match(rest):
            raise SpecSyntaxError(
                n, "`%s %s` — a `%s` line is `%s name`, one declared box's "
                   "name and nothing after it" % (kind, rest, kind, kind))
        name = rest
    tone = kind in ("acc", "flg")
    for k, nm, _t, ln in marks:
        if nm == name and (k == kind or (tone and k in ("acc", "flg"))):
            raise SpecSyntaxError(
                n, "box `%s` already has %s on line %d — %s" % (
                    name, "a %s" % k if k in ("badge", "lock") else
                    "the tone `%s`" % k, ln,
                    "a second one would be drawn on the first" if k == kind
                    else "one box takes one tone"))
    return kind, name, text, n


def _check_tree(boxes, arrows, by_name, marks):
    """Everything a `tree` needs that a line alone cannot show, then the marks
    applied to their boxes. Each refusal names the line the author edits.

    An arrow is `parent -> child`. A box with two parents is refused at the
    SECOND arrow into it: that is a graph, and `::: graph` draws it. A cycle is
    refused at its last-declared arrow. A forest (two boxes with no parent) is
    refused at the second root's declaration: a tree has one root, and two
    trees are two figures. Marks naming an undeclared box are refused at the
    mark's line, with the boxes that do exist.
    """
    parent, line_of = {}, {}
    for a in arrows:
        if a.dst in parent:
            raise SpecSyntaxError(
                a.line, "box `%s` already has the parent `%s` (line %d) and "
                        "this arrow gives it a second, `%s` — a tree box has "
                        "one parent; a shape with two is a graph (`::: graph`)"
                        % (a.dst, parent[a.dst], line_of[(parent[a.dst], a.dst)],
                           a.src))
        parent[a.dst] = a.src
        line_of[(a.src, a.dst)] = a.line
    for b in boxes:
        seen, cur = [], b.name
        while cur in parent and cur not in seen:
            seen.append(cur)
            cur = parent[cur]
        if cur in seen:
            ring = seen[seen.index(cur):]
            last = max((line_of[(parent[x], x)], x) for x in ring)
            raise SpecSyntaxError(
                last[0], "`%s -> %s` closes a cycle (%s) — a tree has no "
                         "arrow back up; write a loop as shape=cycle"
                         % (parent[last[1]], last[1],
                            " -> ".join(list(reversed(ring)) + [ring[-1]])))
    roots = [b for b in boxes if b.name not in parent]
    if len(roots) > 1:
        # The tree's root is the first one that has children; the stray is the
        # first other root, so `x: X` above `r: R` is blamed, not `r`.
        has_kids = {a.src for a in arrows}
        main = next((r for r in roots if r.name in has_kids), roots[0])
        stray = next(r for r in roots if r is not main)
        raise SpecSyntaxError(
            stray.line, "box `%s` has no parent and neither has `%s` — a "
                        "tree has one root; join it under a box, or draw "
                        "the two trees as two figures"
                        % (stray.name, main.name))
    known = ", ".join("`%s`" % b.name for b in boxes)
    for kind, name, text, n in marks:
        if name not in by_name:
            raise SpecSyntaxError(
                n, "`%s %s` names a box no line declares — the boxes are: %s"
                   % (kind, name, known))
    for b in boxes:
        b.tone = "mut"
    for kind, name, text, n in marks:
        b = by_name[name]
        if kind == "badge":
            b.badge = text
        elif kind == "lock":
            b.lock = True
            b.w += LOCK_RESERVE
            if b.w > MAX_BOX_W:
                raise SpecSyntaxError(
                    n, "box `%s` needs a %d-unit box with its lock and the "
                       "page is %d wide — shorten the label"
                       % (name, round(b.w), int(MAX_BOX_W)))
        else:
            b.tone = kind


def badge_w(text):
    """A badge pill's width."""
    return text_width(text, SUB_FS) + 2 * BADGE_PAD


def _check_control(n, what, text):
    """Refuse a label or a lane title holding an XML-illegal control character."""
    m = CTRL.search(text)
    if m:
        raise SpecSyntaxError(
            n, "%s holds the control character \\x%02x at position %d — it is "
               "not a character XML allows in text, so the <svg> this draws "
               "would not parse and the figure can vanish; delete it (it "
               "prints as nothing) or write the character you meant"
            % (what, ord(m.group(0)), m.start() + 1))


def _check_lanes(boxes, arrows, by_name):
    """The arrows a `before-after` cannot draw. Refused at the ARROW's line.

    Two kinds, one reason: the shape is a COMPARISON of two runs, and once the
    canvas is two rows tall neither an arrow BETWEEN the lanes nor one that
    SKIPS a box inside a lane has a corridor left to be drawn in — the room a
    `row` uses for those is where the other lane and the dividing rule now sit.
    Both are the `row` shape's picture, and the message says so rather than
    routing the arrow through a box.

    Note the lane counts are read INDEPENDENTLY: `before-after` with three
    boxes above and one below is a real page and is laid out, because each lane
    is placed on its own. It is the ARROWS that are constrained, not the lanes.
    """
    order = {}
    for lane in (0, 1):
        for i, b in enumerate([x for x in boxes if x.lane == lane]):
            order[b.name] = i
    for a in arrows:
        s_box, d_box = by_name[a.src], by_name[a.dst]
        if s_box.lane != d_box.lane:
            why = ("crosses the two lanes — a `before-after` compares them "
                   "side by side and draws no arrow between them")
        elif order[d_box.name] != order[s_box.name] + 1:
            why = ("skips over a box in its own lane — the room a `row` bows "
                   "that arrow through is taken by the other lane")
        else:
            continue
        raise SpecSyntaxError(
            a.line, "`%s -> %s` %s; write the flow as shape=row"
                    % (a.src, a.dst, why))


def _check_refs(boxes, arrows, by_name):
    """Every arrow names a declared box. Refused at the ARROW's line."""
    known = (", ".join("`%s`" % b.name for b in boxes)
             or "none — this body declares no box at all")
    for a in arrows:
        for name, side in ((a.src, "from"), (a.dst, "to")):
            if name not in by_name:
                raise SpecSyntaxError(
                    a.line,
                    "this arrow points %s `%s`, which no line declares — the "
                    "boxes are: %s" % (side, name, known))


# --- placement ---------------------------------------------------------------
def _place_run(boxes, y):
    """One left-to-right run of boxes at `y`. Returns the run's right edge.

    Each box is as wide as ITS OWN label — this is the Q10 decision, and it is
    why nothing here takes a max over the run: a grid sized to the longest
    label pads every short one, and a grid sized to the LAST one seen (the
    bug this shape invites) clips every label longer than it.
    """
    x = 0.0
    for b in boxes:
        b.x, b.y = x, y
        x += b.w + GAP
    return (x - GAP) if boxes else 0.0


def _tip(p0, p1):
    return math.atan2(p1[1] - p0[1], p1[0] - p0[0])


def _route_row(boxes, arrows, by_name):
    """The arrows of one left-to-right run, and how each is routed.

    Three cases, and each is a stated behaviour rather than a fallback:

      ADJACENT FORWARD (i -> i+1) — a straight segment across the GAP corridor.
      FORWARD, SKIPPING (i -> j, j > i+1) — a curve ABOVE the run. Drawn
        straight it would pass through every box between the two.
      BACKWARD (i -> j, j < i) — a curve BELOW the run, so it cannot be
        confused with, or drawn over, the forward arrows above it. It is also
        the one that gets the `flg` tone: a retry edge drawn like a forward one
        is the thing a reader cannot recover from the picture.
    """
    order = {b.name: i for i, b in enumerate(boxes)}
    routes = []
    for a in arrows:
        i, j = order[a.src], order[a.dst]
        s, d = by_name[a.src], by_name[a.dst]
        if j == i + 1:
            p0 = (s.x + s.w, s.cy)
            p1 = (d.x, d.cy)
            routes.append(Route([p0, p1], _tip(p0, p1), "mut"))
        elif j > i:
            p0 = (s.cx, s.y)
            p1 = (d.cx, d.y)
            c = ((p0[0] + p1[0]) / 2.0, s.y - ARC)
            routes.append(Route([p0, c, p1], _tip(c, p1), "mut"))
        else:
            p0 = (s.cx, s.y + s.h)
            p1 = (d.cx, d.y + d.h)
            c = ((p0[0] + p1[0]) / 2.0, s.y + s.h + ARC)
            routes.append(Route([p0, c, p1], _tip(c, p1), "flg"))
    return routes


def _ranks(boxes, arrows):
    """`{name: rank}` for a `row`: see the module docstring, § Direction.

    Ranks never decrease in declaration order, so a row stays a row. A box
    shares the previous box's rank (a BRANCH, stacked in one column) only when
    one box points forward at both of them and nothing forces it further on;
    otherwise it takes the later of "one past the previous box" and "one past
    its furthest forward source". One pass is enough: a forward arrow's source
    is declared earlier and is already ranked.
    """
    order = {b.name: i for i, b in enumerate(boxes)}
    into = {b.name: set() for b in boxes}
    for a in arrows:
        if order[a.src] < order[a.dst]:
            into[a.dst].add(a.src)
    rank, prev, last = {}, -1, None
    for b in boxes:
        srcs = into[b.name]
        need = max(rank[x] + 1 for x in srcs) if srcs else 0
        if last is not None and need <= prev and srcs & into[last.name]:
            rank[b.name] = prev
        else:
            rank[b.name] = max(prev + 1, need)
        prev, last = rank[b.name], b
    return rank


def _lanes(runs, step):
    """`{key: position}`, one lane per run: see `DETOUR`.

    `runs` is `[(key, lo, hi, base)]`: a detour runs from `lo` to `hi` along
    one axis and wants to sit at `base` on the other. Shortest runs first, so
    a detour nested inside another is drawn inside it. A run steps OUTWARD by
    `step` past every placed lane it would come within a lane of, when the two
    runs overlap or come within SEP of each other. The position only ever
    moves outward, so the loop ends.
    """
    placed, out = [], {}
    for key, lo, hi, base in sorted(runs, key=lambda r: (r[2] - r[1], r[0])):
        pos, moved = base, True
        while moved:
            moved = False
            for plo, phi, pp in placed:
                if (lo < phi + SEP and plo < hi + SEP
                        and abs(pos - pp) < abs(step) - 1e-9):
                    pos, moved = pp + step, True
        placed.append((lo, hi, pos))
        out[key] = pos
    return out


# A cross arrow's ports are the ones its ROLE already owns in a band: a forward
# arrow leaves the right face and enters the left face PORT above the middle
# (a skip's side ports), a backward one leaves the left face and enters the right
# face PORT below it. A cross arrow then shares a port only with an arrow of
# the same role at the same box (a fan out or in), and never sits within 3.5
# units of a port another role owns.
def _cross_route(s, d, forward, xo, xi, ys, chan):
    """A cross arrow of a wrapped row: `xo` the track it leaves by, `xi` the one
    it arrives by, `ys` the y of each corridor leg it runs along (one, or two
    when `chan` is the x of the channel that carries it past a whole band).

    Forward: out of the source's right face, into the target's left face.
    Backward: out of the source's left face, into the target's right face, in
    `flg`."""
    if forward:
        p0, p1 = (s.x + s.w, s.cy - PORT), (d.x, d.cy - PORT)
    else:
        p0, p1 = (s.x, s.cy + PORT), (d.x + d.w, d.cy + PORT)
    pts = [p0, (xo, p0[1]), (xo, ys[0])]
    if chan is not None:
        pts += [(chan, ys[0]), (chan, ys[1]), (xi, ys[1])]
    else:
        pts += [(xi, ys[0])]
    pts += [(xi, p1[1]), p1]
    return Route(pts, _tip(pts[-2], pts[-1]), "mut" if forward else "flg")


def _layout_lr(boxes, arrows, by_name, rank, cuts=()):
    """A `row` left to right: ranks as columns, then one route per arrow.

    `cuts` are the column indexes that start a new ROW of the drawing: the
    columns are then laid out left to right in bands, each band flush left and
    the next one below it (see § Wrapped rows below). Empty: one band, the
    drawing this function has always made.

    Placement: a column is as wide as its WIDEST box and its boxes take that
    width, stacked and centred on y=0, so every face of a column is flush with
    the gap beside it and a gap holds no box at all. A gap is GAP wide, or
    wider when the tracks drawn in it need the room.

    Every route leaves and enters by a port its ROLE owns, so an arrow into a
    box and one out of it never meet at a point (the ports, per box):

      NEXT RANK       out: right face, middle.  in: left face, middle.
                      Straight when the middles line up, else a quadratic
                      inside the one gap.
      SKIPPING RANKS  out: top face right of middle, or, below the top of a
                      stack, the right face above middle and a track in the
                      gap after. in: top face left of middle, or the left face
                      above middle from a track in the gap before. Between,
                      its own lane ABOVE every column it spans.
      BACK            the mirror under the row, in `flg`: out by the bottom
                      face left of middle (or the left face below middle), in
                      by the bottom face right of middle (or the right face
                      below middle). A backward arrow is drawn on the bottom
                      face, as the base drawing had it.
      SAME RANK       out: right face, 2 PORT below middle; in: right face,
                      2 PORT above; its own track in the gap after the column.
                      `flg` when it points back in declaration order (up).

    One track per arrow in a gap, one lane per arrow above or below
    (`_lanes`): two arrows that share no box share no stretch of line.

    Wrapped rows. Each band is drawn as above, from its own arrows. An arrow
    whose two ends sit in different bands (a CROSS arrow) leaves by the gap
    track after its source's column (or, backward, before it) and arrives by
    the gap track before its target's column (after it), exactly like a detour,
    and runs between the two along the CORRIDOR under the upper band, where
    the bands hold no box. A gap holds no box, so the vertical stretch in it is
    clear; when it must pass a whole band it runs in a channel right of
    everything (forward) or left of everything (backward), which holds no box
    either. That is why the rows read left to right with a return arrow rather
    than boustrophedon: the reading order of every row stays the same, and the
    return arrow needs nothing but a corridor and gap tracks, which exist.
    """
    cols = []
    for b in boxes:
        if rank[b.name] == len(cols):
            cols.append([])
        cols[rank[b.name]].append(b)
    band, nb_ = [], 0
    for r in range(len(cols)):
        if r in cuts:
            nb_ += 1
        band.append(nb_)
    bands = nb_ + 1
    top = {c[0].name for c in cols}
    bottom = {c[-1].name for c in cols}
    order = {b.name: i for i, b in enumerate(boxes)}

    # The tracks each arrow needs: (gap, half), gap g after column g (g = -1
    # before the first), half 0 against column g's right face, half 1 against
    # column g+1's left face.
    need = []
    for a in arrows:
        s, d = by_name[a.src], by_name[a.dst]
        rs, rd = rank[a.src], rank[a.dst]
        if band[rs] != band[rd]:
            need.append(((rs, 0), (rd - 1, 1)) if rd > rs
                        else ((rs - 1, 1), (rd, 0)))
        elif rd == rs + 1:
            need.append((None, None))
        elif rd == rs:
            need.append(((rs, 0), None))
        elif rd > rs:
            need.append((None if s.name in top else (rs, 0),
                         None if d.name in top else (rd - 1, 1)))
        else:
            need.append((None if s.name in bottom else (rs - 1, 1),
                         None if d.name in bottom else (rd, 0)))
    count = {}
    slot = []
    for pair in need:
        got = []
        for g in pair:
            if g is None:
                got.append(None)
            else:
                got.append((g, count.get(g, 0)))
                count[g] = count.get(g, 0) + 1
        slot.append(got)

    x = 0.0
    for r, col in enumerate(cols):
        if r in cuts:
            x = 0.0
        cw = max(b.w for b in col)
        for b in col:
            b.w = cw
            b.x = x
        n = count.get((r, 0), 0) + count.get((r, 1), 0)
        x += cw + max(GAP, 2 * TRACK0 + (n - 1) * LANE if n else 0.0)
    left = [c[0].x for c in cols]
    right = [c[0].x + c[0].w for c in cols]

    def track(g_k):
        (g, half), k = g_k
        if half == 0:
            return right[g] + TRACK0 + k * LANE
        return left[g + 1] - TRACK0 - k * LANE

    # Bands, top to bottom. A band is as tall as its tallest column, and the
    # corridor under it holds, from the top: its own below-lanes, the cross
    # arrows' lanes, the next band's above-lanes. Reserved from the arrow
    # counts, since the lanes themselves are placed once the boxes are.
    cross = [i for i, a in enumerate(arrows)
             if band[rank[a.src]] != band[rank[a.dst]]]
    chan_r = chan_l = None
    corridor = {}
    if cross:
        # Two bands are flush left, so the gap tracks of one can land on the
        # x of another's, and a cross arrow's vertical runs the corridor between
        # them. A band that would put a cross track within LANE / 2 of an
        # earlier band's moves right by the smallest whole number of units
        # that clears it (usually none).
        ends = [(band[rank[a.src]], track(slot[i][0]))
                for i, a in enumerate(arrows) if i in cross] + [
                (band[rank[a.dst]], track(slot[i][1]))
                for i, a in enumerate(arrows) if i in cross]
        shifts, placed = [], []
        for bi in range(bands):
            mine = [x for bb, x in ends if bb == bi]
            d = 0.0
            while any(abs(x + d - u) < LANE / 2.0 for x in mine
                      for u in placed):
                d += 1.0
            shifts.append(d)
            placed += [x + d for x in mine]
        for b in boxes:
            b.x += shifts[band[rank[b.name]]]
        left[:] = [c[0].x for c in cols]
        right[:] = [c[0].x + c[0].w for c in cols]
        xs_ = [b.x for b in boxes] + [b.x + b.w for b in boxes]
        for pair in slot:
            xs_ += [track(g_k) for g_k in pair if g_k]
        chan_r, chan_l = max(xs_) + DETOUR, min(xs_) - DETOUR
        runs = {}
        nr = nl = 0
        for i in cross:
            a = arrows[i]
            fwd = rank[a.dst] > rank[a.src]
            bs, bd = band[rank[a.src]], band[rank[a.dst]]
            xo, xi = track(slot[i][0]), track(slot[i][1])
            if fwd and bd == bs + 1:
                legs = [(bs, xo, xi)]
            elif fwd:
                xr = chan_r + nr * LANE
                nr += 1
                legs = [(bs, xo, xr), (bd - 1, xr, xi)]
            elif bd == bs - 1:
                legs = [(bd, xo, xi)]
            else:
                xl = chan_l - nl * LANE
                nl += 1
                legs = [(bs - 1, xo, xl), (bd, xl, xi)]
            corridor[i] = legs
            for k, (c, u, v) in enumerate(legs):
                runs.setdefault(c, []).append(((i, k), min(u, v), max(u, v), 0.0))
    n_below = [0] * bands
    n_above = [0] * bands
    for a in arrows:
        rs, rd = rank[a.src], rank[a.dst]
        if band[rs] == band[rd]:
            if rd > rs + 1:
                n_above[band[rs]] += 1
            elif rd < rs:
                n_below[band[rs]] += 1
    cross_y = {}
    cross_lane = {}
    next_top = 0.0
    for bi in range(bands):
        cols_b = [c for r, c in enumerate(cols) if band[r] == bi]
        heights = [sum(b.h for b in c) + VGAP * (len(c) - 1) for c in cols_b]
        hb = max(heights)
        centre = 0.0 if bi == 0 else next_top + hb / 2.0
        for c, hc in zip(cols_b, heights):
            y = centre - hc / 2.0
            for b in c:
                b.y = y
                y += b.h + VGAP
        if bi == bands - 1:
            break
        bottom = centre + hb / 2.0
        lo = bottom + (DETOUR + (n_below[bi] - 1) * LANE if n_below[bi] else 0.0)
        lanes_ = _lanes(runs.get(bi, []) if cross else [], LANE)
        cross_lane.update(lanes_)
        cross_y[bi] = lo + DETOUR
        last = cross_y[bi] + max(lanes_.values()) if lanes_ else lo
        next_top = max(last + DETOUR, bottom + 2 * DETOUR)
        if n_above[bi + 1]:
            next_top += DETOUR + (n_above[bi + 1] - 1) * LANE

    # The end stubs of each detour, before its lane is known: [(x, y)] from
    # the port to the foot of the vertical that reaches the lane.
    heads, tails, above, below = {}, {}, [], []
    for i, a in enumerate(arrows):
        s, d = by_name[a.src], by_name[a.dst]
        rs, rd = rank[a.src], rank[a.dst]
        if rd == rs + 1 or rd == rs:
            continue
        o, n_ = slot[i]
        if rd > rs:
            head = ([(s.cx + PORT_X, s.y)] if o is None else
                    [(s.x + s.w, s.cy - PORT), (track(o), s.cy - PORT)])
            tail = ([(d.cx - PORT_X, d.y)] if n_ is None else
                    [(track(n_), d.cy - PORT), (d.x, d.cy - PORT)])
            base = min(b.y for b in boxes if rs <= rank[b.name] <= rd)
            above.append((i, head[-1][0], tail[0][0], base - DETOUR))
        else:
            head = ([(s.cx - PORT_X, s.y + s.h)] if o is None else
                    [(s.x, s.cy + PORT), (track(o), s.cy + PORT)])
            tail = ([(d.cx + PORT_X, d.y + d.h)] if n_ is None else
                    [(track(n_), d.cy + PORT), (d.x + d.w, d.cy + PORT)])
            base = max(b.y + b.h for b in boxes if rd <= rank[b.name] <= rs)
            below.append((i, tail[0][0], head[-1][0], base + DETOUR))
        heads[i], tails[i] = head, tail
    lane = _lanes(above, -LANE)
    lane.update(_lanes(below, LANE))

    routes = []
    for i, a in enumerate(arrows):
        s, d = by_name[a.src], by_name[a.dst]
        rs, rd = rank[a.src], rank[a.dst]
        if i in corridor:
            routes.append(_cross_route(
                s, d, rd > rs, track(slot[i][0]), track(slot[i][1]),
                [cross_y[c] + cross_lane[(i, k)]
                 for k, (c, _u, _v) in enumerate(corridor[i])],
                corridor[i][0][2] if len(corridor[i]) == 2 else None))
            continue
        if rd == rs + 1:
            p0, p1 = (s.x + s.w, s.cy), (d.x, d.cy)
            if p0[1] == p1[1]:
                routes.append(Route([p0, p1], _tip(p0, p1), "mut"))
            else:
                c = ((p0[0] + p1[0]) / 2.0, p1[1])
                routes.append(Route([p0, c, p1], _tip(c, p1), "mut"))
            continue
        if rd == rs:
            xt = track(slot[i][0])
            y0, y1 = s.cy + 2 * PORT, d.cy - 2 * PORT
            pts = [(s.x + s.w, y0), (xt, y0), (xt, y1), (d.x + d.w, y1)]
            tone = "mut" if order[a.dst] > order[a.src] else "flg"
        else:
            y = lane[i]
            head, tail = heads[i], tails[i]
            pts = (head + [(head[-1][0], y), (tail[0][0], y)] + tail)
            tone = "mut" if rd > rs else "flg"
        routes.append(Route(pts, _tip(pts[-2], pts[-1]), tone))
    return routes


def _balance(cw, rows):
    """The cut of the columns (widths `cw`) into `rows` rows whose widest row is
    the narrowest: the greedy cut fills each row and leaves the remainder alone
    (4 + 1), this one evens them out (3 + 2). At most 8 columns, so every cut is
    tried; of equal ones the fuller upper rows win (3 + 2, not 2 + 3), so it is deterministic."""
    def widest(cuts):
        edges = (0,) + cuts + (len(cw),)
        return max(sum(cw[a:b]) + GAP * (b - a - 1)
                   for a, b in zip(edges, edges[1:]))
    best = min(itertools.combinations(range(1, len(cw)), rows - 1), key=lambda c: (widest(c), tuple(-i for i in c)))
    return set(best)


def _wrap_lr(boxes, arrows, by_name, rank):
    """A `row` too wide for the page, laid out lr in as many rows as it needs.

    The columns are cut greedily to a width budget; the drawing is then placed
    for real (`_layout_lr` with the cuts) and measured, since the tracks and
    channels the cross arrows need are only known then. Each pass that is still
    over MAX_BOX_W tightens the budget by the excess, down to one column per
    row. Returns `(routes, cuts)`: the drawing may still be wider than the page
    when one column alone is (the caller then falls back to `tb`)."""
    ncols = max(rank.values()) + 1
    cw = [max(b.w for b in boxes if rank[b.name] == r) for r in range(ncols)]
    floor = max(cw)
    limit = MAX_BOX_W - 2 * MARGIN
    while True:
        cuts, x = set(), None
        for r in range(ncols):
            if x is not None and x + GAP + cw[r] <= limit:
                x += GAP + cw[r]
            else:
                if x is not None:
                    cuts.add(r)
                x = cw[r]
        cuts = _balance(cw, len(cuts) + 1)
        routes = _layout_lr(boxes, arrows, by_name, rank, cuts)
        x0, _y0, x1, _y1 = _bounds(boxes, routes, [], None)
        width = (x1 - x0) + 2 * MARGIN
        if width <= MAX_BOX_W or limit <= floor:
            return routes, cuts
        limit = max(floor, limit - max(width - MAX_BOX_W, 1.0))


def _wrap(text, width, limit):
    """`text` as lines broken at runs of spaces (U+0020 only), each
    `width(line)` at most `limit` if a line can be: greedy, a word wider than
    `limit` stays whole on its own line. Everything but a broken run of
    spaces is kept byte for byte: a no-break space or a tab holds."""
    if limit is None or width(text) <= limit:
        return [text]
    parts = re.split(r"( +)", text)
    lines = [parts[0]]
    for gap, w in zip(parts[1::2], parts[2::2]):
        cand = lines[-1] + gap + w
        if width(cand) <= limit:
            lines[-1] = cand
        else:
            lines.append(w)
    return lines


def _fit_tb(boxes, limit):
    """Wrap each label and sublabel so its box is at most `limit` wide.

    Each is wrapped on its own, by the same greedy rule: a sublabel too wide
    for `limit` wraps too, instead of forcing its label one word per line to
    make room it can never give. A word wider than `limit` stays whole on its
    line — the text is never cut inside a word — and it holds the box that
    wide, so neither text is wrapped narrower than that word. `None` draws
    each on one line. The box grows LINE_H per extra line.
    """
    for b in boxes:
        lw = lambda t: box_width(t, "", b.decision)
        sw = lambda t: box_width("", t, b.decision)
        extra = len(b.lines) - 1 + len(b.sub_lines) - (1 if b.sub else 0)
        base = b.h - LINE_H * extra
        room = limit
        if limit is not None:
            room = max([limit] + [lw(w) for w in b.label.split(" ")]
                       + [sw(w) for w in b.sub.split(" ")])
        b.lines = _wrap(b.label, lw, room)
        b.sub_lines = _wrap(b.sub, sw, room) if b.sub else []
        b.w = max([lw(ln) for ln in b.lines] + [sw(sl) for sl in b.sub_lines])
        extra = len(b.lines) - 1 + len(b.sub_lines) - (1 if b.sub else 0)
        b.h = base + LINE_H * extra


def _place_tb(boxes):
    """One box per line, top to bottom in declaration order, centred on x=0."""
    y = 0.0
    for b in boxes:
        b.x, b.y = -b.w / 2.0, y
        y += b.h + TB_GAP


def _route_tb(boxes, arrows, by_name):
    """A `row` drawn top to bottom.

    Next box: a straight drop, bottom middle to top middle. Forward past a
    box: out of the right face below its middle, along its own lane RIGHT of
    every box it spans, into the right face above the target's middle. Back:
    the mirror on the LEFT, out above the middle and in below it, in `flg`.
    In-ports and out-ports never coincide, and `_lanes` gives each detour a
    lane of its own.
    """
    order = {b.name: i for i, b in enumerate(boxes)}
    right, left, ends = [], [], {}
    for k, a in enumerate(arrows):
        i, j = order[a.src], order[a.dst]
        s, d = by_name[a.src], by_name[a.dst]
        if j == i + 1:
            continue
        span = boxes[min(i, j):max(i, j) + 1]
        if j > i:
            p0, p1 = (s.x + s.w, s.cy + PORT), (d.x + d.w, d.cy - PORT)
            right.append((k, p0[1], p1[1],
                          max(b.x + b.w for b in span) + DETOUR))
        else:
            p0, p1 = (s.x, s.cy - PORT), (d.x, d.cy + PORT)
            left.append((k, p1[1], p0[1], min(b.x for b in span) - DETOUR))
        ends[k] = (p0, p1)
    lane = _lanes(right, LANE)
    lane.update(_lanes(left, -LANE))
    routes = []
    for k, a in enumerate(arrows):
        s, d = by_name[a.src], by_name[a.dst]
        if k not in ends:
            p0, p1 = (s.cx, s.y + s.h), (d.cx, d.y)
            routes.append(Route([p0, p1], _tip(p0, p1), "mut"))
            continue
        p0, p1 = ends[k]
        x = lane[k]
        pts = [p0, (x, p0[1]), (x, p1[1]), p1]
        routes.append(Route(pts, _tip(pts[2], p1),
                            "mut" if order[a.dst] > order[a.src] else "flg"))
    return routes


def _edge_point(box, tx, ty):
    """Where the segment from `box`'s centre toward (tx, ty) leaves the box."""
    dx, dy = tx - box.cx, ty - box.cy
    if dx == 0.0 and dy == 0.0:
        return box.cx, box.cy
    hw, hh = box.w / 2.0, box.h / 2.0
    t = min(hw / abs(dx) if dx else float("inf"),
            hh / abs(dy) if dy else float("inf"))
    return box.cx + dx * t, box.cy + dy * t


def _place_cycle(boxes):
    """Boxes evenly spaced on a ring whose RADIUS comes from the boxes.

    The quantifier is EVERY pair of boxes on the ring, not every adjacent
    pair. Adjacency is a property of the arrows, not of the picture: two boxes
    N/2 apart are drawn on the same canvas as two neighbours and collide the
    same way. Sizing off the neighbours alone is the bug this ring shipped
    with — at N == 4 the two boxes at angles 0 and pi have the SAME y, so they
    overlap by the full BOX_H and only `2R` keeps them apart, and `2R` had been
    derived from pairs that may both be narrow. Two long opposite labels were
    then drawn straight through each other, with `svg_text_findings` green:
    the checker compares a label to a label and a label to its own rect, never
    a rect to a rect.

    Per pair `(i, j)` the chord between the two centres is
    `2R sin(pi |i - j| / N)`, and two axis-aligned rectangles are disjoint as
    soon as EITHER axis separates them:

        |dx| >= (w_i + w_j) / 2 + GAP   or   |dy| >= BOX_H + GAP

    so a chord of at least `hypot((w_i + w_j) / 2 + GAP, BOX_H + GAP)` is
    enough whatever direction it points in: if both axes fell short, then
    `dx^2 + dy^2` would be below that hypotenuse squared, and the chord is
    exactly `hypot(dx, dy)`. Requiring the hypotenuse rather than the two
    projections is also what keeps the radius independent of WHERE on the ring
    a long label sits — the requirement reads only the two widths and `|i - j|`,
    both of which rotate with the labels.

    The max over all pairs is what makes the guarantee hold at once: the
    requirement per pair is monotone in R, so the largest of them satisfies
    every other. Never the last pair looked at.
    """
    n = len(boxes)
    radius = 0.0
    for i in range(n):
        for j in range(i + 1, n):
            chord = math.hypot((boxes[i].w + boxes[j].w) / 2.0 + GAP,
                               (boxes[i].h + boxes[j].h) / 2.0 + GAP)
            # `sin` of the half-angle between the two centres. Non-zero for
            # every i != j on a ring of n >= 2, so nothing divides by 0.
            spread = 2.0 * math.sin(math.pi * (j - i) / n)
            radius = max(radius, chord / spread)
    for k, b in enumerate(boxes):
        ang = -math.pi / 2.0 + 2.0 * math.pi * k / n
        b.x = radius * math.cos(ang) - b.w / 2.0
        b.y = radius * math.sin(ang) - b.h / 2.0
    return radius


def _route_cycle(boxes, arrows, by_name, radius):
    """Every declared arrow as a curve bowing OUT of the ring.

    The bow is what keeps the two arrows of a 2-box cycle apart: with the
    boxes opposite each other the midpoint of the chord IS the ring's centre,
    so "push away from the centre" has no direction. The fallback is the
    chord's left-hand normal, which flips with the arrow, so `A -> B` and
    `B -> A` bow to opposite sides instead of onto each other.
    """
    bow = max(24.0, radius * 0.28)
    order = {b.name: i for i, b in enumerate(boxes)}
    n = len(boxes)
    routes = []
    for a in arrows:
        s, d = by_name[a.src], by_name[a.dst]
        # WITH the ring (including the one that closes it, which is what a
        # cycle is for) or AGAINST it. Only the second is flagged.
        tone = "mut" if order[a.dst] == (order[a.src] + 1) % n else "flg"
        mx, my = (s.cx + d.cx) / 2.0, (s.cy + d.cy) / 2.0
        length = math.hypot(mx, my)
        if length > 1e-9:
            ux, uy = mx / length, my / length
        else:
            dx, dy = d.cx - s.cx, d.cy - s.cy
            chord = math.hypot(dx, dy) or 1.0
            ux, uy = -dy / chord, dx / chord
        c = (mx + ux * bow, my + uy * bow)
        p0 = _edge_point(s, c[0], c[1])
        p1 = _edge_point(d, c[0], c[1])
        routes.append(Route([p0, c, p1], _tip(c, p1), tone))
    return routes


# --- the `tree` shape --------------------------------------------------------
# Top-down placement is the Buchheim-Walker algorithm: C. Buchheim, M. Juenger,
# S. Leipert, "Improving Walker's Algorithm to Run in Linear Time", Graph
# Drawing 2002 (LNCS 2528), itself Reingold-Tilford (1981) with Walker's (1990)
# n-ary extension. A parent is centred over its first and last child, and each
# subtree is pushed against its left neighbour only as far as the two CONTOURS
# force, so subtrees are as compact as the tree allows; the threads and the
# `change`/`shift` bookkeeping keep it linear. The one departure from the
# paper's unit-width nodes: a node has a FOOTPRINT, `l` left and `r` right of
# its middle (the box's half-width, and to the right the badge pill too), and
# two neighbours are kept `l + r + SIB_GAP` apart instead of one `distance`.
class _TN(object):
    __slots__ = ("box", "parent", "children", "i", "mod", "shift", "change",
                 "thread", "ancestor", "x", "l", "r")

    def __init__(self, box, parent, i):
        self.box, self.parent, self.i = box, parent, i
        self.children = []
        self.mod = self.shift = self.change = 0.0
        self.thread, self.ancestor, self.x = None, self, 0.0
        self.l = box.w / 2.0
        self.r = max(box.w / 2.0, BADGE_INSET + badge_w(box.badge)
                     if box.badge else 0.0)

    def left(self):
        return self.thread or (self.children[0] if self.children else None)

    def right(self):
        return self.thread or (self.children[-1] if self.children else None)

    def lbrother(self):
        return self.parent.children[self.i - 1] if self.parent and self.i else None

    def lmost(self):
        return self.parent.children[0] if self.parent and self.i else None


def _sep(a, b):
    return a.r + b.l + SIB_GAP


def _tree_nodes(boxes, arrows):
    """The root `_TN`, the children of each box taken in arrow order."""
    by_name = {b.name: b for b in boxes}
    kids = {b.name: [] for b in boxes}
    has_parent = set()
    for a in arrows:
        kids[a.src].append(a.dst)
        has_parent.add(a.dst)
    root = [b for b in boxes if b.name not in has_parent][0]

    def make(box, parent, i):
        node = _TN(box, parent, i)
        node.children = [make(by_name[k], node, j)
                         for j, k in enumerate(kids[box.name])]
        return node
    return make(root, None, 0)


def _firstwalk(v):
    if not v.children:
        w = v.lbrother()
        v.x = w.x + _sep(w, v) if w else 0.0
        return
    default = v.children[0]
    for w in v.children:
        _firstwalk(w)
        default = _apportion(w, default)
    _execute_shifts(v)
    mid = (v.children[0].x + v.children[-1].x) / 2.0
    w = v.lbrother()
    if w:
        v.x = w.x + _sep(w, v)
        v.mod = v.x - mid
    else:
        v.x = mid


def _apportion(v, default):
    w = v.lbrother()
    if w is None:
        return default
    vir = vor = v
    vil, vol = w, v.lmost()
    sir = sor = v.mod
    sil, sol = vil.mod, vol.mod
    while vil.right() and vir.left():
        vil, vir = vil.right(), vir.left()
        vol, vor = vol.left(), vor.right()
        vor.ancestor = v
        shift = (vil.x + sil) - (vir.x + sir) + _sep(vil, vir)
        if shift > 0:
            a = vil.ancestor if vil.ancestor.parent is v.parent else default
            n = v.i - a.i
            v.change -= shift / n
            v.shift += shift
            a.change += shift / n
            v.x += shift
            v.mod += shift
            sir += shift
            sor += shift
        sil += vil.mod
        sir += vir.mod
        sol += vol.mod
        sor += vor.mod
    if vil.right() and not vor.right():
        vor.thread = vil.right()
        vor.mod += sil - sor
    else:
        if vir.left() and not vol.left():
            vol.thread = vir.left()
            vol.mod += sir - sol
        default = v
    return default


def _execute_shifts(v):
    shift = change = 0.0
    for w in reversed(v.children):
        w.x += shift
        w.mod += shift
        change += w.change
        shift += w.shift + change


def _secondwalk(v, m, depth, out):
    out.append((v, v.x + m, depth))
    for w in v.children:
        _secondwalk(w, m + v.mod, depth + 1, out)


def _place_pill(b, x, limit=None):
    """The badge pill of `b`, its left edge at `x`, straddling the top edge.

    The bottom edge is always 6 below the box's top edge; a badge wrapped to
    several lines (`limit`, the pill's widest width; the outline's) grows UP,
    so it never reaches the box's own label."""
    if b.badge:
        b.badge_lines = _wrap(
            b.badge, lambda t: text_width(t, SUB_FS) + 2 * BADGE_PAD, limit)
        h = BADGE_H + (len(b.badge_lines) - 1) * BADGE_LINE
        w = max(text_width(t, SUB_FS) for t in b.badge_lines) + 2 * BADGE_PAD
        b.pill = (x, b.y + (BADGE_H - BADGE_UP) - h, w, h)


def _place_marks(b):
    """The pill's text sits where the box's label would; a lock moves the
    label left and takes the right-hand strip."""
    if b.lock:
        b.text_dx = -LOCK_RESERVE / 2.0
        b.lock_at = (b.x + b.w - 12.0 - LOCK_W, b.cy - LOCK_H / 2.0 + 1.0)


def _route_top_down(arrows, by_name):
    """One route per parent -> child arrow, in arrow order: down out of the
    parent's bottom middle, along a run BUS below it, down into the child's top
    middle. Straight when the two middles line up. The run is between two
    levels, where no box is, and each edge arrives at its child's middle, left
    of the badge pill."""
    routes = []
    for ar in arrows:
        a, b = by_name[ar.src], by_name[ar.dst]
        if abs(a.cx - b.cx) < 1e-9:
            pts = [(a.cx, a.y + a.h), (b.cx, b.y)]
        else:
            yb = a.y + a.h + BUS
            pts = [(a.cx, a.y + a.h), (a.cx, yb), (b.cx, yb), (b.cx, b.y)]
        routes.append(Route(pts, _tip(pts[-2], pts[-1]), "mut"))
    return routes


def _layout_tree(boxes, arrows):
    """Top-down: Buchheim-Walker, then y by depth. Returns the routes."""
    root = _tree_nodes(boxes, arrows)
    _firstwalk(root)
    placed = []
    _secondwalk(root, 0.0, 0, placed)
    left = min(x - v.l for v, x, _d in placed)
    h = boxes[0].h
    for v, x, depth in placed:
        b = v.box
        b.x = x - left - b.w / 2.0
        b.y = depth * (h + LEVEL_GAP)
        _place_pill(b, b.cx + BADGE_INSET)
        _place_marks(b)
    return _route_top_down(arrows, {b.name: b for b in boxes})


def _layout_outline(boxes, arrows):
    """The stacked drawing: one box per row in preorder, each level INDENT to
    the right of its parent, an edge leaving its parent's left strip by a
    spine and turning into the child's left face. It is what a tree becomes
    when the top-down drawing is wider than the page (or a phone): its width is
    the depth times INDENT plus one box, not the sum of the widest level."""
    root = _tree_nodes(boxes, arrows)
    order = []

    def walk(v, d):
        order.append((v, d))
        for w in v.children:
            walk(w, d + 1)
    walk(root, 0)
    deepest = max(d for _v, d in order)
    # The room left for a label after the indent, never under 120: a deep chain
    # is wrapped to a readable box and drawn wider than NARROW_W instead of a
    # word a line.
    room = max(120.0, NARROW_W - 2 * MARGIN - deepest * INDENT)
    # A locked box grows by LOCK_RESERVE after wrapping, so its label is
    # wrapped that much narrower; a badge pill starts BADGE_OUT right of the box
    # and is wrapped to end inside the same room.
    _fit_tb([v.box for v, _d in order],
            room - (LOCK_RESERVE if any(v.box.lock for v, _d in order) else 0.0))
    y = 0.0
    for i, (v, d) in enumerate(order):
        b = v.box
        if b.lock:
            b.w += LOCK_RESERVE
        b.x = d * INDENT
        if b.badge:
            # Placed at the row's own y first to learn how tall the pill is,
            # then the row is moved down by what the pill grows above it.
            b.y = 0.0
            _place_pill(b, b.x + BADGE_OUT, room - BADGE_OUT)
            up = (len(b.badge_lines) - 1) * BADGE_LINE
        else:
            up = 0.0
        if i:
            y += OUT_GAP + up
        b.y = y
        _place_pill(b, b.x + BADGE_OUT, room - BADGE_OUT)
        y += b.h
        _place_marks(b)
    routes = []
    by_name = {b.name: b for b in boxes}
    for ar in arrows:
        a, b = by_name[ar.src], by_name[ar.dst]
        sx = a.x + SPINE
        # Four points, the second collinear: a 3-point route is a quadratic to
        # `diagram_svg._path`, and this elbow is a right angle.
        pts = [(sx, a.y + a.h), (sx, (a.y + a.h + b.cy) / 2.0),
               (sx, b.cy), (b.x, b.cy)]
        routes.append(Route(pts, _tip(pts[-2], pts[-1]), "mut"))
    return routes


def _bounds(boxes, routes, titles, divider):
    xs, ys = [], []
    for b in boxes:
        xs += [b.x, b.x + b.w]
        ys += [b.y, b.y + b.h]
        if b.pill:
            xs += [b.pill[0], b.pill[0] + b.pill[2]]
            ys += [b.pill[1], b.pill[1] + b.pill[3]]
    for r in routes:
        for px, py in r.points:
            xs.append(px)
            ys.append(py)
    for text, tx, ty in titles:
        xs += [tx, tx + text_width(text, TITLE_FS)]
        # A title's glyph box, the way check_artifact measures one: the ascent
        # above the baseline and the descent below it.
        ys += [ty - 0.8 * TITLE_FS, ty + 0.25 * TITLE_FS]
    if divider:
        xs += [divider[0], divider[2]]
        ys.append(divider[1])
    if not xs:                                     # unreachable: 0 boxes is
        xs, ys = [0.0], [0.0]                      # refused at the fence
    return min(xs), min(ys), max(xs), max(ys)


def _shift(lay, dx, dy):
    """Move a placed body by (dx, dy), in place: boxes, pills, locks, routes."""
    for b in lay.boxes:
        b.x, b.y = b.x + dx, b.y + dy
        if b.pill:
            b.pill = (b.pill[0] + dx, b.pill[1] + dy, b.pill[2], b.pill[3])
        if b.lock_at:
            b.lock_at = (b.lock_at[0] + dx, b.lock_at[1] + dy)
    for r in lay.routes:
        r.points = [(x + dx, y + dy) for x, y in r.points]


def _layout_compare(panels, mode):
    """Two framed panels, side by side (`side`) or A above B (`stack`, and
    `narrow`, which also takes each body's own 390 px twin).

    A panel is its title, its body (a tree or a row, laid out by that shape's
    own layout and only moved), and its outcome, top to bottom. Both frames get
    the same width, the widest content of either. Side by side they also get
    the same height and the same three baselines: titles at one y, bodies
    top-aligned, the outcome's first line at one y under the taller body.
    Stacked, each frame is as tall as its own content."""
    bodies = []
    for p in panels:
        main, twin = drawings(p.kind, p.boxes, p.arrows, [])
        lay = main
        if twin is not None and (mode in ("narrow", "side-narrow")
                                 or main.view[2] - 2 * MARGIN
                                 > MAX_BOX_W - 2 * (PANEL_PAD + MARGIN)):
            lay = twin
        bodies.append(lay)
    cw = [lay.view[2] - 2 * MARGIN for lay in bodies]
    ch = [lay.view[3] - 2 * MARGIN for lay in bodies]
    inner = max([MIN_PANEL_W] + cw + [text_width(p.title, FS) for p in panels]
                + [_widest_word(p.outcome) for p in panels])
    fw = inner + 2 * PANEL_PAD
    ow = lambda t: text_width(t, FS)
    out_lines = [_wrap(p.outcome, ow, inner) for p in panels]
    title_h = PANEL_PAD + FS
    side = mode in ("side", "side-narrow")
    y = 0.0
    frames = []
    for i, p in enumerate(panels):
        x = i * (fw + PANEL_GAP) if side else 0.0
        top = 0.0 if side else y
        body_h = max(ch) if side else ch[i]
        n_out = max(len(o) for o in out_lines) if side else len(out_lines[i])
        by = top + title_h + PANEL_BODY_GAP
        oy = by + body_h + PANEL_BODY_GAP
        p.title_at = (x + PANEL_PAD, top + PANEL_PAD + 0.8 * FS)
        _shift(bodies[i], x + PANEL_PAD + (inner - cw[i]) / 2.0
               - (bodies[i].view[0] + MARGIN),
               by - (bodies[i].view[1] + MARGIN))
        p.outcome_lines = [(t, x + PANEL_PAD, oy + 0.8 * FS + k * LINE_H)
                           for k, t in enumerate(out_lines[i])]
        h = oy + 0.8 * FS + (n_out - 1) * LINE_H + 0.25 * FS + PANEL_PAD - top
        p.frame = (x, top, fw, h)
        frames.append(p.frame)
        y = top + h + PANEL_GAP
    x1 = max(f[0] + f[2] for f in frames)
    y1 = max(f[1] + f[3] for f in frames)
    boxes = [b for lay in bodies for b in lay.boxes]
    routes = [r for lay in bodies for r in lay.routes]
    view = (-MARGIN, -MARGIN, x1 + 2 * MARGIN, y1 + 2 * MARGIN)
    return Layout("compare", boxes, routes, [], None, view,
                  "side" if side else "stack", panels)


def layout(shape, boxes, arrows, titles, direction=None):
    """A placed `Layout`. Everything `diagram_svg` draws is decided here.

    The two `ValueError`s are the caller's to prevent, and the emitter does:
    it holds the FENCE's line, which is the line an author fixes for "this
    diagram has no boxes". Kept here so a direct call cannot divide by a ring
    of one box — `sin(pi/1)` is 1.2e-16, and the radius it yields is 1e17.
    Same division of labour as `chart_svg.svg()`.
    """
    shape = SHAPE_ALIASES[shape]
    if shape == "compare":
        # The panels carry their own boxes and arrows, and are placed on
        # copies: `drawings()` lays a compare out up to three times.
        panels = [copy.copy(p) for p in titles]
        return _layout_compare(panels, direction or "side")
    if not boxes:
        raise ValueError("a diagram needs at least one box")
    if shape == "cycle" and len(boxes) < 2:
        raise ValueError("a cycle needs at least two boxes")
    # Placed on COPIES: `drawings()` lays the same boxes out twice, and a
    # second placement must not move the boxes of the first.
    boxes = [copy.copy(b) for b in boxes]
    h = SUB_BOX_H if any(b.sub for b in boxes) else BOX_H
    for b in boxes:
        b.h = h
    by_name = {b.name: b for b in boxes}
    placed_titles, divider = [], None

    if shape == "row" and direction == "tb":
        # A `tb` drawing is the one a 390 px screen shows: at most NARROW_W
        # wide, by wrapping labels, narrower each pass by what is still over.
        # Stops when it fits or wrapping no longer narrows the widest box
        # (one word wider than the room left): drawn then, never cut.
        limit, prev = None, None
        while True:
            _fit_tb(boxes, limit)
            _place_tb(boxes)
            routes = _route_tb(boxes, arrows, by_name)
            x0, _y0, x1, _y1 = _bounds(boxes, routes, [], None)
            over = (x1 - x0) + 2 * MARGIN - NARROW_W
            widest = max(b.w for b in boxes)
            if over <= 1e-9 or widest == prev:
                break
            prev, limit = widest, widest - over
    elif shape == "tree":
        # The outline wraps its labels (`_fit_tb`), which sets each box's own
        # height: `outline` is the one direction that does not use `h` alone.
        if direction == "outline":
            routes = _layout_outline(boxes, arrows)
        else:
            routes = _layout_tree(boxes, arrows)
            direction = "top-down"
    elif shape == "row":
        rank = _ranks(boxes, arrows)
        if direction == "wrap":
            routes, _cuts = _wrap_lr(boxes, arrows, by_name, rank)
        else:
            routes = _layout_lr(boxes, arrows, by_name, rank)
        direction = "lr"
    elif shape == "before-after":
        lanes = [[b for b in boxes if b.lane == 0],
                 [b for b in boxes if b.lane == 1]]
        routes = []
        widths = []
        for k, run in enumerate(lanes):
            y = k * (h + LANE_V)
            widths.append(_place_run(run, y))
            # The lane being LEFT is quieter than the one being arrived at.
            for b in run:
                b.tone = "mut" if k == 0 else "acc"
            placed_titles.append((titles[k], 0.0, y - TITLE_DROP))
            routes += _route_row(run, [a for a in arrows
                                       if by_name[a.src].lane == k], by_name)
        # The rule spans the WIDEST thing on the canvas, which may be a lane
        # title rather than a lane: a short "Antes" over two narrow boxes and a
        # long "Después de la corrección" over one is a real page, and a rule
        # measured off the boxes alone would stop short of the title above it.
        width = max(widths + [text_width(t, TITLE_FS) for t in titles])
        divider = (0.0, h + LANE_V / 2.0, width)
    else:
        radius = _place_cycle(boxes)
        routes = _route_cycle(boxes, arrows, by_name, radius)

    x0, y0, x1, y1 = _bounds(boxes, routes, placed_titles, divider)
    view = (x0 - MARGIN, y0 - MARGIN,
            (x1 - x0) + 2 * MARGIN, (y1 - y0) + 2 * MARGIN)
    return Layout(shape, boxes, routes, placed_titles, divider, view,
                  direction if shape in ("row", "tree") else None)


def drawings(shape, boxes, arrows, titles, direction=None):
    """`(main, narrow)`: the drawing a page shows, and its twin for 390 px.

    A `row` with no `direction` is `lr` when that drawing fits the page, `lr`
    wrapped into rows when it does not, and `tb` when even one column per row
    is over the page. `narrow` is a `tb` drawing when the main one is an `lr`
    wider than NARROW_W, so small screens reflow instead of shrinking the text
    under 11 px; None otherwise (every other shape, a forced `tb`, a row
    narrow enough already).
    """
    if SHAPE_ALIASES[shape] == "compare":
        # Side by side when that fits the page's 720, first with the bodies'
        # main drawings and then with their narrow ones; otherwise A above B. The
        # 390 px twin is A above B with each body's own narrow drawing, shown
        # only when it is the narrower of the two, like a tree's.
        main = layout(shape, boxes, arrows, titles, "side")
        if main.view[2] > MAX_BOX_W:
            # Side by side is the goal: before stacking, try it with each
            # body's narrow drawing (a tree's outline, a row's tb).
            main = layout(shape, boxes, arrows, titles, "side-narrow")
        if main.view[2] > MAX_BOX_W:
            main = layout(shape, boxes, arrows, titles, "stack")
        if main.view[2] > NARROW_W:
            twin = layout(shape, boxes, arrows, titles, "narrow")
            return main, (twin if twin.view[2] < main.view[2] else None)
        return main, None
    main = layout(shape, boxes, arrows, titles, direction)
    if SHAPE_ALIASES[shape] == "tree":
        # The same rule as a `row`, with the outline for `tb`: the top-down
        # drawing when it fits the page, the outline when it does not, and the
        # outline as a twin for 390 px when the top-down one is wider than a
        # phone's column keeps readable.
        if main.view[2] > MAX_BOX_W:
            return layout(shape, boxes, arrows, titles, "outline"), None
        if main.view[2] > NARROW_W:
            # Only when the twin is the narrower of the two: a phone shows the
            # one that scales up, and a wrapped outline can come out wider
            # than a top-down tree that is only just over NARROW_W.
            twin = layout(shape, boxes, arrows, titles, "outline")
            return main, (twin if twin.view[2] < main.view[2] else None)
        return main, None
    if SHAPE_ALIASES[shape] != "row":
        return main, None
    if direction is None and main.view[2] > MAX_BOX_W:
        # Too wide for one row: rows of columns, each left to right. `tb`
        # only when even one column per row is over the page.
        wrapped = layout(shape, boxes, arrows, titles, "wrap")
        main = (wrapped if wrapped.view[2] <= MAX_BOX_W
                else layout(shape, boxes, arrows, titles, "tb"))
    if main.dir == "lr" and main.view[2] > NARROW_W:
        return main, layout(shape, boxes, arrows, titles, "tb")
    return main, None


def one_row(shape, boxes, arrows, titles, direction=None):
    """The `lr` drawing of a `row` that `drawings()` wrapped although the
    widest column holds it (over MAX_BOX_W, at most COL_MAX); None otherwise.
    A forced `direction` is the author's and gets no alternative."""
    if SHAPE_ALIASES[shape] != "row" or direction is not None:
        return None
    lay = layout(shape, boxes, arrows, titles, None)
    return (lay if lay.dir == "lr" and MAX_BOX_W < lay.view[2] <= COL_MAX
            else None)


def build(shape, rows):
    """`parse_body` then `layout`. The one entry point `diagram_svg` calls."""
    boxes, arrows, titles = parse_body(rows, shape)
    return layout(shape, boxes, arrows, titles)
