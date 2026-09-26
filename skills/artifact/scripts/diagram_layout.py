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
has no exact table, so `text_width` is the LARGER of two estimates:

  * `chart_svg._text_width` — the generous 0.62 em per character the chart
    legend already uses (shared, not forked), with an East-Asian Wide or
    Fullwidth character counted twice (1.24 em: those glyphs are a full em);
  * `check_artifact.svg_text_width` — the checker's own proportional table.

The second term is what makes the box never narrower than the checker
measures its label (`MMMM` is 0.85 em there), and the first is what keeps it
generous against the real font. It counts CHARACTERS, never bytes: `señor` is
6 bytes and 5 characters.

Direction (`row` only)
----------------------
A `row` is ranked in declaration order (`_ranks`): each box one past the
previous one, or further when a box pointing FORWARD at it (declared earlier)
is further on. Two consecutive boxes that one box points at share a rank — a
branch, stacked in one column; nothing else is stacked.
`lr` places ranks left to right and is the default when that drawing fits the
page (`MAX_BOX_W`); otherwise `tb`, one box per line in declaration order.
A wide `lr` drawing also gets a `tb` twin for narrow screens (`drawings()`):
the kit stretches a figure to its column, and a 700-unit flow in a 294 px
column draws 13-unit text at 5 px.

Everything is refused, or laid out. Nothing is silently clipped.
"""

import copy
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

# --- the shape vocabulary ----------------------------------------------------
# `pipeline` is a spelling of `row`, not a fourth shape: the corpus writes both
# words for the same picture. Resolved once, here, so nothing downstream carries
# two names for one layout.
SHAPE_ALIASES = {"row": "row", "pipeline": "row",
                 "before-after": "before-after", "cycle": "cycle"}
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
# root): 13-unit labels at 15.6 px, under the kit's 17 px body. Without it the
# kit's `figure svg { width: 100% }` blew a short row up to twice body size.
MAX_SCALE = 1.2
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
TRACK0 = 14.0          # a gap track's distance from the face it serves: more
                       # than an arrowhead (HEAD_L 9), so a head fits its stub
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
    """The label's rendered width in viewBox units: never below the checker's."""
    wide = "".join(ch for ch in label
                   if unicodedata.east_asian_width(ch) in ("W", "F"))
    return max(_text_width(label + wide, float(size)),
               svg_text_width(label, float(size)))


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
    __slots__ = ("name", "label", "sub", "decision", "line", "lane", "w", "h",
                 "x", "y", "tone", "lines")

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


class Layout(object):
    __slots__ = ("shape", "boxes", "routes", "titles", "divider", "view", "dir")

    def __init__(self, shape, boxes, routes, titles, divider, view, dir=None):
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
    boxes, arrows, titles = [], [], []
    by_name = {}
    seen_arrow = set()
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

        if "->" in line:
            raise SpecSyntaxError(
                n, "%r is not an arrow — one arrow per line, `A -> B`, and "
                   "both names are box names (letters, digits, `_`, `-`); a "
                   "chain is written as one line per hop" % line)
        raise SpecSyntaxError(
            n, "%r is neither a box nor an arrow — a box is `name: Label`, an "
               "arrow is `A -> B`%s" % (line, ", and a lane is `lane Title`"
                                        if shape == "before-after" else ""))

    _check_refs(boxes, arrows, by_name)
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


def _layout_lr(boxes, arrows, by_name, rank):
    """A `row` left to right: ranks as columns, then one route per arrow.

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
    """
    cols = []
    for b in boxes:
        if rank[b.name] == len(cols):
            cols.append([])
        cols[rank[b.name]].append(b)
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
        if rd == rs + 1:
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
        cw = max(b.w for b in col)
        y = -(sum(b.h for b in col) + VGAP * (len(col) - 1)) / 2.0
        for b in col:
            b.w = cw
            b.x, b.y = x, y
            y += b.h + VGAP
        n = count.get((r, 0), 0) + count.get((r, 1), 0)
        x += cw + max(GAP, 2 * TRACK0 + (n - 1) * LANE if n else 0.0)
    left = [c[0].x for c in cols]
    right = [c[0].x + c[0].w for c in cols]

    def track(g_k):
        (g, half), k = g_k
        if half == 0:
            return right[g] + TRACK0 + k * LANE
        return left[g + 1] - TRACK0 - k * LANE

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


def _fit_tb(boxes, limit):
    """Wrap each label so its box is at most `limit` wide, at spaces only.

    A word wider than `limit` stays whole on its line: the label is never cut
    inside a word, and a box is never narrower than its widest line. `None`
    draws every label on one line. The box grows LINE_H per extra line.
    """
    for b in boxes:
        words = b.label.split()
        lines = [b.label]
        if limit is not None and box_width(b.label, b.sub, b.decision) > limit:
            lines = [words[0]]
            for w in words[1:]:
                cand = lines[-1] + " " + w
                if box_width(cand, b.sub, b.decision) <= limit:
                    lines[-1] = cand
                else:
                    lines.append(w)
        base = b.h - LINE_H * (len(b.lines) - 1)
        b.lines = lines
        b.w = max(box_width(ln, b.sub, b.decision) for ln in lines)
        b.h = base + LINE_H * (len(lines) - 1)


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


def _bounds(boxes, routes, titles, divider):
    xs, ys = [], []
    for b in boxes:
        xs += [b.x, b.x + b.w]
        ys += [b.y, b.y + b.h]
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


def layout(shape, boxes, arrows, titles, direction=None):
    """A placed `Layout`. Everything `diagram_svg` draws is decided here.

    The two `ValueError`s are the caller's to prevent, and the emitter does:
    it holds the FENCE's line, which is the line an author fixes for "this
    diagram has no boxes". Kept here so a direct call cannot divide by a ring
    of one box — `sin(pi/1)` is 1.2e-16, and the radius it yields is 1e17.
    Same division of labour as `chart_svg.svg()`.
    """
    shape = SHAPE_ALIASES[shape]
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
    elif shape == "row":
        rank = _ranks(boxes, arrows)
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
                  direction if shape == "row" else None)


def drawings(shape, boxes, arrows, titles, direction=None):
    """`(main, narrow)`: the drawing a page shows, and its twin for 390 px.

    A `row` with no `direction` is `lr` when that drawing fits the page and
    `tb` otherwise. `narrow` is a `tb` drawing when the main one is an `lr`
    wider than NARROW_W, so small screens reflow instead of shrinking the text
    under 11 px; None otherwise (every other shape, a forced `tb`, a row
    narrow enough already).
    """
    main = layout(shape, boxes, arrows, titles, direction)
    if SHAPE_ALIASES[shape] != "row":
        return main, None
    if direction is None and main.view[2] > MAX_BOX_W:
        main = layout(shape, boxes, arrows, titles, "tb")
    if main.dir == "lr" and main.view[2] > NARROW_W:
        return main, layout(shape, boxes, arrows, titles, "tb")
    return main, None


def build(shape, rows):
    """`parse_body` then `layout`. The one entry point `diagram_svg` calls."""
    boxes, arrows, titles = parse_body(rows, shape)
    return layout(shape, boxes, arrows, titles)
