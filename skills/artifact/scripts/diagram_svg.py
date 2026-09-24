#!/usr/bin/env python3
"""diagram_svg.py — the `::: diagram` renderer. A serialiser and nothing else.

Every number this file writes was decided by `diagram_layout.py`. That split is
the point: a layout is a thing you can assert about (a box's width, a route's
points, the ring's radius) without parsing markup, and a renderer you can read
in one sitting because it holds no arithmetic worth being wrong about.

Colour
------
Three classes and no fourth, straight out of `components.css`:

    figure svg .acc { color: var(--accent) }
    figure svg .flg { color: var(--flag) }
    figure svg .mut { color: var(--muted) }

and every shape is painted `currentColor`, so the class is what themes it and
the browser resolves it in light, dark and both explicit toggles alike. There
is NO literal hex in this file and there must never be one, for the reason
`chart_svg.py` gives about `--s1..--s8`: the kit defines these four times over
and a fifth definition here would agree with exactly one of them. There is also
no `fill="var(--accent)"` — `components.css` says in as many words that the
browser does not resolve a custom property in a presentation attribute and
falls back to black, which is invisible in dark mode.

What each class MEANS here, so the page is readable and not merely coloured:

    acc   a box. The thing the diagram is made of.
    mut   the arrows that go forward, the lane titles, the dividing rule, and
          the boxes of a `before-after`'s FIRST lane — the state being left.
    flg   an arrow that goes BACKWARD: the retry, the rejection, the edge that
          closes a ring. `--flag` is the kit's colour for exactly that, and a
          backward arrow drawn like a forward one is the one thing a reader of
          a flow diagram cannot recover from the picture.

Text
----
Labels are drawn in the kit's `--mono` stack, spelled out (a presentation
attribute cannot read `var(--mono)` either). That is not a style choice, it is
what makes `diagram_layout`'s column table TRUE: a monospace advance of 0.6 em
is what both this module's sizing and `check_artifact.svg_text_width`'s
monospace branch assume, so the box a label is given and the box the checker
measures it against are computed the same way.

Every label reaching the SVG goes through `esc()`, once, at the point of
emission — `_shell.esc` is `html.escape(quote=True)`. A box label is DATA and
must not be able to close an attribute or open an element.
"""

import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "dash"))
sys.path.insert(0, _HERE)
from _shell import esc                             # noqa: E402
import diagram_layout as dl                        # noqa: E402

HEAD_L = 9.0           # the arrowhead, from its tip back along the line
HEAD_A = 0.38          # half its opening, in radians
CORNER = 3.0           # the box's corner radius
STROKE = 1.5
# Spelled out because a presentation attribute cannot resolve `var(--mono)`.
# Byte-for-byte the `--mono` stack of `tokens.css`; the two are checked against
# each other by `test_diagram.py`, so this copy cannot drift silently.
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"


def _num(x):
    """A float as the shortest stable decimal string.

    The same function `chart_svg.py` carries, for the same reason: `repr()` of
    a float has a tail that differs between inputs that draw identically, and
    `-0.0` prints a minus sign for a value that is zero. Two decimals is finer
    than a pixel at this size, and it is what makes two builds byte-identical.
    """
    v = round(float(x), 2)
    if v == 0:
        v = 0.0
    s = "%.2f" % v
    s = s.rstrip("0").rstrip(".")
    return s or "0"


def _path(points):
    """`M`, then `L` for a segment or `Q` for a quadratic. Nothing else."""
    d = "M %s,%s" % (_num(points[0][0]), _num(points[0][1]))
    if len(points) == 2:
        d += " L %s,%s" % (_num(points[1][0]), _num(points[1][1]))
    else:
        d += " Q %s,%s %s,%s" % (_num(points[1][0]), _num(points[1][1]),
                                 _num(points[2][0]), _num(points[2][1]))
    return d


def _head(x, y, angle, tone):
    """The arrowhead as a filled triangle, pointing along `angle`.

    It is drawn BACKWARD from the tip, so it never reaches past the point the
    layout put it at and cannot push anything out of the viewBox.
    """
    back = angle + math.pi
    a = (x + HEAD_L * math.cos(back - HEAD_A),
         y + HEAD_L * math.sin(back - HEAD_A))
    b = (x + HEAD_L * math.cos(back + HEAD_A),
         y + HEAD_L * math.sin(back + HEAD_A))
    return ('  <path class="%s" d="M %s,%s L %s,%s L %s,%s Z" '
            'fill="currentColor"/>'
            % (tone, _num(x), _num(y), _num(a[0]), _num(a[1]),
               _num(b[0]), _num(b[1])))


def svg(lay):
    """One `<svg>` element for a placed `diagram_layout.Layout`."""
    vx, vy, vw, vh = lay.view
    out = ['<svg viewBox="%s %s %s %s" xmlns="http://www.w3.org/2000/svg" '
           'role="img">' % (_num(vx), _num(vy), _num(vw), _num(vh))]

    if lay.divider:
        dx0, dy, dx1 = lay.divider
        out.append('  <line class="mut" x1="%s" y1="%s" x2="%s" y2="%s" '
                   'stroke="currentColor" stroke-opacity="0.5" '
                   'stroke-dasharray="4 4"/>'
                   % (_num(dx0), _num(dy), _num(dx1), _num(dy)))

    for text, tx, ty in lay.titles:
        out.append('  <text class="mut" x="%s" y="%s" font-size="%s" '
                   'font-family="%s" fill="currentColor">%s</text>'
                   % (_num(tx), _num(ty), _num(dl.TITLE_FS), MONO, esc(text)))

    # The arrows first, so a box is painted over the line that reaches it and
    # not under it. Both are `currentColor` on a transparent box, so the order
    # only shows where the head meets the border — which is every arrow.
    for r in lay.routes:
        out.append('  <path class="%s" d="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>' % (r.tone, _path(r.points),
                                            _num(STROKE)))
        tip = r.points[-1]
        out.append(_head(tip[0], tip[1], r.angle, r.tone))

    for b in lay.boxes:
        out.append('  <rect class="%s" x="%s" y="%s" width="%s" height="%s" '
                   'rx="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>'
                   % (b.tone, _num(b.x), _num(b.y), _num(b.w), _num(b.h),
                      _num(CORNER), _num(STROKE)))
        # The baseline sits 0.35 em below the box's middle, which is where a
        # cap-height glyph reads as centred. `check_artifact` measures a label
        # from 0.8 em above the baseline to 0.25 em below it, so this keeps the
        # whole glyph box inside the rect with room on both sides.
        out.append('  <text x="%s" y="%s" text-anchor="middle" font-size="%s" '
                   'font-family="%s" fill="currentColor">%s</text>'
                   % (_num(b.cx), _num(b.cy + 0.35 * dl.FS), _num(dl.FS),
                      MONO, esc(b.label)))

    out.append("</svg>")
    return "\n".join(out)


def figure(lay, title="", classes="", ident=""):
    """The whole block: the kit's `<figure>`, the diagram, and its caption.

    Identical plumbing to `chart_svg.figure`, including the one thing that is
    easy to get wrong: the id is carried byte-exactly as `id=` and NOTHING
    else. No `data-id=` — that attribute is how `check_artifact.py` recognises
    a consultation ITEM, and a figure wearing one is read as a decision with no
    title and no reply surface.
    """
    head = "<figure"
    if ident:
        head += ' id="%s"' % esc(ident)
    if classes:
        head += ' class="%s"' % esc(classes)
    out = [head + ">", svg(lay)]
    if title:
        out.append("<figcaption>%s</figcaption>" % esc(title))
    out.append("</figure>")
    return "\n".join(out)
