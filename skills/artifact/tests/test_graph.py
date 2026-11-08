#!/usr/bin/env python3
"""The `::: graph` block: DOT in, a kit-themed Graphviz SVG out (Phase 5).

Four groups:

  WITHOUT GRAPHVIZ — a spec with a `graph` block and no `dot` on PATH fails at
  the fence's line with the install line, and `spec_build.py -o` writes
  nothing. Runs on every machine: PATH is rebuilt without any `dot`.

  THE FENCE — an empty body and an unknown attr are refused at the fence's
  line before Graphviz is ever called.

  WITH GRAPHVIZ (SKIP with a printed line when `dot` is absent) — the class
  attribute really reaches the SVG; no literal colour, no id, no <title>, no
  identity transform; every label is currentColor; a literal colour, an
  unknown class, a link and a DOT syntax error are refused with the spec line;
  the same spec builds byte-identical twice and across processes; the wrapped
  page passes check-artifact with zero svg-text findings.

  THE LABELS — `graph_svg.labels` returns node and cluster text (multi-line
  joined, entities unescaped) and never edge labels: it is what the goal gate
  compares against the census (review finding F2).

Stdlib only: `python3 test_graph.py`, prints OK, exits 0.
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

import check_artifact                               # noqa: E402
import graph_svg                                    # noqa: E402
from spec_build import SpecBuildError, build        # noqa: E402
from spec_parser import SpecSyntaxError             # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")
failures = []


def check(label, cond, detail=""):
    if cond:
        print("  ok: " + label)
    else:
        failures.append(label)
        print("FAIL: %s%s" % (label, (": " + detail) if detail else ""))


def rejects(label, spec, line, fragment):
    try:
        build(spec)
    except (SpecSyntaxError, SpecBuildError) as exc:
        check(label, exc.line == line and fragment in exc.message,
              "line %d: %s (wanted line %d with %r)"
              % (exc.line, exc.message, line, fragment))
        return
    except Exception as exc:                        # a traceback, not a refusal
        check(label, False, "raised %s: %s" % (type(exc).__name__, exc))
        return
    check(label, False, "built a spec that should have been refused")


def fence(*body, attrs='title="Un grafo"'):
    return "Antes.\n\n::: graph {%s}\n%s\n:::\n" % (attrs, "\n".join(body))


GOOD = fence(
    "digraph {",
    "  rankdir=LR;",
    "  node [shape=box];",
    '  a [label="Primero"];',
    '  b [label="Segundo" class=acc];',
    '  c [label="Tercero\\nsegunda línea" class=mut];',
    '  subgraph cluster_x { label="Grupo & <cosa>"; c; }',
    '  a -> b [label="etiqueta de arista"];',
    "  b -> c [style=dashed class=flg];",
    "}")
SPEC_PAGE = ('::: masthead {title="Grafo sintético" visual="svg"}\n'
             "Una página con un grafo.\n:::\n\n" + GOOD)


# --- without Graphviz --------------------------------------------------------
print("== without dot on PATH ==")
nodot = [d for d in os.environ.get("PATH", "").split(os.pathsep)
         if d and not os.path.exists(os.path.join(d, "dot"))]
tmp = tempfile.mkdtemp(prefix="test-graph-")
try:
    spec = os.path.join(tmp, "p.spec.md")
    with open(spec, "w", encoding="utf-8") as fh:
        fh.write(SPEC_PAGE)
    out = os.path.join(tmp, "p.html")
    env = dict(os.environ, PATH=os.pathsep.join(nodot))
    r = subprocess.run([sys.executable, BUILD, spec, "-o", out], env=env,
                       capture_output=True, text=True)
    fence_line = SPEC_PAGE.split("\n").index('::: graph {title="Un grafo"}') + 1
    check("no dot: the build fails", r.returncode == 1,
          "exit %d" % r.returncode)
    check("no dot: the message names the fence's line",
          ":%d:" % fence_line in r.stderr, r.stderr)
    check("no dot: the message carries both install lines",
          "brew install graphviz" in r.stderr
          and "apt install graphviz" in r.stderr, r.stderr)
    check("no dot: nothing is written", not os.path.exists(out),
          "%s exists" % out)
finally:
    shutil.rmtree(tmp, ignore_errors=True)

# --- the fence, before Graphviz ----------------------------------------------
print("== the fence ==")
rejects("an empty body is refused at the fence", fence(""), 3, "no body")
rejects("an unknown attr is refused at the fence",
        fence("digraph { a }", attrs='shape=row'), 3, "takes no attr 'shape'")

# --- with Graphviz -----------------------------------------------------------
if not graph_svg.dot_path():
    print("SKIP the Graphviz cases: no `dot` on PATH (%s)" % graph_svg.INSTALL)
else:
    print("== with Graphviz ==")
    html = build(GOOD)
    svg = re.search(r"<svg\b.*?</svg>", html, re.S).group(0)
    check("one <figure>, one <svg>, one caption",
          html.count("<figure") == 1 and html.count("<svg") == 1
          and "<figcaption>Un grafo</figcaption>" in html, html)
    root = svg.split(">", 1)[0]
    ratio = (float(re.search(r"max-width:([\d.]+)px", root).group(1))
             / float(re.search(r'viewBox="\S+ \S+ (\S+) \S+"', root).group(1)))
    check("a graph is shown at most 1.2x its viewBox width, its own cap (BL-513; "
          "the diagram's is 1x) (%.3f)" % ratio, abs(ratio - 1.2) < 0.001)
    check("the Graphviz version is in the figure's comment",
          re.search(r"<!-- graph: graphviz \S+ -->", html) is not None)
    check("DOT's class= reaches the SVG (node acc, node mut, edge flg)",
          'class="node acc"' in svg and 'class="node mut"' in svg
          and 'class="edge flg"' in svg, svg)
    check("no literal colour: fill/stroke are none or currentColor only",
          set(re.findall(r'\b(?:fill|stroke)="([^"]*)"', svg))
          <= {"none", "currentColor"},
          str(set(re.findall(r'\b(?:fill|stroke)="([^"]*)"', svg))))
    check("no hex, rgb( or var( anywhere in the figure",
          not re.search(r"#[0-9a-fA-F]{3,6}\b|rgb\(|var\(", svg))
    check("every <text> is painted currentColor",
          all('fill="currentColor"' in t
              for t in re.findall(r"<text\b[^>]*>", svg)))
    check("no id=, no <title>, no identity transform, no width/height",
          " id=" not in svg and "<title>" not in svg and "scale(" not in svg
          and not re.search(r"<svg[^>]*\b(width|height)=", svg), svg[:300])
    check("the labels are drawn in the kit's --mono stack",
          'font-family="monospace"' not in svg and "ui-monospace" in svg)
    check("a label is escaped once, not passed through",
          "Grupo &amp; &lt;cosa&gt;" in svg, svg)
    check("svg-text: zero findings on the built figure",
          check_artifact.svg_text_findings(html) == [],
          str(check_artifact.svg_text_findings(html)))

    # Refusals Graphviz's output triggers, each at the fence's line (3).
    rejects("a literal colour is refused",
            fence('digraph { a [color=red] }'), 3, 'stroke="red"')
    rejects("a fill colour is refused",
            fence('digraph { a [style=filled fillcolor="#ff0000"] }'), 3,
            "colour")
    rejects("an unknown class is refused",
            fence('digraph { a [class="acc consult-item"] }'), 3,
            "'consult-item' is not a kit class")
    rejects("a link is refused", fence('digraph { a [URL="https://x.y"] }'),
            3, "link")
    rejects("a DOT syntax error carries Graphviz's message and the spec line",
            fence("digraph {", "  a -> ;", "}"), 3, "(spec line 5)")

    # Review finding 1: Graphviz does not escape `"` inside fontname, so a
    # DOT can write markup into the SVG. Refused structurally, never passed.
    rejects("a fontname that smuggles a <script> element is refused",
            fence(r'digraph{a[fontname="x\"/><script>alert(1)</script>'
                  r'<text x=\"0"]}'), 3, "`graph`:")
    try:
        build(fence(r'digraph{a[fontname="x\"/><script>alert(1)</script>'
                    r'<text x=\"0"]}'))
    except SpecBuildError as exc:
        check("the <script> refusal names the element",
              "<script>" in exc.message, exc.message)
    rejects("a fontname that smuggles an onclick attribute is refused",
            fence(r'digraph{a->b[fontname="x\" onclick=\"alert(1)" '
                  r'label="e"]}'), 3, "`graph`:")
    try:
        build(fence(r'digraph{a->b[fontname="x\" onclick=\"alert(1)" '
                    r'label="e"]}'))
    except SpecBuildError as exc:
        check("the onclick refusal names the attribute",
              "onclick" in exc.message, exc.message)
    rejects("a font other than the kit's --mono is refused",
            fence('digraph { a [fontname="Helvetica"] }'), 3, "font")

    # BL-722 B-c22: label TEXT that reads like markup is not markup. The raw
    # substring test for ` style=` refused `style=bold` typed in a label.
    try:
        label_html = build(fence('digraph { a [label="use style=bold"] }'))
        check("a label that says style=bold is not refused",
              "use style=bold" in label_html, label_html)
    except (SpecSyntaxError, SpecBuildError) as exc:
        check("a label that says style=bold is not refused", False,
              exc.message)
    # ...while a style= ATTRIBUTE smuggled through fontname stays refused (by
    # the parsed whitelist, now the only check).
    rejects("a fontname that smuggles a style= attribute is refused",
            fence(r'digraph{a->b[fontname="x\" style=\"fill:red" '
                  r'label="e"]}'), 3, "style")

    # BL-451, found by a headless-Chrome probe: the whitelist ran on
    # ElementTree's parse but the page carried Graphviz's own bytes. XML reads
    # `<?x ><script>…?>` as ONE processing instruction (dropped by the parse);
    # HTML reads `<?x >` as a bogus comment and then runs the <script>. A
    # single-quoted attribute slipped past the class= and colour regexes.
    for what, payload in (
            ("script", "<script>document.title=1</script>"),
            ("style", "<style>body{display:none}</style>")):
        rejects("a processing instruction hiding a <%s> is refused" % what,
                fence(r'digraph{a[fontname="monospace\"/><?x >%s?><text '
                      r'font-family=\"monospace"]}' % payload), 3,
                "processing instruction")
    rejects("a single-quoted class= is refused like a double-quoted one",
            fence(r'''digraph{a[fontname="monospace\" class='consult-item' '''
                  r'''role=\"x"]}'''), 3, "'consult-item' is not a kit class")
    rejects("a single-quoted colour is refused like a double-quoted one",
            fence(r'''digraph{a[fontname="monospace\" stroke='red' '''
                  r'''role=\"x"]}'''), 3, 'stroke="red"')

    # BL-905: `fixedsize` keeps a box at width x height whatever its label, and
    # Graphviz measures generic monospace while the page draws the kit's wider
    # --mono stack, so the label ran past the box. The DOT a delegate shipped:
    BL905 = fence(
        "digraph {",
        "  node [shape=box width=2.6 height=0.9 fixedsize=true];",
        '  n1 [label="1. Landing de Framer\\ncookie gd_referral"];',
        '  n2 [label="2. App de onboarding\\nenvía tracking_data"];',
        '  n3 [label="3. Filtro del backend\\nhoy: aquí se pierden" class=flg];',
        '  n4 [label="4. Token del enlace\\nmágico"];',
        '  n5 [label="5. Seed al crear\\nel onboarding"];',
        '  n6 [label="6. Salidas\\nadmin y BigQuery"];',
        "  {rank=same; n1; n2; n3}",
        "  {rank=same; n4; n5; n6}",
        "  n1 -> n2 -> n3;",
        "  n4 -> n5 -> n6;",
        "  n3 -> n4 [constraint=true];",
        "}")
    rejects("BL-905: the shipped fixedsize DOT is refused, naming fixedsize",
            BL905, 3, "fixedsize")
    rejects("BL-905: the refusal names the row diagram for a linear flow",
            BL905, 3, "::: diagram shape=row")
    # Every spelling Graphviz reads as on (its mapbool, plus the literal
    # `shape`), at every level it can be written; read from Graphviz's own parse.
    for body in ("node [fixedsize=TRUE]; a", 'node ["fixedsize"=yes]; a',
                 "a [fixedsize=1]", "a [fixedsize=01]", "a [fixedsize=shape]",
                 "fixedsize=true; a", "edge [fixedsize=true]; a -> b",
                 "subgraph s { node [fixedsize=true]; a }",
                 # a graph attribute named like json0's own keys hides no node
                 'edges="x"; a [fixedsize=true]', 'objects="y"; a [fixedsize=true]'):
        rejects("fixedsize on is refused: %s" % body,
                fence("digraph { %s }" % body), 3, "fixedsize")
    # ...and every spelling Graphviz reads as off builds (`Shape` is not
    # `shape`: Graphviz compares that one case-sensitively).
    for body in ("node [fixedsize=false]; a", "a [fixedsize=no]",
                 "a [fixedsize=0]", 'a [fixedsize=""]', "a [fixedsize=Shape]",
                 "node [fixedsize=true]; a [fixedsize=false]"):
        try:
            build(fence("digraph { %s }" % body))
            check("fixedsize off builds: %s" % body, True)
        except (SpecSyntaxError, SpecBuildError) as exc:
            check("fixedsize off builds: %s" % body, False, exc.message)
    # An HTML label's <TABLE>/<TD> takes FIXEDSIZE too, inside the label
    # string; Graphviz reads only "true" (any case, either quote) as on.
    for body in ('a [shape=plain label=<<table><tr><td fixedsize="true" '
                 'width="40" height="20">una etiqueta larga</td></tr></table>>]',
                 "a [shape=plain label=<<TABLE FIXEDSIZE = 'TRUE' WIDTH='20'>"
                 "<TR><TD>x</TD></TR></TABLE>>]",
                 'a -> b [label=<<table><tr><td fixedsize="True">x</td></tr>'
                 '</table>>]'):
        rejects("an HTML label's fixedsize=\"true\" is refused: %s" % body,
                fence("digraph { %s }" % body), 3, "fixedsize")
    for body in ('a [shape=plain label=<<table><tr><td fixedsize="false">x'
                 '</td></tr></table>>]',
                 'a [shape=plain label=<<table><tr><td fixedsize="1">x'
                 '</td></tr></table>>]',
                 'a [shape=plain label=<<table><tr><td fixedsize="truex">x'
                 '</td></tr></table>>]'):
        try:
            build(fence("digraph { %s }" % body))
            check("an HTML fixedsize Graphviz reads as off builds: %s" % body,
                  True)
        except (SpecSyntaxError, SpecBuildError) as exc:
            check("an HTML fixedsize Graphviz reads as off builds: %s" % body,
                  False, exc.message)
    # Graphviz writes a raw control character of a label into its JSON as is:
    # still refused by name (the SVG check), never a JSONDecodeError.
    rejects("a control character in a label is refused by name",
            fence('digraph { a [label="x\x01y"] }'), 3,
            "not well-formed SVG")

    # BL-905: Graphviz's default nodesep (0.25 in) left ~10 px between boxes.
    # A separation under 0.44 in (the diagram engine's 32 px GAP) is refused
    # when the DOT sets it; an unset nodesep gets 0.44 (ranksep's own default,
    # 0.5, is already above it).
    for body in ("nodesep=0.43", "nodesep=0.25", "ranksep=0.43",
                 'ranksep="0.3 equally"', "nodesep=abc", 'nodesep=" "',
                 'ranksep="4e-1"', "nodesep=nan"):
        rejects("a separation under 0.44 in is refused: %s" % body,
                fence("digraph { %s; a -> b }" % body), 3, "0.44")
    # An empty nodesep is no value: Graphviz leaves it out of its parse, so it
    # gets the 0.44 floor like an unset one.
    for body in ("nodesep=0.44", "ranksep=0.44", 'ranksep="0.5 equally"',
                 "nodesep=1 ranksep=2", 'nodesep=""'):
        try:
            build(fence("digraph { %s; a -> b }" % body))
            check("a separation of 0.44 in or more builds: %s" % body, True)
        except (SpecSyntaxError, SpecBuildError) as exc:
            check("a separation of 0.44 in or more builds: %s" % body, False,
                  exc.message)
    # The floor is dot's: neato, circo, fdp, osage and patchwork ignore nodesep
    # and ranksep and place boxes touching or overlapping, so a root `layout=`
    # other than dot is refused. Graphviz itself refuses a wrong case (`Dot`);
    # a node's `layout` is ignored and dot lays the graph out.
    for body in ("layout=neato; a -> b", "graph [layout=patchwork]; a; b",
                 "layout=circo; a -> b"):
        rejects("a layout engine other than dot is refused: %s" % body,
                fence("digraph { %s }" % body), 3, "layout=")
    rejects("a wrong-case engine is Graphviz's own refusal: layout=Dot",
            fence("digraph { layout=Dot; a -> b }"), 3, "Layout type")
    # Packing has dot lay out each unconnected part alone and set the parts
    # `pack` points apart (8 by default, `pack=false` included): refused at any
    # value on the root graph, where dot reads it; a subgraph's pack is ignored.
    for body in ("pack=0; a; b", "pack=false; a; b", 'packmode="array"; a; b',
                 "graph [pack=40]; a; b"):
        rejects("packing is refused: %s" % body,
                fence("digraph { %s }" % body), 3, "pack")
    for body in ("layout=dot; a -> b", "node [layout=neato]; a -> b",
                 "layout=neato; layout=dot; a -> b",
                 "subgraph s { pack=0; a; b }"):
        try:
            build(fence("digraph { %s }" % body))
            check("a graph dot lays out builds: %s" % body, True)
        except (SpecSyntaxError, SpecBuildError) as exc:
            check("a graph dot lays out builds: %s" % body, False, exc.message)
    # json0 writes graph attributes beside its own `objects` and `edges` keys:
    # a graph attribute of that name, with no node or edge to shadow it, is a
    # string there, never a traceback.
    for body in ('edges="x"; a', 'objects="y"'):
        try:
            build(fence("digraph { %s }" % body))
            check("a graph attribute named like a json0 key builds: %s" % body, True)
        except Exception as exc:
            check("a graph attribute named like a json0 key builds: %s" % body,
                  False, "%s: %s" % (type(exc).__name__, exc))
    pair = build(fence("digraph { node [shape=box]; {rank=same; a; b} }"))
    xs = sorted(float(x) for x in re.findall(r'points="([\d.-]+),', pair))
    check("an unset nodesep leaves 0.44 in (31.68 units) between two boxes",
          len(xs) == 2 and xs[1] - xs[0] - 54 >= 31.68 - 0.01, repr(xs))
    # ...and the floor never replaces a wider nodesep the DOT sets: a -G value
    # would override it.
    wide = build(fence("digraph { nodesep=1; node [shape=box]; "
                       "{rank=same; a; b} }"))
    xs = sorted(float(x) for x in re.findall(r'points="([\d.-]+),', wide))
    check("a nodesep=1 the DOT sets is kept (72 units between two boxes)",
          len(xs) == 2 and abs(xs[1] - xs[0] - 54 - 72) < 0.01, repr(xs))

    # Determinism: in one process, and across processes with another seed.
    check("the same spec builds byte-identical twice", build(GOOD) == html)
    tmp = tempfile.mkdtemp(prefix="test-graph-")
    try:
        spec = os.path.join(tmp, "g.spec.md")
        with open(spec, "w", encoding="utf-8") as fh:
            fh.write(GOOD)
        outs = [subprocess.run([sys.executable, BUILD, spec],
                               env=dict(os.environ, PYTHONHASHSEED=seed),
                               capture_output=True).stdout
                for seed in ("1", "2")]
        check("byte-identical across processes and hash seeds",
              outs[0] == outs[1] and outs[0])

        # The wrapped page, through the real contract.
        page = os.path.join(tmp, "page.spec.md")
        with open(page, "w", encoding="utf-8") as fh:
            fh.write(SPEC_PAGE)
        out = os.path.join(tmp, "page.html")
        r = subprocess.run([sys.executable, BUILD, page, "-o", out, "--check"],
                           capture_output=True, text=True)
        check("the wrapped page passes check-artifact", r.returncode == 0,
              r.stdout + r.stderr)
        check("and check-artifact reports no svg-text finding",
              "svg-text" not in r.stdout + r.stderr, r.stdout + r.stderr)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # --- labels ---------------------------------------------------------
    print("== labels ==")
    got = graph_svg.labels(svg)
    check("labels: nodes and clusters, multi-line joined, entities unescaped",
          sorted(got) == sorted(["Primero", "Segundo", "Tercero segunda línea",
                                 "Grupo & <cosa>"]), repr(got))
    check("labels: an edge label is not a node label",
          "etiqueta de arista" not in got)

# --- BL-905: a long single-line label grows its box (measure wider) --------
# The browser draws the kit mono stack at 0.602 em (7.83 units at 13); Graphviz
# measured `monospace` at 7.5 and sized the box for that. The real-browser proof
# is test-render-probe.sh; this row pins the number without a browser.
print("== long labels ==")
if graph_svg.dot_path():
    LONG = "x" * 80
    svg, _ = graph_svg.render('digraph { node [shape=box]; a [label="%s"] }' % LONG)
    box = re.search(r'<polygon fill="none"[^>]*points="([^"]*)"', svg).group(1)
    xs = [float(p.split(",")[0]) for p in box.split()]
    drawn = len(LONG) * 0.602 * 13
    check("a long label: the box is wider than the browser's drawn text",
          max(xs) - min(xs) >= drawn * 1.05, "box %g, text %g" % (max(xs) - min(xs), drawn))
    check("a long label: the text keeps the kit size, not the layout size",
          'font-size="13.00"' in svg and "14.30" not in svg)
    svg, _ = graph_svg.render('digraph { a [fontsize=20] }')
    check("a DOT's own fontsize=20 is left as written",
          'font-size="20.00"' in svg)
    svg, _ = graph_svg.render('digraph { a [fontsize=14] }')
    check("a DOT's own fontsize=14 (Graphviz's default) is left as written",
          'font-size="14.00"' in svg)
    svg, _ = graph_svg.render('digraph { a [fontsize=14.3] }')
    check("known: a DOT's own fontsize=14.3 reads as the layout size and is "
          "written back as 13", 'font-size="13.00"' in svg)
    svg, _ = graph_svg.render('digraph { subgraph cluster_x { label="t"; '
                              'a -> b [label="e"] } }')
    check("title and edge label: laid out at 12.3, drawn at 11; nodes at 13",
          set(re.findall(r'font-size="([^"]*)"', svg)) == {"11.00", "13.00"}
          and "12.30" not in svg, repr(set(re.findall(r'font-size="([^"]*)"', svg))))

# --- a Graphviz that hangs is refused, not waited on (review finding 1) -----
real_run, real_path = graph_svg.subprocess.run, graph_svg.dot_path


def _hang(cmd, **kw):
    raise subprocess.TimeoutExpired(cmd, kw.get("timeout"))


graph_svg.subprocess.run, graph_svg.dot_path = _hang, lambda: "/fake/dot"
try:
    rejects("a dot that does not finish is refused with a timeout",
            fence("digraph { a }"), 3, "did not finish")
finally:
    graph_svg.subprocess.run, graph_svg.dot_path = real_run, real_path

# --- edges on a fixed SVG: what the gate compares besides labels -----------
EDGES = ('<svg viewBox="0 0 10 10"><g class="graph">'
         '<g class="node"><polygon/><text>a</text></g>'
         '<g class="edge"><path d="M0,0"/><polygon/></g>'
         '<g class="edge flg"><path stroke-dasharray="5,2" d="M0,0"/></g>'
         '<g class="edge"><path d="M0,0"/></g>'
         '</g></svg>')
check("edges (fixed svg): solid and dashed counted per edge group",
      graph_svg.edges(EDGES) == {"solid": 2, "dashed": 1},
      repr(graph_svg.edges(EDGES)))

# --- labels on a fixed SVG: no Graphviz needed ------------------------------
FIXED = ('<svg viewBox="0 0 10 10"><g class="graph">'
         '<g class="cluster"><polygon/><text>Caja</text></g>'
         '<g class="node acc"><polygon/><text>Uno</text><text>dos</text></g>'
         '<g class="edge"><path/><text>arista</text></g>'
         '<g class="node"><polygon/><text>&lt;b&gt; &amp; c</text></g>'
         '</g></svg>')
check("labels (fixed svg): cluster, multi-line node, escaped node; no edge",
      graph_svg.labels(FIXED) == ["Caja", "Uno dos", "<b> & c"],
      repr(graph_svg.labels(FIXED)))

if failures:
    print("NOT OK — %d failure(s)" % len(failures))
    sys.exit(1)
print("OK — graph block: no-dot refusal with the install line, fence refusals,"
      " kit classes and currentColor only, refusals with the spec line,"
      " byte-identical builds, contract and svg-text clean, labels for the gate")
