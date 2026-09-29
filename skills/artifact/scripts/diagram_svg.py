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
Labels are drawn in the kit's `--sans` token, set ONCE on the root as
`style="font-family:var(--sans)"`: a style attribute resolves a custom
property where a presentation attribute does not, so no font stack is copied
here. `diagram_layout.text_width` sizes every box for that font. The same
`style` caps the drawing at `MAX_SCALE` px per unit, so a short row is never
blown up to the column's width.

Two drawings, one figure
------------------------
When `diagram_layout.drawings` returns a narrow twin, the figure carries both
svgs (`dg-wide`, `dg-narrow`) and one `<style>` rule that shows the wide one
above 48rem and the narrow one at or under it. 48rem because the kit's column
there is at least 672 px, where a 720-unit drawing still draws 12-unit
sublabels at 11 px. The rule lives HERE, not in `components.css`, only because
the kit is another phase's file; it is `SWAP_CSS` and moves there verbatim.

A wrapped `row` that fits the widest column in one row (`diagram_layout.one_row`)
adds a third svg, `dg-full`, first: the figure becomes a size container and
`full_css` shows it in place of `dg-wide` while the figure is at least its width.
A container query, not a media query, because the column's width depends on
the rail and the page cap, not on the viewport alone (BL-525).

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

# --- Excalidraw architect-mode values ---------------------------------------
# Read from github.com/excalidraw/excalidraw (master, 2026-09-29): "architect"
# is roughness 0 (`ROUGHNESS.architect`, constants.ts:470), so there is no
# wobble here, and colour stays the kit's classes. Excalidraw's numbers are in
# its canvas pixels with a 20 px default font; this drawing's label is FS
# (13 units), so every LENGTH is scaled by FS / EX_FONT_SIZE. Angles and
# ratios are not.
EX_FONT_SIZE = 20          # constants.ts:226 DEFAULT_FONT_SIZE
EX_STROKE_WIDTH = 2        # constants.ts:487 STROKE_WIDTH.medium, the default
                           # (DEFAULT_ELEMENT_STROKE_WIDTH_KEY, :515); thin 1,
                           # bold 4
EX_RADIUS_RATIO = 0.25     # constants.ts:446 DEFAULT_PROPORTIONAL_RADIUS; used
                           # while the short side is <= 128 (getCornerRadius,
                           # element/src/utils.ts:528), where the fixed 32 px
                           # (DEFAULT_ADAPTIVE_RADIUS, :448) takes over
EX_ADAPTIVE_RADIUS = 32    # constants.ts:448 DEFAULT_ADAPTIVE_RADIUS, the fixed
                           # radius past the cutoff (ROUNDNESS.ADAPTIVE_RADIUS,
                           # :465-466)
EX_ARROWHEAD_SIZE = 25     # element/src/bounds.ts:717 getArrowheadSize("arrow")
EX_ARROWHEAD_ANGLE = 20    # degrees, bounds.ts:738 getArrowheadAngle("arrow"):
                           # each arm leaves the tip this far off the shaft
EX_HEAD_MAX_FRACTION = 0.5  # bounds.ts:834 lengthMultiplier: a head is at most
                           # half the last segment (0.25 for a diamond)
# Not constants, only cited: opacity is constants.ts:533 (100) with
# backgroundColor "transparent" (:528), so a box is `fill="none"` and no opacity
# is emitted. BOUND_TEXT_PADDING is constants.ts:424 (5): NOT adopted, because
# it assumes text measured in the one font it is drawn in, and here
# `diagram_layout.PAD_X` (14) is also the margin the svg-text checker uses.
SCALE = dl.FS / EX_FONT_SIZE
HEAD_L = EX_ARROWHEAD_SIZE * SCALE     # 16.25
HEAD_A = math.radians(EX_ARROWHEAD_ANGLE)
STROKE = EX_STROKE_WIDTH * SCALE       # 1.3
# `graph_svg.py` still draws in the monospace stack and reads it from here.
# Byte-for-byte the `--mono` stack of `tokens.css`; the two are checked against
# each other by `test_diagram.py`, so this copy cannot drift silently.
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
SWAP_CSS = ("figure svg.dg-narrow{display:none}"
            "@media (max-width: 48rem){figure svg.dg-wide{display:none}"
            "figure svg.dg-narrow{display:block}}")


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
    """`M`, then `L` per leg of a polyline, or `Q` for a 3-point quadratic."""
    d = "M %s,%s" % (_num(points[0][0]), _num(points[0][1]))
    if len(points) != 3:
        for x, y in points[1:]:
            d += " L %s,%s" % (_num(x), _num(y))
    else:
        d += " Q %s,%s %s,%s" % (_num(points[1][0]), _num(points[1][1]),
                                 _num(points[2][0]), _num(points[2][1]))
    return d


def _last_len(points):
    """The length the head is measured against: the last straight leg, or for
    a quadratic (whose middle point is a CONTROL point, possibly a hair from
    the tip) the chord from its start to its tip."""
    tip = points[-1]
    ref = points[0] if len(points) == 3 else points[-2]
    return math.hypot(tip[0] - ref[0], tip[1] - ref[1])


def _corner(w, h):
    """Excalidraw's ADAPTIVE_RADIUS (constants.ts:459-466): 0.25 of the short
    side up to a cutoff of 32 / 0.25 = 128 px, then a fixed 32 px; both scaled
    by FS / EX_FONT_SIZE."""
    side = min(w, h)
    cutoff = EX_ADAPTIVE_RADIUS * SCALE / EX_RADIUS_RATIO
    return side * EX_RADIUS_RATIO if side <= cutoff else EX_ADAPTIVE_RADIUS * SCALE


def _head(x, y, angle, tone, seg):
    """Excalidraw's open arrowhead: two strokes from the tip, along `angle`.

    `seg` is the length of the arrow's last segment; the head is at most half
    of it, as Excalidraw scales a head down on a short segment. It is drawn
    BACKWARD from the tip, so it never reaches past the point the layout put
    it at and cannot push anything out of the viewBox.
    """
    size = min(HEAD_L, EX_HEAD_MAX_FRACTION * seg)
    back = angle + math.pi
    a = (x + size * math.cos(back - HEAD_A), y + size * math.sin(back - HEAD_A))
    b = (x + size * math.cos(back + HEAD_A), y + size * math.sin(back + HEAD_A))
    return ('  <path class="%s" d="M %s,%s L %s,%s L %s,%s" fill="none" '
            'stroke="currentColor" stroke-width="%s"/>'
            % (tone, _num(a[0]), _num(a[1]), _num(x), _num(y),
               _num(b[0]), _num(b[1]), _num(STROKE)))


def _lock(b):
    """The lock glyph of a locked box, from two primitives and no icon font:
    a filled body and an open shackle over it, in the box's own kit class."""
    x, y = b.lock_at
    w, h = dl.LOCK_W, dl.LOCK_H
    return ('  <g class="%s" fill="none" stroke="currentColor" '
            'stroke-width="%s"><rect x="%s" y="%s" width="%s" height="%s" '
            'rx="1.5" fill="currentColor"/><path d="M %s,%s L %s,%s A 3,3 0 0 1 '
            '%s,%s L %s,%s"/></g>'
            % (b.tone, _num(STROKE), _num(x), _num(y), _num(w), _num(h),
               _num(x + 2), _num(y), _num(x + 2), _num(y - 3),
               _num(x + w - 2), _num(y - 3), _num(x + w - 2), _num(y)))


def svg(lay, cls=""):
    """One `<svg>` element for a placed `diagram_layout.Layout`."""
    vx, vy, vw, vh = lay.view
    out = ['<svg%s viewBox="%s %s %s %s" xmlns="http://www.w3.org/2000/svg" '
           'role="img" style="font-family:var(--sans);max-width:%spx">'
           % (' class="%s"' % cls if cls else "", _num(vx), _num(vy),
              _num(vw), _num(vh), _num(vw * dl.MAX_SCALE))]

    if lay.divider:
        dx0, dy, dx1 = lay.divider
        out.append('  <line class="mut" x1="%s" y1="%s" x2="%s" y2="%s" '
                   'stroke="currentColor" stroke-opacity="0.5" '
                   'stroke-dasharray="4 4"/>'
                   % (_num(dx0), _num(dy), _num(dx1), _num(dy)))

    # A compare's frames, first, so bodies and arrows are painted over them.
    # The recommended panel is `acc` in its frame, title and outcome; the other
    # keeps a `mut` frame and plain text, so the accent means one thing.
    for p in lay.panels:
        fx, fy, fw, fh = p.frame
        tone = "acc" if p.recommended else "mut"
        tcls = ' class="acc"' if p.recommended else ""
        out.append('  <rect class="%s" x="%s" y="%s" width="%s" height="%s" '
                   'rx="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>'
                   % (tone, _num(fx), _num(fy), _num(fw), _num(fh),
                      _num(_corner(fw, fh)), _num(STROKE)))
        out.append('  <text%s x="%s" y="%s" font-size="%s" '
                   'fill="currentColor">%s</text>'
                   % (tcls, _num(p.title_at[0]), _num(p.title_at[1]),
                      _num(dl.FS), esc(p.title)))
        for text, tx, ty in p.outcome_lines:
            out.append('  <text%s x="%s" y="%s" font-size="%s" '
                       'fill="currentColor">%s</text>'
                       % (tcls, _num(tx), _num(ty), _num(dl.FS), esc(text)))

    for text, tx, ty in lay.titles:
        out.append('  <text class="mut" x="%s" y="%s" font-size="%s" '
                   'fill="currentColor">%s</text>'
                   % (_num(tx), _num(ty), _num(dl.TITLE_FS), esc(text)))

    # The arrows first, so a box is painted over the line that reaches it and
    # not under it. Both are `currentColor` on a transparent box, so the order
    # only shows where the head meets the border — which is every arrow.
    for r in lay.routes:
        out.append('  <path class="%s" d="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>' % (r.tone, _path(r.points),
                                            _num(STROKE)))
        tip = r.points[-1]
        out.append(_head(tip[0], tip[1], r.angle, r.tone, _last_len(r.points)))

    for b in lay.boxes:
        # A decision is a rounded box: its ends are half circles, of a
        # one- or two-line box's height at most, so a wrapped label in a tall
        # decision is not eaten by the curve.
        out.append('  <rect class="%s" x="%s" y="%s" width="%s" height="%s" '
                   'rx="%s" fill="none" stroke="currentColor" '
                   'stroke-width="%s"/>'
                   % (b.tone, _num(b.x), _num(b.y), _num(b.w), _num(b.h),
                      _num(min(b.h, dl.SUB_BOX_H) / 2.0 if b.decision
                           else _corner(b.w, b.h)), _num(STROKE)))
        # The label's lines, then the sublabel, as one block LINE_H apart and
        # centred on the box's middle; a lone line's baseline sits 0.35 em
        # below the middle, where a cap-height glyph reads as centred.
        # `check_artifact` measures a line from 0.8 em above its baseline to
        # 0.25 em below it (13.65 units at FS): every glyph box stays inside
        # the rect and apart from the next.
        rows = [(ln, dl.FS, "") for ln in b.lines]
        rows += [(sl, dl.SUB_FS, ' class="mut"') for sl in b.sub_lines]
        y = b.cy + 0.35 * dl.FS - (len(rows) - 1) * dl.LINE_H / 2.0
        for text, size, cls in rows:
            out.append('  <text%s x="%s" y="%s" text-anchor="middle" '
                       'font-size="%s" fill="currentColor">%s</text>'
                       % (cls, _num(b.cx + b.text_dx), _num(y), _num(size),
                          esc(text)))
            y += dl.LINE_H
        if b.lock_at:
            out.append(_lock(b))

    # A badge is drawn AFTER every box: its pill overlaps its box's top border
    # and is filled with the page ground (`style`, which resolves a custom
    # property where a presentation attribute does not) so the border does not
    # run through the text. Always `acc`: it marks who or what is attached here.
    for b in lay.boxes:
        if b.pill:
            px, py, pw, ph = b.pill
            # Inside a compare the accent is the recommended panel's alone.
            pt = ("acc" if not lay.panels or lay.panels[b.lane].recommended
                  else "mut")
            out.append('  <rect class="%s" x="%s" y="%s" width="%s" height="%s" '
                       'rx="%s" style="fill:var(--paper)" stroke="currentColor" '
                       'stroke-width="%s"/>'
                       % (pt, _num(px), _num(py), _num(pw), _num(ph),
                          _num(ph / 2.0), _num(STROKE)))
            # The lines are centred as one block, the way a box's are.
            y = py + ph / 2.0 + 0.35 * dl.SUB_FS - (
                len(b.badge_lines) - 1) * dl.BADGE_LINE / 2.0
            for text in b.badge_lines:
                out.append('  <text x="%s" y="%s" text-anchor="middle" '
                           'font-size="%s" fill="currentColor">%s</text>'
                           % (_num(px + pw / 2.0), _num(y), _num(dl.SUB_FS),
                              esc(text)))
                y += dl.BADGE_LINE

    out.append("</svg>")
    return "\n".join(out)


def full_css(width):
    """The rule that shows a `dg-full` drawing `width` wide instead of the
    wrapped one, only while the figure holds it at 1x (BL-525). The hide and
    the show both name the width's class, so they have equal specificity and
    the show, later in the rule, wins for ITS figure; another figure's hide
    (a different width class) can never match this one's drawing."""
    k = "dg-w%d" % width
    return ("figure svg.dg-full.%s{display:none}"
            "@container (min-width: %dpx){figure svg.dg-full.%s{display:block}"
            "figure svg.%s~svg.dg-wide{display:none}}" % (k, width, k, k))


def figure(lay, title="", classes="", ident="", narrow=None, full=None):
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
    if full is not None:
        # The figure is the container its own width is queried on.
        head += ' style="container-type:inline-size"'
    if narrow is None:
        out = [head + ">", svg(lay)]
    else:
        out = [head + ">", "<style>%s</style>" % SWAP_CSS,
               svg(lay, "dg-wide"), svg(narrow, "dg-narrow")]
    if full is not None:
        width = int(math.ceil(full.view[2] * dl.MAX_SCALE))
        out[1:1] = ["<style>%s</style>" % full_css(width),
                    svg(full, "dg-full dg-w%d" % width)]
    if title:
        out.append("<figcaption>%s</figcaption>" % esc(title))
    out.append("</figure>")
    return "\n".join(out)
