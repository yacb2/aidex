#!/usr/bin/env python3
"""The `::: chart` block: the data grammar, and the SVG it renders to.

Both halves of Phase 2 in one file, because they are one claim: a chart either
refuses its input with a line the author can find, or draws something true.
There is no third outcome, and a silently broken chart — a NaN bar the browser
paints as nothing, a ninth series wearing the first one's colour, a zero-height
division by zero — is the one this file is written against.

Four groups:

  PARSE — the body grammar. Both forms (`label,value` rows and a pipe table),
  and every malformed shape with the SPEC line it names. The line is the one
  INSIDE the fence, never the fence's own: the author edits the row.

  RENDER — the geometry that has a boundary in it. An empty set, one row, all
  zeros (the max-minus-min zero division), all-equal values, negatives, a value
  of exactly 0, one series against eight against nine. Each one is asserted to
  DO something stated, not merely to "not crash".

  COLOUR — only `--s1..--s8`, and zero literal hex anywhere in the emitted
  page. Asserted over the markup, not over the source of this file.

  SAFETY AND DETERMINISM — a hostile label cannot leave its attribute or open
  an element, and the same spec built twice is byte-identical.

Stdlib only, no runner: `python3 test_chart.py`, prints OK, exits 0.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

import chart_svg                                   # noqa: E402
from spec_build import SpecBuildError, build       # noqa: E402
from spec_parser import SpecSyntaxError            # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")
CHECK = os.path.join(SCRIPTS, "check-artifact.sh")
FIXTURE = os.path.join(HERE, "fixtures", "chart-sample.spec.md")

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
    """Assert `spec` is refused AT `line`, with `fragment` in the message.

    The line is asserted, not just the refusal: "it raised something" is what a
    green gate says about a chart that names the fence instead of the row, and
    the fence is not the line the author has to change.
    """
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


def svg_of(html):
    m = re.search(r"<svg\b.*?</svg>", html, re.S)
    return m.group(0) if m else ""


def rects(svg):
    return re.findall(r'<rect\b[^>]*>', svg)


def fnum(tag, attr):
    m = re.search(r'\b%s="([-\d.]+)"' % attr, tag)
    return float(m.group(1)) if m else None


tmp = tempfile.mkdtemp(prefix="chart-spec-")
try:
    print("== the data grammar: the two forms ==")
    html = holds("`label,value` rows build a one-series bar chart",
                 '::: chart {type=bar title="T"}\nuno,3\ndos,7\n:::',
                 "<figure>", "<svg ", 'fill="var(--s1)"',
                 ">uno<", ">dos<", "<figcaption>T</figcaption>")
    check("a one-series chart draws no legend",
          html.count('fill="var(--s1)"') == 2, html)

    html = holds("a pipe table builds a multi-series chart, names from the header",
                 '::: chart {type=bar}\n| R | Abiertas | Cerradas |\n'
                 '|---|---|---|\n| r1 | 8 | 2 |\n| r2 | 6 | 5 |\n:::',
                 'fill="var(--s1)"', 'fill="var(--s2)"',
                 ">Abiertas<", ">Cerradas<", ">r1<", ">r2<")
    check("the label column's own header is not drawn as a series",
          'var(--s3)' not in html and ">R<" not in html, html)

    holds("a separator row is skipped wherever it sits",
          '::: chart {type=bar}\n| R | A |\n|---|---|\n| r1 | 1 |\n'
          '|:--|--:|\n| r2 | 2 |\n:::', ">r1<", ">r2<")
    holds("blank lines in the body are ignored",
          '::: chart {type=bar}\n\nuno,3\n\ndos,7\n\n:::', ">uno<", ">dos<")
    holds("`type=` is the one spelling of the kind",
          '::: chart {type=line}\nuno,3\n:::', "<polyline")
    holds("a #id reaches the figure byte-exactly and is not a data-id",
          '::: chart {#c1 type=bar}\nuno,3\n:::', '<figure id="c1">')
    check("a chart is never given a data-id", "data-id" not in BUILT[-1][1],
          "data-id on a figure is how check_artifact recognises a consultation "
          "ITEM: the page then failed eight consult rules with no question in it")

    print()
    print("== the grammar's refusals, at the line INSIDE the fence ==")
    rejects("a CSV row with a trailing comma is a 3-field row",
            '::: chart {type=bar}\nuno,3\ndos,7,\n:::', 3, "3 comma-separated",
            SpecSyntaxError)
    rejects("a CSV row with no comma",
            '::: chart {type=bar}\nuno,3\nsolo\n:::', 3, "1 comma-separated",
            SpecSyntaxError)
    rejects("a label containing a comma is refused, not split",
            '::: chart {type=bar}\nGarcía, Ana,3\n:::', 2,
            "a label containing a comma", SpecSyntaxError)
    rejects("an empty label in a CSV row", '::: chart {type=bar}\n,7\n:::',
            2, "empty label", SpecSyntaxError)
    rejects("an empty label in a table row",
            '::: chart {type=bar}\n| R | A |\n|---|---|\n|  | 7 |\n:::',
            4, "empty label", SpecSyntaxError)
    rejects("a ragged table row names both counts",
            '::: chart {type=bar}\n| R | A | B |\n|---|---|---|\n| r1 | 1 |\n:::',
            4, "2 cells and the header has 3", SpecSyntaxError)
    rejects("a one-column table", '::: chart {type=bar}\n| solo |\n:::', 2,
            "at least 2 columns", SpecSyntaxError)
    rejects("a table whose first row is the separator",
            '::: chart {type=bar}\n|---|---|\n| r1 | 1 |\n:::', 2,
            "starts with its separator", SpecSyntaxError)
    rejects("a table with a header and no data rows",
            '::: chart {type=bar}\n| R | A |\n|---|---|\n:::', 2,
            "no data rows", SpecSyntaxError)
    rejects("mixing a table row into CSV rows",
            '::: chart {type=bar}\nuno,3\n| r2 | 7 |\n:::', 3,
            "one form per chart", SpecSyntaxError)
    rejects("mixing a CSV row into a table",
            '::: chart {type=bar}\n| R | A |\n|---|---|\n| r1 | 1 |\ndos,7\n:::',
            5, "one form per chart", SpecSyntaxError)
    rejects("a nested fence in a chart body",
            '::: chart {type=bar}\nuno,3\n::: note\nx\n:::\n:::', 3,
            "its body is data rows", SpecBuildError)

    print()
    print("== what counts as a number ==")
    for bad, line_frag in (("1e3", "no exponent"), ("NaN", "no bar to draw"),
                           ("inf", "no bar to draw"), ("-inf", "no bar to draw"),
                           ("0x10", "not a number"), ("1_000", "not a number"),
                           ("", "is empty"), ("--5", "not a number"),
                           ("7 8", "not a number")):
        rejects("a value of %r is refused" % bad,
                '::: chart {type=bar}\n| R | A |\n|---|---|\n| r1 | %s |\n:::'
                % bad, 4, line_frag, SpecSyntaxError)
    rejects("a decimal COMMA in a table cell says what to write instead",
            '::: chart {type=bar}\n| R | A |\n|---|---|\n| r1 | 1,5 |\n:::',
            4, "write `1.5`", SpecSyntaxError)
    # In the CSV form the decimal comma is not a bad value, it is an extra
    # field — and the field count is what the author sees. Both refuse; they
    # refuse with different sentences because they are different mistakes.
    rejects("a decimal comma in a CSV row is a field-count refusal",
            '::: chart {type=bar}\nuno,1,5\n:::', 2, "3 comma-separated",
            SpecSyntaxError)
    holds("the numbers that ARE accepted",
          '::: chart {type=bar}\n| R | A |\n|---|---|\n| a | 0 |\n'
          '| b | -3.5 |\n| c | +2 |\n| d | .5 |\n| e | 1000 |\n:::',
          "<rect")

    print()
    print("== the block's own refusals, at the FENCE's line ==")
    rejects("a chart with no kind", '::: chart\nuno,3\n:::', 1,
            "there is no default", SpecBuildError)
    rejects("an unknown kind", '::: chart {type=pie}\nuno,3\n:::', 1,
            "not one of: bar, line, stacked", SpecBuildError)
    rejects("the missing-kind refusal names every kind",
            '::: chart\nuno,3\n:::', 1, "type=\"stacked\"", SpecBuildError)
    rejects("`type` written twice on one fence",
            '::: chart {type=bar type=line}\nuno,3\n:::', 1,
            "appears twice", SpecSyntaxError)
    rejects("an empty chart body", '::: chart {type=bar}\n:::', 1,
            "no data rows", SpecBuildError)
    rejects("a whitespace-only chart body", '::: chart {type=bar}\n \n\n:::',
            1, "no data rows", SpecBuildError)
    rejects("an unknown attr", '::: chart {type=bar scale=log}\nuno,3\n:::',
            1, "takes no attr", SpecBuildError)

    print()
    print("== the scale: every boundary that could divide by zero ==")
    # ALL ZEROS. lo == hi == 0 is the max-minus-min division, and it is the one
    # that has to be named rather than discovered: the domain collapses to a
    # point and every bar is height 0 against a baseline that is also the top.
    html = holds("all-zero values draw zero-height bars, not a ZeroDivisionError",
                 '::: chart {type=bar}\na,0\nb,0\n:::', "<rect")
    heights = [fnum(r, "height") for r in rects(svg_of(html))]
    check("every bar of an all-zero chart has height 0", heights == [0.0, 0.0],
          str(heights))
    check("...and the axis still reads 0 at the baseline", ">0<" in html, html)
    # A value of exactly 0 next to a non-zero one: height 0 and NOT bumped to a
    # minimum, which would draw a bar for a measurement of nothing.
    html = holds("a value of exactly 0 beside a non-zero one",
                 '::: chart {type=bar}\na,0\nb,10\n:::', "<rect")
    heights = [fnum(r, "height") for r in rects(svg_of(html))]
    check("the zero bar is height 0 and the other is not",
          heights[0] == 0.0 and heights[1] > 0, str(heights))
    # ALL EQUAL, non-zero: 0 is forced into the domain, so hi > lo and the bars
    # are full height and identical — not an empty plot.
    html = holds("all-equal non-zero values", '::: chart {type=bar}\na,5\nb,5\n:::',
                 "<rect")
    heights = [fnum(r, "height") for r in rects(svg_of(html))]
    check("all-equal bars are equal and non-zero",
          heights[0] == heights[1] > 0, str(heights))
    # NEGATIVES. The domain reaches below zero and the bars hang from the zero
    # rule, which is drawn because otherwise a reader cannot see which side of
    # nothing a bar is on.
    html = holds("negative values", '::: chart {type=bar}\na,-4\nb,6\n:::',
                 "<rect")
    s = svg_of(html)
    check("a mixed-sign chart draws the zero rule",
          'stroke-opacity="0.45"' in s, s)
    check("the negative bar starts below the positive one",
          fnum(rects(s)[0], "y") > fnum(rects(s)[1], "y"), s)
    html = holds("all-negative values", '::: chart {type=bar}\na,-4\nb,-6\n:::',
                 "<rect")
    check("an all-negative chart has no zero rule to draw (0 is the top)",
          'stroke-opacity="0.45"' not in svg_of(html))
    # ONE ROW. The bar chart centres its single bar; the LINE chart's polyline
    # of one point renders nothing at all, which is why a dot is emitted for
    # every point.
    html = holds("a single row, bar", '::: chart {type=bar}\nsolo,3\n:::', "<rect")
    check("the single bar sits in the middle of the plot",
          abs((fnum(rects(svg_of(html))[0], "x")
               + fnum(rects(svg_of(html))[0], "width") / 2) - 384) < 1,
          svg_of(html))
    html = holds("a single row, line", '::: chart {type=line}\nsolo,3\n:::',
                 "<polyline", "<circle")
    pts = re.search(r'points="([^"]*)"', html).group(1)
    check("a one-point polyline is degenerate, so the point carries a dot",
          len(pts.split()) == 1 and html.count("<circle") == 1, pts)
    html = holds("a line chart of several points",
                 '::: chart {type=line}\na,1\nb,2\nc,3\n:::', "<polyline")
    check("the polyline carries one point per row",
          len(re.search(r'points="([^"]*)"', html).group(1).split()) == 3, html)

    print()
    print("== the series palette stops at --s8 ==")
    head = "| R | " + " | ".join("S%d" % i for i in range(1, 9)) + " |"
    sep = "|" + "---|" * 9
    row = "| r1 | " + " | ".join(str(i) for i in range(1, 9)) + " |"
    html = holds("eight series is the most a chart can wear",
                 "::: chart {type=bar}\n%s\n%s\n%s\n:::" % (head, sep, row),
                 *['fill="var(--s%d)"' % i for i in range(1, 9)])
    check("no ninth token is invented", "--s9" not in html and "--s0" not in html)
    head9 = "| R | " + " | ".join("S%d" % i for i in range(1, 10)) + " |"
    sep9 = "|" + "---|" * 10
    row9 = "| r1 | " + " | ".join(str(i) for i in range(1, 10)) + " |"
    # REFUSED, not cycled back onto --s1. tokens.css: "Past --s8 the answer is
    # to fold into 'other' or facet, not to invent a ninth hue." Two series in
    # one colour is a chart that lies where the reader cannot check it.
    rejects("a ninth series is refused at the header row, never cycled",
            "::: chart {type=bar}\n%s\n%s\n%s\n:::" % (head9, sep9, row9),
            2, "series tokens", SpecSyntaxError)

    print()
    print("== stacked: horizontal bars, one segment per series column ==")
    # Deterministic-figures Phase 3. A row is ONE bar; its segments are the
    # row's series values laid end to end, and the bar's length is the row's
    # total against the LONGEST row's total. So the scale is the totals', not
    # the cells', and that is why a negative cell is refused: a segment cannot
    # be laid end to end backwards.
    html = holds("one series column draws plain horizontal bars",
                 '::: chart {type=stacked title="T" unit=KB}\nuno,3\ndos,6\n:::',
                 "<svg ", ">uno<", ">dos<", ">3 KB<", ">6 KB<",
                 "<figcaption>T</figcaption>")
    s = svg_of(html)
    bars = rects(s)
    check("...one rect per row, all --s1, and no legend swatch",
          len(bars) == 2 and all('var(--s1)' in r for r in bars), s)
    check("...the longer row fills the plot and the shorter is half of it",
          abs(fnum(bars[0], "width") * 2 - fnum(bars[1], "width")) < 0.02
          and fnum(bars[0], "x") == fnum(bars[1], "x"), s)
    check("...a lone segment carries no value label of its own (the total says it)",
          s.count(">3<") == 0 and s.count(">6<") == 0, s)
    x_end = fnum(bars[1], "x") + fnum(bars[1], "width")
    tot = re.search(r'<text x="([-\d.]+)"[^>]*>6 KB<', s)
    check("...the total sits just past the end of its own bar",
          tot and 0 < float(tot.group(1)) - x_end <= 8, s)
    check("...the viewBox is the kit's width",
          re.search(r'viewBox="0 0 720 [\d.]+"', s) is not None, s)

    html = holds("a table draws one segment per series column, in order",
                 '::: chart {type=stacked}\n| R | A | B | C |\n|---|---|---|---|\n'
                 '| r1 | 5 | 3 | 2 |\n| r2 | 4 | 0 | 1 |\n:::',
                 'fill="var(--s1)"', 'fill="var(--s2)"', 'fill="var(--s3)"',
                 ">A<", ">B<", ">C<", ">10<", ">5<")
    s = svg_of(html)
    segs = [r for r in rects(s) if fnum(r, "height") > 12]
    check("...six segment rects (three per row), legend swatches apart",
          len(segs) == 6, s)
    r1 = segs[:3]
    check("...the segments of a row are contiguous, left to right",
          all(abs(fnum(r1[i], "x") + fnum(r1[i], "width") - fnum(r1[i + 1], "x"))
              < 0.02 for i in range(2)), s)
    check("...segment widths are proportional to the cells (5:3:2)",
          abs(fnum(r1[0], "width") / fnum(r1[2], "width") - 2.5) < 0.01
          and abs(fnum(r1[1], "width") / fnum(r1[2], "width") - 1.5) < 0.01, s)
    w1 = sum(fnum(r, "width") for r in r1)
    w2 = sum(fnum(r, "width") for r in segs[3:])
    check("...the row total is the scale: a total of 5 draws half of 10",
          abs(w1 - 2 * w2) < 0.05, "%s vs %s" % (w1, w2))
    check("...a ZERO cell is a zero-width segment, not a bumped one",
          fnum(segs[4], "width") == 0.0, segs[4])
    check("...a row with two or more segments labels each one that fits",
          ">3<" in s and ">2<" in s, s)
    check("...and never labels a zero segment", s.count(">0<") == 0, s)
    check("...a multi-series stacked chart draws its legend",
          s.count("height=\"10\"") == 3, s)

    html = holds("one row, one segment: the progress-bar boundary",
                 '::: chart {type=stacked}\nsolo,7\n:::', "<rect", ">7<")
    only = rects(svg_of(html))[0]
    check("...the single segment spans the whole plot width",
          fnum(only, "width") > 500, only)

    html = holds("an all-zero stacked chart draws, it does not divide by zero",
                 '::: chart {type=stacked}\n| R | A | B |\n|---|---|---|\n'
                 '| r1 | 0 | 0 |\n:::', ">0<")
    check("...every segment of it is zero-width",
          all(fnum(r, "width") == 0.0 for r in rects(svg_of(html))
              if fnum(r, "height") > 12), svg_of(html))

    html = holds("the viewBox grows with the rows, not a fixed plot height",
                 '::: chart {type=stacked}\na,1\nb,2\nc,3\nd,4\ne,5\nf,6\n:::',
                 "<rect")
    h6 = float(re.search(r'viewBox="0 0 720 ([\d.]+)"', html).group(1))
    html = holds("...(one row)", '::: chart {type=stacked}\na,1\n:::', "<rect")
    h1 = float(re.search(r'viewBox="0 0 720 ([\d.]+)"', html).group(1))
    check("...six rows are taller than one row", h6 > h1 * 2, "%s %s" % (h1, h6))

    rejects("a negative segment is refused at its row, naming the total scale",
            '::: chart {type=stacked}\n| R | A | B |\n|---|---|---|\n'
            '| r1 | 2 | 3 |\n| r2 | 4 | -1 |\n:::', 5, "total scale",
            SpecSyntaxError)
    rejects("...and in the `label,value` form too",
            '::: chart {type=stacked}\nuno,3\ndos,-2\n:::', 3, "total scale",
            SpecSyntaxError)
    holds("a negative value is still a legal BAR (the refusal is stacked's own)",
          '::: chart {type=bar}\nuno,3\ndos,-2\n:::', "<rect")
    head8 = "| R | " + " | ".join("S%d" % i for i in range(1, 9)) + " |"
    sep8 = "|" + "---|" * 9
    row8 = "| r1 | " + " | ".join(str(i) for i in range(1, 9)) + " |"
    holds("eight segments wear --s1..--s8",
          "::: chart {type=stacked}\n%s\n%s\n%s\n:::" % (head8, sep8, row8),
          *['fill="var(--s%d)"' % i for i in range(1, 9)])
    rejects("a ninth series column is refused for stacked too",
            "::: chart {type=stacked}\n%s\n%s\n%s\n:::" % (head9, sep9, row9),
            2, "series tokens", SpecSyntaxError)

    # The legend WRAPS: six long series names do not fit on one line at the
    # kit's width, and an unwrapped legend walks off the right of the viewBox.
    names = ["Reglas siempre activas", "Listado de skills",
             "CLAUDE.md del proyecto", "CLAUDE.md global", "RTK.md",
             "Nombres MCP"]
    html = holds("six long series names build",
                 "::: chart {type=stacked}\n| R | %s |\n|%s\n| antes | %s |\n:::"
                 % (" | ".join(names), "---|" * 7,
                    " | ".join(str(v) for v in (6194, 3068, 2621, 1578, 699, 48))),
                 ">Nombres MCP<", ">14208<")
    s = svg_of(html)
    lx = [(float(m.group(1)), m.group(2)) for m in re.finditer(
        r'<text x="([-\d.]+)" y="[-\d.]+" font-size="11" fill="currentColor">'
        r'([^<]*)</text>', s) if m.group(2) in names]
    check("...every legend label starts inside the viewBox",
          len(lx) == 6 and all(
              x + chart_svg._text_width(t, chart_svg.LEGEND_SIZE) <= 720
              for x, t in lx), str(lx))
    ys = set(re.findall(r'<rect x="[-\d.]+" y="([-\d.]+)" width="10" height="10"', s))
    check("...by wrapping onto a second legend line", len(ys) >= 2, str(ys))

    # F1 (review): a POSITIVE cell that rounds to 0 at two decimals is not a
    # number worth writing — "0" under a segment that is there is a lie.
    html = holds("cells below the two-decimal precision build",
                 '::: chart {type=stacked}\n| R | A | B |\n|---|---|---|\n'
                 '| r1 | 0.004 | 0.004 |\n:::', ">0.01<")
    check("...and no segment is labelled 0", '>0<' not in svg_of(html),
          svg_of(html))
    html = holds("a tiny cell beside a real one",
                 '::: chart {type=stacked}\n| R | A | B |\n|---|---|---|\n'
                 '| r1 | 0.004 | 5 |\n:::', "<rect")
    check("...labels neither: the real one is alone, its value is the total",
          '>0<' not in svg_of(html)
          and 'font-size="10"' not in svg_of(html),
          svg_of(html))

    # The case where a sub-precision segment is WIDE: every cell is tiny, so
    # 0.004 of a 0.024 total is ~100 px and "0" would fit under it.
    html = holds("a sub-precision cell wide enough to hold a label",
                 '::: chart {type=stacked}\n| R | A | B | C |\n|---|---|---|---|\n'
                 '| r1 | 0.004 | 0.01 | 0.01 |\n:::', ">0.01<")
    check("...labels the two printable segments and not the tiny one as 0",
          '>0<' not in svg_of(html), svg_of(html))

    # F2 (review): the totals' text is reserved out of the plot width, so a
    # long enough unit left a NEGATIVE plot and negative rect widths, with no
    # error. Refused at the fence, with the reason.
    rejects("a unit that leaves no room for the bars is refused",
            '::: chart {type=stacked unit="%s"}\nuno,3\n:::' % ("u" * 120),
            1, "room for the bars", SpecBuildError)
    try:
        chart_svg.svg("stacked", ["uno"], [("", [3.0])], "u" * 120)
        fail("svg() drew a stacked chart with no room for its bars")
    except ValueError:
        ok("svg() called directly refuses the same chart (ValueError)")
    html = holds("a unit that still leaves room builds",
                 '::: chart {type=stacked unit="%s"}\nuno,3\n:::' % ("u" * 20),
                 "<rect")
    check("...with every rect width >= 0",
          all(fnum(r, "width") >= 0 for r in rects(svg_of(html))),
          svg_of(html))

    # F4 (review): the legend's wrap boundary, asserted on `_legend` itself.
    two = [("Alfa", [1]), ("Beta", [1])]
    step = lambda n: (chart_svg.LEGEND_SWATCH + 5
                      + chart_svg._text_width(n, chart_svg.LEGEND_SIZE))
    exact = 16.0 + step("Alfa") + 18 + step("Beta")
    _out, rows = chart_svg._legend(two, 16.0, exact)
    check("a second entry ending EXACTLY at x1 stays on the first line",
          rows == 1, str(rows))
    _out, rows = chart_svg._legend(two, 16.0, exact - 0.01)
    check("...and one hundredth of a pixel less wraps it", rows == 2, str(rows))
    huge = [("W" * 200, [1]), ("b", [1])]
    out, rows = chart_svg._legend(huge, 16.0, 704.0)
    check("a lone first entry wider than the plot starts at x0 on row 1",
          out and 'x="16" y="%s"' % chart_svg._num(chart_svg.PAD_T) in out[0],
          out[0] if out else "no legend")
    check("...and the entry after it wraps to row 2", rows == 2, str(rows))

    print()
    print("== bar and line are untouched by the stacked kind ==")
    # A one-line legend is the same bytes it was before the legend learned to
    # wrap: the top of the plot must not move for a chart that never wraps.
    html = holds("a two-series bar chart keeps its legend on one line",
                 '::: chart {type=bar}\n| R | A | B |\n|---|---|---|\n'
                 '| r1 | 1 | 2 |\n:::', ">A<")
    check("...and its plot starts where it did (PAD_T + one LEGEND_H)",
          '<rect x="64" y="16" width="10" height="10"' in html
          and 'y1="40"' in html, svg_of(html))

    print()
    print("== colour comes only from the kit's tokens ==")
    page = "\n".join(html for _label, html in BUILT)
    hexes = re.findall(r'#[0-9a-fA-F]{3,8}\b', page)
    check("zero literal hex colours in everything built here (%d pages)"
          % len(BUILT), not hexes, str(sorted(set(hexes))))
    for kw in ("rgb(", "hsl(", "red", "blue"):
        check("no %r colour literal in a chart" % kw,
              kw not in "\n".join(svg_of(h) for _l, h in BUILT))
    tokens = set(re.findall(r'var\((--[a-z0-9-]+)\)',
                            "\n".join(svg_of(h) for _l, h in BUILT)))
    check("every var() in a chart is a series token --s1..--s8",
          tokens and tokens <= set(chart_svg.SERIES_TOKENS), str(sorted(tokens)))
    check("the emitter's source carries no hex colour either",
          not re.findall(r'#[0-9a-fA-F]{3,8}\b',
                         open(os.path.join(SCRIPTS, "chart_svg.py"),
                              encoding="utf-8").read()))

    print()
    print("== a hostile label cannot inject markup ==")
    # No `"` in the ATTR values: the attr grammar has no escapes and refuses a
    # quote inside a quoted value (03-spec-grammar.md § Values and quoting), so
    # a hostile title arrives quote-free. The hostile ROW cells carry the
    # quotes, which is where a label actually comes from.
    HOSTILE = "<img src=x onerror=alert(1)>"
    ROW = '<img src=x onerror="alert(1)">'
    html = holds("a label full of markup is escaped, not executed",
                 '::: chart {type=bar title="%s" unit="%s"}\n| %s | %s |\n'
                 '|---|---|\n| %s | 3 |\n:::'
                 % (HOSTILE, HOSTILE, HOSTILE, HOSTILE, ROW),
                 "&lt;img")
    check("no <img element reaches the page", "<img" not in html, html)
    # `onerror` appears in the page as TEXT — that is the point, the label said
    # so. What must not exist is an onerror ATTRIBUTE, i.e. the word inside a
    # real tag rather than between `&lt;` and `&gt;`.
    in_tags = " ".join(re.findall(r"<[^>]*>", html))
    check("no onerror ATTRIBUTE reaches the page (the word as text is fine)",
          "onerror" not in in_tags, in_tags)
    check("the quote inside the label is escaped", '"alert(1)"' not in html, html)
    check("the hostile TITLE is escaped in the figcaption too",
          "<figcaption>&lt;img src=x onerror=alert(1)&gt;</figcaption>" in html,
          html)
    check("the hostile UNIT is escaped in the tick text",
          "&lt;img" in html and "<img" not in html, html)
    # The attribute-breakout shape, separately: a label that is nothing but a
    # quote and a handler. `>` matters as much as `<` — a label ending the tag
    # early is how the next word becomes markup.
    html = holds("a quote-and-angle label cannot leave its element",
                 '::: chart {type=bar}\n| R | A |\n|---|---|\n'
                 '| "\'/><script>x</script> | 1 |\n:::', "&lt;script&gt;")
    check("no <script> reaches the page", "<script" not in html, html)
    svg = svg_of(html)
    check("the SVG's own tags are still well formed (every < opens a known tag)",
          not re.findall(r'<(?!/?(?:svg|line|text|rect|polyline|circle)\b)', svg),
          svg)
    holds("an ampersand in a label is escaped once, not twice",
          '::: chart {type=bar}\nA & B,3\n:::', ">A &amp; B<")
    check("an escaped ampersand is not double-escaped",
          "&amp;amp;" not in BUILT[-1][1], BUILT[-1][1])

    print()
    print("== the same chart built twice is byte-identical ==")
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
    out = os.path.join(tmp, "chart-sample.html")
    r = subprocess.run([sys.executable, BUILD, FIXTURE, "-o", out, "--check"],
                       capture_output=True, text=True)
    check("spec_build.py -o --check exits 0 on the chart fixture",
          r.returncode == 0, r.stdout + r.stderr)
    r = subprocess.run(["bash", CHECK, out], capture_output=True, text=True)
    check("check-artifact.sh passes the built page on its own",
          r.returncode == 0, r.stdout + r.stderr)
    page = open(out, encoding="utf-8").read()
    check("the page carries both charts", page.count("<svg ") == 2, page[:200])
    check("...and the kit", "artifact-kit" in page)
    # The one warning this page does carry is the "nothing could be measured"
    # note, and it is NOT a defect to clear: `currentColor` is what the canon
    # prescribes for figure text (it follows the theme), and the contrast check
    # says so itself — "failing on it would fail every page built the
    # recommended way". Any OTHER warning on this page is a real finding.
    said = r.stdout + r.stderr
    others = [ln for ln in said.splitlines()
              if "WARN" in ln and "no figure text could be measured" not in ln]
    check("no warning but the documented currentColor one", not others,
          "\n".join(others))

    stacked_fx = os.path.join(HERE, "fixtures", "chart-stacked.spec.md")
    out2 = os.path.join(tmp, "chart-stacked.html")
    r = subprocess.run([sys.executable, BUILD, stacked_fx, "-o", out2, "--check"],
                       capture_output=True, text=True)
    check("spec_build.py -o --check exits 0 on the stacked fixture",
          r.returncode == 0, r.stdout + r.stderr)
    r = subprocess.run(["bash", CHECK, out2], capture_output=True, text=True)
    check("check-artifact.sh passes the stacked page on its own",
          r.returncode == 0, r.stdout + r.stderr)
    said = r.stdout + r.stderr
    others = [ln for ln in said.splitlines()
              if "WARN" in ln and "no figure text could be measured" not in ln]
    check("...with no svg-text warning: no label overlaps, none leaves the "
          "viewBox or its segment", not others, "\n".join(others))
    stacked_page = open(out2, encoding="utf-8").read()
    check("the stacked page carries its three charts",
          stacked_page.count("<svg ") == 3, stacked_page[:200])
    BUILT.append(("the wrapped stacked page", stacked_page))

    print()
    print("== what the contract cannot see ==")
    BUILT.append(("the wrapped fixture page", page))
    dirty = [label for label, h in BUILT if "\x00" in h]
    check("every page built here holds zero \\x00 bytes (%d pages)" % len(BUILT),
          not dirty, "NUL in: %r" % dirty)
    # `build()` raises its two documented types and nothing else. A ValueError
    # or a ZeroDivisionError out of the renderer is uncatchable by every caller
    # that handles the spec exceptions — which is all of them.
    for label, spec in (
            ("all zeros", '::: chart {type=bar}\na,0\n:::'),
            ("one row, line", '::: chart {type=line}\na,0\n:::'),
            ("huge values", '::: chart {type=bar}\na,999999999\nb,0.01\n:::'),
            ("a lone minus sign", '::: chart {type=bar}\na,-\n:::'),
            ("a body of only a separator", '::: chart {type=bar}\n|---|---|\n:::')):
        try:
            build(spec)
            ok("%s: built" % label)
        except (SpecSyntaxError, SpecBuildError) as exc:
            ok("%s: refused at line %d" % (label, exc.line))
        except Exception as exc:                    # noqa: BLE001
            fail("%s: raised %s, which no caller catches (%s)"
                 % (label, type(exc).__name__, exc))

    print()
    print("== every chart kind is documented where an author looks ==")
    # A kind added to KINDS and not to the references is a construct no agent
    # knows how to write; the block-type lockstep (test_lockstep.py) cannot
    # see it, because it compares block TYPES, not a block's `type=` values.
    refs = os.path.join(SKILL, "references")
    vocab = open(os.path.join(refs, "04-block-vocabulary.md"),
                 encoding="utf-8").read()
    row = next((ln for ln in vocab.splitlines() if ln.startswith("| `chart` |")),
               "")
    grammar = open(os.path.join(refs, "03-spec-grammar.md"),
                   encoding="utf-8").read()
    local = open(os.path.join(refs, "02-local-first-artifacts.md"),
                 encoding="utf-8").read()
    said = re.search(r"`type` is required and is ([^.]*)", local)
    for kind in chart_svg.KINDS:
        check("chart kind `%s` is in 04-block-vocabulary.md's `chart` row" % kind,
              "`%s`" % kind in row, row)
        check("...and in 02-local-first-artifacts.md's `type` sentence",
              said is not None and "`%s`" % kind in said.group(1),
              said.group(0) if said else "no `type` sentence")
        check("...and in 03-spec-grammar.md § The `chart` body",
              "type=%s" % kind in grammar, kind)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

print()
if failures:
    print("%d failure(s)" % len(failures))
    raise SystemExit(1)
print("OK — the chart block: both body forms, every malformed row refused at "
      "its own line inside the fence, the block's refusals at the fence line, "
      "the numeric rule (no exponent, no NaN, no decimal comma), the scale's "
      "zero-division and sign boundaries, one row against eight series against "
      "a refused ninth, only --s1..--s8 and zero literal hex, a hostile label "
      "escaped, a byte-identical rebuild across processes, the fixture "
      "page through check-artifact.sh, the stacked kind (contiguous segments "
      "on the total scale, one segment, a zero cell, all zeros, a refused "
      "negative, the 8-series cap, a wrapping legend, its fixture through "
      "check-artifact.sh) and every kind documented")
