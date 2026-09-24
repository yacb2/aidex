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
