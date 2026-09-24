#!/usr/bin/env python3
"""The `::: diagram` block: the body grammar, the layout, and the SVG it draws.

Both halves of Phase 6 in one file, because they are one claim: a diagram
either refuses its body with a line the author can find, or lays out boxes
whose text is inside them. There is no third outcome, and the third outcome —
a diagram that renders with its label past the box edge and every gate green —
is the one the prior-art note names as the reason a layout engine exists at
all (`.context/research/2026-09-23-deterministic-diagrams-prior-art.md`, the
"hand-rolled stdlib grid/flow layout" row).

Six groups:

  THE METRIC — the monospace column table. Characters and never bytes, wide
  characters at two columns, and the one inequality everything else rests on:
  `columns(s) >= len(s)`, so this module's estimate is never below
  `check_artifact.svg_text_width`'s monospace branch, whatever the label holds.

  THE GRAMMAR — every malformed line refused at the line INSIDE the fence with
  `SpecSyntaxError`, and the three fence-level refusals (no shape, unknown
  shape, empty body) at the fence's own line with `SpecBuildError`. Same split
  `chart` keeps: the author edits a row for one and the fence for the other.

  THE LAYOUT'S BOUNDARIES — zero boxes, one box, one box and no arrows; the
  longest label first against last; a one-character label; an empty one; a
  multi-byte one; a label wider than the page. Two lanes of unequal length and
  one empty. A cycle of one, of two, and one whose boxes outgrow the ring. The
  arrow router at both ends: zero gap between adjacent boxes, and a backward
  arrow in a row. Each asserted to do something STATED, never to "not crash".

  THE svg-text CONTRACT — 0 warnings from `check_artifact.svg_text_findings`
  on every shape and on a battery of hostile labels, MEASURED by calling the
  real checker rather than looked at. Plus the margin the sizing actually has,
  so "how far off can the table be" has a number rather than a hope.

  COLOUR — `acc`/`flg`/`mut` and `currentColor` only, zero literal hex in the
  emitted pages and in the two sources.

  SAFETY AND DETERMINISM — a hostile label cannot leave its attribute or open
  an element, and the same spec built twice is byte-identical, in one process
  and across processes with a different hash seed.

Stdlib only, no runner: `python3 test_diagram.py`, prints OK, exits 0.
"""
import html as _html
import math
import os
import re
import shutil
import subprocess
import sys
import tempfile
import xml.dom.minidom

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

import check_artifact                               # noqa: E402
import diagram_layout as dl                         # noqa: E402
import diagram_svg as ds                            # noqa: E402
from spec_build import SpecBuildError, build        # noqa: E402
from spec_parser import SpecSyntaxError             # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")
CHECK = os.path.join(SCRIPTS, "check-artifact.sh")
FIXTURE = os.path.join(HERE, "fixtures", "diagram-sample.spec.md")
TOKENS = os.path.join(SKILL, "assets", "artifact-kit", "tokens.css")

failures = []
BUILT = []


def fail(msg):
    failures.append(msg)
    print("FAIL: " + msg)


def ok(msg):
    print("  ok: " + msg)


def check(label, cond, detail=""):
    if cond:
        ok(label)
    else:
        fail("%s%s" % (label, (": " + detail) if detail else ""))


def holds(label, spec, *needles):
    """Build `spec`; assert every needle appears in the output verbatim."""
    try:
        html = build(spec)
    except (SpecSyntaxError, SpecBuildError) as exc:
        fail("%s: refused a valid spec (line %d: %s)"
             % (label, exc.line, exc.message))
        return ""
    BUILT.append((label, html))
    missing = [n for n in needles if n not in html]
    check(label, not missing, "missing %r in:\n%s" % (missing, html))
    return html


def rejects(label, spec, line, fragment, kind=None):
    """Assert `spec` is refused AT `line`, with `fragment` in the message."""
    try:
        html = build(spec)
    except (SpecSyntaxError, SpecBuildError) as exc:
        got = type(exc).__name__
        want = kind.__name__ if kind else got
        check(label, exc.line == line and fragment in exc.message
              and got == want,
              "raised %s at line %d (%s), wanted %s at line %d with %r"
              % (got, exc.line, exc.message, want, line, fragment))
        return
    BUILT.append((label, html))
    fail("%s: built a spec that should have been refused" % label)


def fence(shape, *body):
    return "::: diagram {shape=%s}\n%s\n:::" % (shape, "\n".join(body))


def lay(shape, *body):
    """A placed `Layout` straight from the layout module, no markup."""
    rows = [(i + 2, ln) for i, ln in enumerate(body)]
    return dl.build(shape, rows)


def svg_of(html):
    m = re.search(r"<svg\b.*?</svg>", html, re.S)
    return m.group(0) if m else ""


def rects(svg):
    return re.findall(r'<rect\b[^>]*>', svg)


def fnum(tag, attr):
    m = re.search(r'\b%s="([-\d.]+)"' % attr, tag)
    return float(m.group(1)) if m else None


def findings(html):
    """The REAL `svg-text` findings for a fragment, from check_artifact."""
    return check_artifact.svg_text_findings(html)


def by_name(layout):
    return {b.name: b for b in layout.boxes}


def worst_pair(layout):
    """The tightest pair of RECTANGLES on a layout: `(clearance, which)`.

    Two axis-aligned boxes are disjoint when EITHER axis separates them, so a
    pair's clearance is `max(x-gap, y-gap)` and the layout's is the min of
    that over EVERY pair — every pair, because two boxes half a ring apart are
    drawn on the same canvas as two neighbours and collide the same way. A
    centre-to-centre distance is not this number: at N == 4 the boxes at
    angles 0 and pi have identical `cy`, and a metric that compares centre
    distance to half the widths calls them clear while the browser draws one
    through the other.
    """
    bs = layout.boxes
    out = None
    for i in range(len(bs)):
        for j in range(i + 1, len(bs)):
            a, b = bs[i], bs[j]
            gap = max(abs(a.cx - b.cx) - (a.w + b.w) / 2.0,
                      abs(a.cy - b.cy) - (a.h + b.h) / 2.0)
            if out is None or gap < out[0]:
                out = (gap, "%s/%s" % (a.name, b.name))
    return out if out else (float("inf"), "")


tmp = tempfile.mkdtemp(prefix="diagram-spec-")
try:
    print("== the metric: columns, never bytes ==")
    # The inequality everything else rests on. `check_artifact.svg_text_width`
    # is `0.6 * size * len(label)` on the monospace branch; if `columns()` ever
    # went below `len()`, a box would be sized smaller than the checker
    # measures the label it holds, and the whole phase would rest on luck.
    hostile = ["", "x", "abc", "señor", "日本語", "ＡＢ", "éclair",
               "🙂 ok", "AV.,;iii", "M" * 40, "—em dash—", "a​b"]
    below = [s for s in hostile if dl.columns(s) < len(s)]
    check("columns(s) >= len(s) for every label shape (%d probed)"
          % len(hostile), not below, "below len(): %r" % below)
    check("a wide character is two columns, not one",
          dl.columns("日本語") == 6 and dl.columns("ＡＢ") == 4,
          "%d / %d" % (dl.columns("日本語"), dl.columns("ＡＢ")))
    # The classic monospace-table bug: `señor` is 5 characters and 6 BYTES.
    check("an accented label is measured in characters, not bytes",
          dl.columns("señor") == 5 == dl.columns("senor")
          and len("señor".encode("utf-8")) == 6,
          "columns=%d" % dl.columns("señor"))
    check("an empty label measures 0 and never divides by anything",
          dl.columns("") == 0 and dl.text_width("") == 0.0)
    # The kit's own font stack, byte for byte. A presentation attribute cannot
    # read `var(--mono)`, so the renderer carries a COPY — and a copy that can
    # drift silently is a metric that stops being true.
    css = open(TOKENS, encoding="utf-8").read()
    m = re.search(r"--mono:\s*([^;]+);", css)
    check("diagram_svg.MONO is tokens.css's --mono stack verbatim",
          m is not None and m.group(1).strip() == ds.MONO,
          "tokens.css: %r / diagram_svg: %r"
          % (m.group(1).strip() if m else None, ds.MONO))

    print()
    print("== a box is sized to ITS label (the plan's Q10) ==")
    widths = [dl.box_width("x" * n) for n in (1, 5, 10, 20, 40)]
    check("box width is non-decreasing over five label lengths: %s"
          % ", ".join("%.0f" % w for w in widths),
          all(a <= b for a, b in zip(widths, widths[1:])), str(widths))
    # Non-decreasing is not enough: a constant box width satisfies it. Above
    # the one-character floor the width must MOVE, and move by the metric.
    grew = [b - a for a, b in zip(widths[1:], widths[2:])]
    check("...and strictly grows past the minimum box, by the metric",
          all(g > 0 for g in grew)
          and abs(dl.box_width("x" * 40)
                  - (dl.CHAR_W * dl.FS * 40 + 2 * dl.PAD_X)) < 1e-9,
          str(grew))
    check("a one-character label still gets the minimum box, not a sliver",
          dl.box_width("x") == dl.MIN_BOX_W, str(dl.box_width("x")))
    # The "max or last?" shape. Two runs holding the same five labels in
    # opposite orders must occupy the same canvas: a layout that sized the run
    # off the LAST label it saw would give two different numbers here.
    labels = ["corto", "un poco mas largo", "x", "mediano", "L" * 30]
    a = lay("row", *["b%d: %s" % (i, s) for i, s in enumerate(labels)])
    b = lay("row", *["b%d: %s" % (i, s) for i, s in enumerate(labels[::-1])])
    check("a run is the sum of its own boxes, whatever order the longest is in",
          abs(a.view[2] - b.view[2]) < 1e-9,
          "%.2f vs %.2f" % (a.view[2], b.view[2]))
    check("...and every box keeps its own width, not the run's maximum",
          len({round(x.w, 2) for x in a.boxes}) == 4,
          str(sorted(round(x.w, 2) for x in a.boxes)))

    print()
    print("== the grammar's refusals, at the line INSIDE the fence ==")
    rejects("an arrow naming a box no line declares",
            fence("row", "a: uno", "a -> zzz"), 3, "which no line declares",
            SpecSyntaxError)
    rejects("...and it names the boxes that DO exist",
            fence("row", "a: uno", "zzz -> a"), 3, "the boxes are: `a`",
            SpecSyntaxError)
    rejects("a box declared twice names the first declaration's line",
            fence("row", "a: uno", "b: dos", "a: otra vez"), 4,
            "already declared on line 2", SpecSyntaxError)
    rejects("a self-arrow", fence("row", "a: uno", "a -> a"), 3,
            "an arrow from a box to itself", SpecSyntaxError)
    rejects("the same arrow declared twice",
            fence("row", "a: uno", "b: dos", "a -> b", "a -> b"), 5,
            "already declared", SpecSyntaxError)
    rejects("an empty label", fence("row", "a:"), 2, "empty label",
            SpecSyntaxError)
    rejects("...and a label of only spaces is the same empty label",
            fence("row", "a:    "), 2, "empty label", SpecSyntaxError)
    rejects("a chained arrow says one arrow per line",
            fence("row", "a: uno", "b: dos", "c: tres", "a -> b -> c"), 5,
            "one arrow per line", SpecSyntaxError)
    rejects("a line that is neither a box nor an arrow",
            fence("row", "a: uno", "esto es prosa"), 3,
            "neither a box nor an arrow", SpecSyntaxError)
    rejects("a nested fence in a diagram body",
            "::: diagram {shape=row}\na: uno\n::: note\nx\n:::\n:::", 3,
            "its body is data rows", SpecBuildError)
    rejects("a `lane` line in a shape that has no lanes",
            fence("row", "lane Antes", "a: uno"), 2,
            "only a `before-after` line", SpecSyntaxError)
    # A label may CONTAIN an arrow: the box rule is matched first, so
    # `paso: construir -> enviar` is one box and not an ambiguity.
    html = holds("a label containing `->` is a label, not an arrow",
                 fence("row", "paso: construir -> enviar"),
                 ">construir -&gt; enviar<")
    check("...and it produced exactly one box",
          len(rects(svg_of(html))) == 1, svg_of(html))

    print()
    print("== the block's refusals, at the FENCE's line ==")
    rejects("a diagram with no shape", "::: diagram\na: uno\n:::", 1,
            "there is no default", SpecBuildError)
    rejects("an unknown shape", "::: diagram {shape=sankey}\na: uno\n:::", 1,
            "is not one of", SpecBuildError)
    rejects("an empty body", "::: diagram {shape=row}\n:::", 1,
            "a diagram with no boxes", SpecBuildError)
    rejects("a body of only blank lines", "::: diagram {shape=row}\n\n \n:::",
            1, "a diagram with no boxes", SpecBuildError)
    rejects("an unknown attr", "::: diagram {shape=row layout=lr}\na: x\n:::",
            1, "takes no attr", SpecBuildError)
    rejects("a cycle of one box", fence("cycle", "a: sola"), 1,
            "a cycle of one is a box", SpecBuildError)

    print()
    print("== row: one box, adjacency, and the arrow router at both ends ==")
    one = lay("row", "a: sola")
    check("one box and no arrows lays out: one box, zero routes",
          len(one.boxes) == 1 and not one.routes and not one.divider)
    check("...and its canvas is the box plus a margin on each side",
          abs(one.view[2] - (one.boxes[0].w + 2 * dl.MARGIN)) < 1e-9,
          str(one.view))
    run = lay("row", "a: uno", "b: dos", "c: tres largo de verdad", "d: x")
    gaps = [run.boxes[i + 1].x - (run.boxes[i].x + run.boxes[i].w)
            for i in range(len(run.boxes) - 1)]
    # "Adjacent boxes with zero gap" is not a state this layout can reach: the
    # gap is a constant the author cannot set, and it is the corridor the
    # straight arrow and its head are drawn in.
    check("every adjacent pair keeps the same non-zero gap (%s)"
          % ", ".join("%.0f" % g for g in gaps),
          gaps and all(abs(g - dl.GAP) < 1e-9 for g in gaps) and dl.GAP > 0,
          str(gaps))
    check("...and the gap is wider than the arrowhead drawn in it",
          dl.GAP > ds.HEAD_L * 2, "%s vs %s" % (dl.GAP, ds.HEAD_L))

    fwd = lay("row", "a: uno", "b: dos", "a -> b")
    check("an adjacent forward arrow is a straight segment across the gap",
          len(fwd.routes[0].points) == 2
          and fwd.routes[0].points[0][1] == fwd.routes[0].points[1][1]
          and fwd.routes[0].tone == "mut", str(fwd.routes[0].points))
    skip = lay("row", "a: uno", "b: dos", "c: tres", "a -> c")
    top = min(b.y for b in skip.boxes)
    check("a forward arrow that skips a box bows ABOVE the run, never through it",
          len(skip.routes[0].points) == 3
          and skip.routes[0].points[1][1] < top
          and skip.routes[0].tone == "mut", str(skip.routes[0].points))
    back = lay("row", "a: uno", "b: dos", "c: tres", "c -> a")
    bottom = max(b.y + b.h for b in back.boxes)
    check("a backward arrow bows BELOW the run and wears the `flg` tone",
          len(back.routes[0].points) == 3
          and back.routes[0].points[1][1] > bottom
          and back.routes[0].tone == "flg", str(back.routes[0].points))
    check("...and the two curves never share a side, so they cannot overdraw",
          skip.routes[0].points[1][1] < top < bottom < back.routes[0].points[1][1])
    check("the canvas grew to hold the curve it drew",
          back.view[1] + back.view[3] > bottom + dl.ARC,
          str(back.view))
    holds("`pipeline` is a spelling of `row`, not a fourth shape",
          fence("pipeline", "a: uno", "b: dos", "a -> b"), "<svg ")
    check("...and the two spellings emit byte-identical SVG",
          build(fence("pipeline", "a: uno", "b: dos", "a -> b"))
          == build(fence("row", "a: uno", "b: dos", "a -> b")))

    print()
    print("== before-after: two lanes, and what they refuse ==")
    ba = lay("before-after", "lane Antes", "a1: uno", "a2: dos", "a3: tres",
             "lane Después", "b1: solo uno")
    check("two lanes of UNEQUAL length lay out, each on its own",
          len([b for b in ba.boxes if b.lane == 0]) == 3
          and len([b for b in ba.boxes if b.lane == 1]) == 1)
    check("...on two rows that do not overlap",
          max(b.y + b.h for b in ba.boxes if b.lane == 0)
          < min(b.y for b in ba.boxes if b.lane == 1))
    check("...with the dividing rule between them",
          ba.divider is not None
          and max(b.y + b.h for b in ba.boxes if b.lane == 0)
          < ba.divider[1] < min(b.y for b in ba.boxes if b.lane == 1),
          str(ba.divider))
    check("the first lane is the quieter tone, the second the accent",
          {b.tone for b in ba.boxes if b.lane == 0} == {"mut"}
          and {b.tone for b in ba.boxes if b.lane == 1} == {"acc"})
    # The rule is measured off the WIDEST thing on the canvas, and a lane title
    # can be wider than the lane under it.
    wide = lay("before-after", "lane Después de la corrección completa",
               "a: x", "lane B", "b: y")
    check("a lane title wider than its boxes widens the rule and the canvas",
          wide.divider[2] >= dl.text_width(
              "Después de la corrección completa", dl.TITLE_FS) - 1e-9,
          str(wide.divider))
    rejects("a box above the first `lane` line",
            fence("before-after", "a: uno", "lane Antes", "b: dos"), 2,
            "sits above the first `lane`", SpecSyntaxError)
    rejects("a lane closed with no boxes in it",
            fence("before-after", "lane Antes", "lane Después", "b: dos"), 3,
            "closed with no boxes", SpecSyntaxError)
    rejects("the SECOND lane left empty",
            fence("before-after", "lane Antes", "a: uno", "lane Después"), 4,
            "has no boxes", SpecSyntaxError)
    rejects("only one lane",
            fence("before-after", "lane Antes", "a: uno"), 2,
            "needs two `lane` lines", SpecSyntaxError)
    rejects("a third lane",
            fence("before-after", "lane A", "a: 1", "lane B", "b: 2",
                  "lane C", "c: 3"), 6, "this is the 3rd `lane`",
            SpecSyntaxError)
    rejects("a lane with no title",
            fence("before-after", "lane   ", "a: uno"), 2,
            "has no title", SpecSyntaxError)
    rejects("an arrow crossing the two lanes",
            fence("before-after", "lane A", "a: 1", "lane B", "b: 2",
                  "a -> b"), 6, "crosses the two lanes", SpecSyntaxError)
    rejects("an arrow skipping a box inside a lane",
            fence("before-after", "lane A", "a: 1", "b: 2", "c: 3",
                  "lane B", "d: 4", "a -> c"), 8, "skips over a box",
            SpecSyntaxError)
    holds("an arrow between two neighbours of one lane is drawn",
          fence("before-after", "lane A", "a: 1", "b: 2", "lane B", "c: 3",
                "a -> b"), "<path")
    # `lane` is reserved as a first word, but a NAME may start with it.
    holds("a box named `lane-1` is a box, not a lane",
          fence("row", "lane-1: uno"), ">uno<")

    print()
    print("== cycle: the ring is sized by the boxes on it ==")
    two = lay("cycle", "a: uno", "b: dos", "a -> b", "b -> a")
    check("a cycle of two lays out, with both arrows",
          len(two.boxes) == 2 and len(two.routes) == 2)
    # With two boxes the chord's midpoint IS the ring's centre, so "bow away
    # from the centre" has no direction and the fallback has to flip with the
    # arrow. If it did not, the two arrows would be drawn on top of each other.
    c0, c1 = two.routes[0].points[1], two.routes[1].points[1]
    # "Opposite" as a claim about the RING, not a distance: the two control
    # points must fall in opposite half-planes through its centre, which is the
    # origin the boxes were placed around.
    check("...and its two arrows bow to OPPOSITE sides, not onto each other",
          c0 != c1 and (c0[0] * c1[0] + c0[1] * c1[1]) < 0,
          "%s vs %s" % (c0, c1))
    ring = lay("cycle", "a: " + "L" * 30, "b: x", "c: y", "d: z",
               "a -> b", "b -> c", "c -> d", "d -> a")
    boxes = ring.boxes
    worst, which = worst_pair(ring)
    check("boxes whose combined width outgrows the ring push the RADIUS out, "
          "they do not overlap (%.0f units of clearance)" % worst, worst > 0,
          "tightest pair %s in %s"
          % (which, [(b.name, round(b.x, 1), round(b.w, 1)) for b in boxes]))
    small = lay("cycle", "a: x", "b: y", "c: z", "d: w",
                "a -> b", "b -> c", "c -> d", "d -> a")
    check("...and the radius came from the LONGEST pair, not a constant",
          ring.view[2] > small.view[2],
          "%.0f vs %.0f" % (ring.view[2], small.view[2]))
    # The pair an ADJACENT-pairs-only radius cannot see. At N == 4 the boxes
    # at angles 0 and pi have the same `cy` — they overlap by the full BOX_H
    # and only `2R` holds them apart, and `2R` was derived from the two
    # adjacent pairs, which here are (long, short). Put the two long labels
    # OPPOSITE each other and the ring drew one straight through the other,
    # with `svg_text_findings` returning [] (it compares a label to a label
    # and a label to its own rect, never a rect to a rect). Asserted as
    # rectangle disjointness in BOTH axes, over every pair.
    long_label = "L" * 60
    opp = lay("cycle", "a: x", "b: " + long_label, "c: y", "d: " + long_label,
              "a -> b", "b -> c", "c -> d", "d -> a")
    gap, which = worst_pair(opp)
    check("two long labels OPPOSITE each other on a ring do not overlap "
          "either (%.0f units of clearance, tightest pair %s)" % (gap, which),
          gap > 0,
          str([(b.name, round(b.x, 1), round(b.y, 1), round(b.w, 1))
               for b in opp.boxes]))
    # And the same claim on the RECTS the page actually carries, so the
    # guarantee is not a property of the layout objects alone.
    svg = svg_of(holds("a ring of two long opposite labels renders",
                       fence("cycle", "a: x", "b: " + long_label, "c: y",
                             "d: " + long_label, "a -> b", "b -> c",
                             "c -> d", "d -> a"), "<rect"))
    rs = [(fnum(t, "x"), fnum(t, "y"), fnum(t, "width"), fnum(t, "height"))
          for t in rects(svg)]
    drawn = [(i + 1, j + 1) for i in range(len(rs))
             for j in range(i + 1, len(rs))
             if min(rs[i][0] + rs[i][2], rs[j][0] + rs[j][2])
             - max(rs[i][0], rs[j][0]) > 0
             and min(rs[i][1] + rs[i][3], rs[j][1] + rs[j][3])
             - max(rs[i][1], rs[j][1]) > 0]
    check("...and no two <rect> of that page intersect", not drawn,
          "overlapping rect pairs %r in %r" % (drawn, rs))
    # Every ring size, not the one N a fixture happens to use: N == 4 is the
    # only size with a dy == 0 pair up to the refusal boundary, and a fix that
    # knew that would be the same defect waiting for a different N.
    worst_n = []
    for n in range(2, 11):
        for k in range(n):
            labels = ["s%d: x" % i for i in range(n)]
            labels[k] = "s%d: %s" % (k, "L" * 80)
            if n > 2:
                labels[(k + n // 2) % n] = ("s%d: %s"
                                            % ((k + n // 2) % n, "L" * 80))
            worst_n.append((n, k) + worst_pair(lay("cycle", *labels)))
    bad_n = [t for t in worst_n if t[2] <= 0]
    check("no ring of 2..10 boxes overlaps, wherever the long labels sit "
          "(%d rings, tightest %.0f units)" % (len(worst_n),
                                               min(t[2] for t in worst_n)),
          not bad_n, str(bad_n[:4]))
    # The radius reads the WIDTHS and the ring size, nothing about WHERE the
    # long label sits — so moving it around the ring cannot change the ring.
    # A radius taken from the last pair looked at, or one that forgets the
    # pair closing the ring, is exactly what this asymmetry exposes.
    radii = []
    for k in range(4):
        labels = ["x", "y", "z", "w"]
        labels[k] = "L" * 30
        r = lay("cycle", *["%s: %s" % (nm, lb) for nm, lb
                           in zip("abcd", labels)])
        radii.append(round(math.hypot(r.boxes[0].cx, r.boxes[0].cy), 6))
    check("the ring is the same size wherever the long label sits on it",
          len(set(radii)) == 1, "radii by position: %r" % radii)
    check("an arrow that runs WITH the ring (including the one that closes it) "
          "is `mut`", {r.tone for r in ring.routes} == {"mut"},
          str([r.tone for r in ring.routes]))
    against = lay("cycle", "a: x", "b: y", "c: z", "a -> b", "b -> c", "b -> a")
    check("...and one that runs against it is `flg`",
          [r.tone for r in against.routes] == ["mut", "mut", "flg"],
          str([r.tone for r in against.routes]))
    holds("a cycle with no arrows at all is boxes on a ring, not an error",
          fence("cycle", "a: uno", "b: dos"), "<rect")

    print()
    print("== a label the emitted SVG could not carry is refused ==")
    # `esc()` is `html.escape`: it rewrites `& < > " '` and passes a C0
    # control character through RAW. XML 1.0 allows none of them in character
    # data bar tab/LF/CR, so `Pa\x0bso` makes the <svg> not well-formed —
    # invisible to check_artifact (its SVG rules are regexes over text) and
    # able to make a browser's XML parser drop the figure. REFUSED at the
    # box's own line rather than stripped: this module's contract is
    # "everything is refused, or laid out", and a strip would silently draw a
    # label the author did not write.
    rejects("a control character in a label is refused at its own line",
            fence("row", "a: Pa\x0bso uno"), 2, "control character \\x0b",
            SpecSyntaxError)
    rejects("...and in a lane title too — it is emitted through the same esc()",
            fence("before-after", "lane An\x07tes", "a: x", "lane Despues",
                  "b: y"), 2, "control character \\x07", SpecSyntaxError)
    rejects("a NUL is refused, not carried into the page",
            fence("row", "a: x\x00y"), 2, "control character \\x00",
            SpecSyntaxError)
    # The claim the refusal exists for, measured: the <svg> of a page built
    # from the hardest labels this grammar accepts PARSES as XML. `holds`
    # only proves a substring is present; minidom proves the document is one.
    xml_html = holds("a page of hostile-but-legal labels builds",
                     fence("row", "a: A & B", "b: <tag> \"q\" 'x'",
                           "c: señor 日本語 🙂", "a -> b", "b -> c"), "<svg")
    try:
        xml.dom.minidom.parseString(svg_of(xml_html))
        ok("...and its <svg> parses as well-formed XML")
    except Exception as exc:                        # noqa: BLE001
        fail("the emitted <svg> is not well-formed XML: %s" % exc)

    print()
    print("== a label wider than the page is refused, not clipped ==")
    # The one label the layout will not draw: `figure svg { width: 100% }`
    # scales the viewBox to the page, so a box wider than the page has no
    # readable size left. Everything SHORTER is laid out and scaled, never cut.
    fits = "L" * 88
    over = "L" * 89
    check("the refusal boundary is where a box outgrows the page",
          dl.text_width(fits) + 2 * dl.PAD_X <= dl.MAX_BOX_W
          < dl.text_width(over) + 2 * dl.PAD_X,
          "%.1f / %.1f" % (dl.text_width(fits) + 2 * dl.PAD_X,
                           dl.text_width(over) + 2 * dl.PAD_X))
    holds("the widest label that still fits the page is drawn",
          fence("row", "a: " + fits), ">" + fits + "<")
    rejects("one character more is refused, with the page width in the message",
            fence("row", "a: " + over), 2, "the page is 720 wide",
            SpecSyntaxError)
    # A RUN wider than the page is not the same thing and is not refused: the
    # viewBox grows and the browser scales the whole figure down uniformly, so
    # nothing is clipped and no label leaves its box.
    long_run = lay("row", *["b%d: etiqueta %d" % (i, i) for i in range(10)])
    check("a RUN wider than the page scales instead of clipping (viewBox %.0f)"
          % long_run.view[2], long_run.view[2] > dl.MAX_BOX_W)
    check("...and every one of its labels is still inside its own box",
          not findings(ds.svg(long_run)), str(findings(ds.svg(long_run))))

    print()
    print("== 0 svg-text warnings, measured by the real checker ==")
    SHAPES = [
        ("row, straight and curved arrows",
         fence("row", "a: uno", "b: dos largo", "c: t", "a -> b", "b -> c",
               "c -> a", "a -> c")),
        ("before-after, unequal lanes",
         fence("before-after", "lane Antes de la corrección", "a: medir",
               "b: escribir coordenadas", "a -> b",
               "lane Después", "c: una fence")),
        ("cycle of four",
         fence("cycle", "a: Preguntar", "b: R", "c: Decidir y escribir",
               "d: W", "a -> b", "b -> c", "c -> d", "d -> a")),
        ("cycle of two", fence("cycle", "a: uno", "b: dos", "a -> b", "b -> a")),
        ("one box", fence("row", "a: x")),
    ]
    for label, spec in SHAPES:
        html = build(spec)
        BUILT.append((label, html))
        got = findings(html)
        check("no svg-text finding: %s" % label, not got, "\n".join(got))
    # The labels the geometry is most likely to be wrong about, all on one
    # canvas: one character, a wide CJK run, an accented Spanish word, the
    # widest label that fits, and punctuation the checker's own proportional
    # table treats as narrow.
    hard = fence("row", "a: x", "b: 日本語のラベル", "c: Corrección",
                 "d: " + "W" * 60, "e: i.l|!;:'", "a -> b", "b -> c",
                 "c -> d", "d -> e", "e -> a")
    html = build(hard)
    BUILT.append(("the hard-label row", html))
    got = findings(html)
    check("no svg-text finding on the hard labels either", not got,
          "\n".join(got))
    # And the number behind it: how far the monospace table could be BELOW the
    # truth before a label outgrew the box it was given. The checker fires at
    # `true_width > rect_width + max(4, 0.06 * true_width)`.
    svg = svg_of(html)
    margins = []
    for rect, text in zip(rects(svg),
                          re.findall(r'<text x=[^>]*>([^<]*)</text>', svg)):
        rw = fnum(rect, "width")
        # UNESCAPED, because that is what the checker measures: it strips the
        # tags and runs `html.unescape` before sizing. Measuring `&#x27;` as
        # six characters is the same confusion as measuring bytes.
        tw = check_artifact.svg_text_width(_html.unescape(text), dl.FS,
                                           mono=True)
        if tw > 0:
            margins.append((rw + max(4.0, 0.06 * tw)) / tw)
    # The floor is analytic, not a hope: a box is `tw + 2*PAD_X` wide and the
    # checker fires past `tw * 1.06 + max(4, ...)`, so the headroom is
    # `1.06 + 2*PAD_X/tw` and it is smallest for the WIDEST label the grammar
    # allows (MAX_BOX_W - 2*PAD_X units). Every legal label has at least that.
    floor = 1.06 + 2 * dl.PAD_X / (dl.MAX_BOX_W - 2 * dl.PAD_X)
    check("every box has at least the analytic headroom over the checker's own "
          "estimate (floor %.3f, narrowest here %.3f)" % (floor, min(margins)),
          min(margins) >= floor - 1e-9,
          str(sorted(round(x, 3) for x in margins)))
    check("...and that floor is above 10%%, so the 0.6 em advance could be "
          "that far under the true font and still not overflow",
          floor > 1.10, "%.4f" % floor)

    print()
    print("== colour: three classes, currentColor, zero hex ==")
    html = build(fence("row", "a: uno", "b: dos", "a -> b", "b -> a"))
    svg = svg_of(html)
    check("every painted element carries a kit class or is a box label",
          not re.findall(r'<(rect|path|line)\b(?![^>]*\bclass="(acc|flg|mut)")',
                         svg), svg)
    check("the three kit classes are the whole palette",
          set(re.findall(r'class="([a-z]+)"', svg)) <= {"acc", "flg", "mut"},
          str(set(re.findall(r'class="([a-z]+)"', svg))))
    check("nothing is painted with a var() in a presentation attribute",
          "var(--" not in svg, svg)
    hexes = []
    for label, page in BUILT:
        found = re.findall(r'#[0-9a-fA-F]{3,8}\b', svg_of(page))
        if found:
            hexes.append((label, found))
    check("zero literal hex in any emitted diagram (%d pages)" % len(BUILT),
          not hexes, str(hexes))
    for path in (os.path.join(SCRIPTS, "diagram_layout.py"),
                 os.path.join(SCRIPTS, "diagram_svg.py")):
        src = open(path, encoding="utf-8").read()
        found = re.findall(r'["\']#[0-9a-fA-F]{3,8}["\']', src)
        check("zero literal hex in %s" % os.path.basename(path), not found,
              str(found))

    print()
    print("== a hostile label cannot leave its element ==")
    html = holds("a label that tries to open an element is escaped",
                 fence("row", 'a: <img src=x onerror=alert(1)>'),
                 "&lt;img")
    check("no <img element reaches the page",
          "onerror" in html and "<img" not in html, html)
    html = holds("a quote-and-angle label cannot break out of an attribute",
                 fence("row", 'a: "\'/><script>x</script>'), "&lt;script&gt;")
    check("no <script> reaches the page", "<script" not in html, html)
    svg = svg_of(html)
    check("the SVG's own tags are still well formed (every < opens a known tag)",
          not re.findall(r'<(?!/?(?:svg|rect|text|path|line)\b)', svg), svg)
    holds("an ampersand in a label is escaped once, not twice",
          fence("row", "a: A & B"), ">A &amp; B<")
    check("an escaped ampersand is not double-escaped",
          "&amp;amp;" not in BUILT[-1][1], BUILT[-1][1])
    # A hostile label is also MEASURED before it is escaped: sizing the box for
    # `&amp;` (5 columns) instead of `&` (1) is not a security hole, but it is
    # the same confusion in the other direction and it makes the box a lie.
    esc_lay = lay("row", "a: A & B")
    check("a box is sized on the raw label, not on its escaped spelling",
          esc_lay.boxes[0].w == dl.box_width("A & B"),
          "%.2f" % esc_lay.boxes[0].w)

    print()
    print("== the same diagram built twice is byte-identical ==")
    spec = open(FIXTURE, encoding="utf-8").read()
    a, b = build(spec), build(spec)
    check("build() is deterministic in one process", a == b)
    env = dict(os.environ)
    outs = []
    for seed in ("0", "1", "42"):
        env["PYTHONHASHSEED"] = seed
        r = subprocess.run([sys.executable, BUILD, FIXTURE],
                           capture_output=True, env=env)
        outs.append(r.stdout)
    check("...and across processes with different PYTHONHASHSEED",
          outs[0] == outs[1] == outs[2] and outs[0].decode("utf-8") == a,
          "%d distinct outputs" % len(set(outs)))

    print()
    print("== the fixture page, end to end, through check-artifact ==")
    out = os.path.join(tmp, "diagram-sample.html")
    r = subprocess.run([sys.executable, BUILD, FIXTURE, "-o", out, "--check"],
                       capture_output=True, text=True)
    check("spec_build.py -o --check exits 0 on the diagram fixture",
          r.returncode == 0, r.stdout + r.stderr)
    r = subprocess.run(["bash", CHECK, out], capture_output=True, text=True)
    check("check-artifact.sh passes the built page on its own",
          r.returncode == 0, r.stdout + r.stderr)
    page = open(out, encoding="utf-8").read()
    check("the page carries all three shapes", page.count("<svg ") == 3,
          page[:200])
    check("...and the kit", "artifact-kit" in page)
    check("...and its ids survive byte-exactly",
          '<figure id="d1">' in page and '<figure id="d2">' in page
          and '<figure id="d3">' in page)
    check("a diagram is never given a data-id",
          'data-id' not in page,
          "data-id on a figure is how check_artifact recognises a consultation "
          "ITEM: the page then failed eight consult rules with no question in it")
    said = r.stdout + r.stderr
    # The one warning this page carries is the documented "nothing could be
    # measured" note: `currentColor` is what the canon prescribes for figure
    # text. An `svg-text` line here is a real finding and the phase's
    # acceptance criterion.
    others = [ln for ln in said.splitlines()
              if "WARN" in ln and "no figure text could be measured" not in ln]
    check("no warning but the documented currentColor one", not others,
          "\n".join(others))
    check("zero svg-text warnings on the wrapped page (the phase's criterion)",
          not findings(page), "\n".join(findings(page)))

    print()
    print("== what the contract cannot see ==")
    BUILT.append(("the wrapped fixture page", page))
    dirty = [label for label, h in BUILT if "\x00" in h]
    check("every page built here holds zero \\x00 bytes (%d pages)" % len(BUILT),
          not dirty, "NUL in: %r" % dirty)
    # `build()` raises its two documented types and nothing else. A ValueError
    # or a ZeroDivisionError out of the layout is uncatchable by every caller
    # that handles the spec exceptions — which is all of them.
    for label, spec in (
            ("zero boxes", "::: diagram {shape=row}\n:::"),
            ("a cycle of one", fence("cycle", "a: sola")),
            ("a cycle of two", fence("cycle", "a: x", "b: y")),
            ("one box, one self-arrow", fence("row", "a: x", "a -> a")),
            ("arrows and no boxes", fence("row", "a -> b")),
            ("only lane lines", fence("before-after", "lane A", "lane B")),
            ("a one-character ring", fence("cycle", "a: x", "b: y", "c: z")),
            ("a label of one space", fence("row", "a:  ")),
            ("a label of 300 characters", fence("row", "a: " + "x" * 300))):
        try:
            build(spec)
            ok("%s: built" % label)
        except (SpecSyntaxError, SpecBuildError) as exc:
            ok("%s: refused at line %d" % (label, exc.line))
        except Exception as exc:                    # noqa: BLE001
            fail("%s: raised %s, which no caller catches (%s)"
                 % (label, type(exc).__name__, exc))
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
if failures:
    print("%d failure(s)" % len(failures))
    raise SystemExit(1)
print("OK — the diagram block: the monospace column metric (characters, never "
      "bytes, wide characters at two, never below the checker's own), a box "
      "sized to its own label, every malformed line refused at its own line "
      "inside the fence and the block's three at the fence line, the three "
      "shapes' boundaries (one box, unequal lanes, a cycle of one and of two, "
      "a ring the boxes outgrow, a backward arrow, a label wider than the "
      "page), 0 svg-text findings from the real checker on every shape and on "
      "the hard labels, only acc/flg/mut and zero literal hex, a hostile "
      "label escaped and measured raw, a byte-identical rebuild across "
      "processes, and the fixture page through check-artifact.sh")
