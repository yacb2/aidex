#!/usr/bin/env python3
"""The `::: figure` block: a drawing from a file, embedded on the spec route.

Five groups:

  EMBED — an .svg is parsed and re-serialised (prolog and comments dropped),
  a .png/.jpg becomes an <img> with a data URI and its alt; the id, classes and
  caption land where `chart` puts them.

  REFUSE AT THE FENCE — no src, an absolute src, an unknown or missing
  extension, a missing file, a raster with no alt, an svg with an alt, a body,
  a file with no <svg> in it: each a SpecBuildError at the FENCE's line.

  SVG RULES — `check_artifact.svg_embed_sanitize` is the owner and the block
  keeps no copy: an ALLOWLIST over a strict XML parse. Code, HTML, fetching or
  navigating elements, foreign namespaces, unknown or on* attributes, any href
  but #frag, CSS that loads or runs, literal paint, and anything that does not
  parse (the tokenizer differentials) are refused with the thing named; the
  page gets the checked tree re-serialised, every text node escaped.

  EXTRACT — `figure_extract.py`, the corpus's tool for taking figure N out of
  a page: the <svg> byte for byte, a data-URI image decoded, anything else
  refused.

  THE PAGE — a masthead declaring `visual="svg"` is satisfied by a figure the
  way it is by a chart (the wrapped page passes check-artifact, built from `/`
  so src is proved relative to the spec), and the same spec builds
  byte-identically twice.

Stdlib only, no runner: `python3 test_figure.py`, prints OK, exits 0.
"""
import base64
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
SCRIPTS = os.path.join(SKILL, "scripts")
sys.path.insert(0, SCRIPTS)
sys.path.insert(0, os.path.join(SCRIPTS, "dash"))

import check_artifact                              # noqa: E402
import spec_build                                  # noqa: E402
from spec_build import SpecBuildError, build       # noqa: E402

BUILD = os.path.join(SCRIPTS, "spec_build.py")

failures = []


def check(label, cond, detail=""):
    if cond:
        print("  ok: " + label)
    else:
        failures.append(label)
        print("FAIL: %s%s" % (label, (": " + detail) if detail else ""))


SVG = ('<svg viewBox="0 0 40 20" role="img"><rect class="acc" x="1" y="1" '
       'width="38" height="18" fill="none" stroke="currentColor"/>'
       '<text x="20" y="14" fill="currentColor">ok</text></svg>')
# A 1x1 PNG, the smallest real file of the type.
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/"
    "PchI7wAAAABJRU5ErkJggg==")


def embedded(src):
    """What a plain SVG (no <style>) comes out as: the same markup, its root
    carrying `data-embed="<first 8 hex of the file's sha256>"`."""
    key = hashlib.sha256(src.encode("utf-8")).hexdigest()[:8]
    return src.replace("<svg", '<svg data-embed="%s"' % key, 1)


def refused(label, spec, base, line, *needles):
    try:
        build(spec, base_dir=base)
    except SpecBuildError as exc:
        missing = [n for n in needles if n not in exc.message]
        check(label, exc.line == line and not missing,
              "line %d (want %d), missing %r in %r"
              % (exc.line, line, missing, exc.message))
        return
    check(label, False, "built without complaint")


def png_of(w, h):
    """A real PNG of w x h (all-black rows), so the builder reads a true size."""
    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xffffffff))
    raw = b"".join(b"\x00" + b"\x00" * w for _ in range(h))
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def run_highlight(tmp):
    """BL-619: a png figure takes highlight="x,y,w,h" in image pixels and
    emits the gallery's percentage overlay; layer: the builder (a decision on
    the spec text, no browser needed)."""
    print("== highlight ==")
    write(tmp, "figures/big.png", png_of(200, 100))

    def fig(extra, src="figures/big.png"):
        return ('::: figure {#f1 src="%s" alt="la lista" %s}\n:::\n'
                % (src, extra))

    html = build(fig('highlight="20,10,60,30"'), base_dir=tmp)
    check("highlight: the gallery overlay in percentages of the image",
          'class="gal-hl-layer"' in html and 'aspect-ratio:200 / 100' in html
          and 'style="left:10%;top:10%;width:30%;height:30%"' in html, html[-600:])
    check("highlight: the overlay sits in the figure, after the img",
          html.index("<img") < html.index("gal-hl-layer") < html.index("</figure>"))
    check("no highlight: no overlay",
          "gal-hl" not in build(fig(""), base_dir=tmp))
    check("highlight touching the far edges is accepted",
          'width:100%;height:100%' in build(fig('highlight="0,0,200,100"'),
                                            base_dir=tmp))
    refused("highlight past the right edge is refused, naming the figure",
            fig('highlight="150,0,60,10"'), tmp, 1, "figures/big.png",
            "runs outside", "200x100")
    refused("highlight past the bottom edge is refused",
            fig('highlight="0,95,10,10"'), tmp, 1, "runs outside")
    refused("zero width is refused", fig('highlight="0,0,0,10"'), tmp, 1,
            "w, h > 0")
    refused("negative x is refused", fig('highlight="-1,0,10,10"'), tmp, 1,
            "x, y >= 0")
    refused("three numbers are refused", fig('highlight="1,2,3"'), tmp, 1,
            "x,y,w,h")
    refused("a non-number is refused", fig('highlight="a,2,3,4"'), tmp, 1,
            "x,y,w,h")
    refused("highlight on an svg is refused", fig('highlight="0,0,5,5"',
            "figures/a.svg").replace(' alt="la lista"', ""), tmp, 1,
            "highlight", "png/jpg")
    # APP0 (JFIF, 16 bytes) sits before SOF0: the walk must step over it.
    write(tmp, "figures/real.jpg", b"\xff\xd8" + b"\xff\xe0\x00\x10" + b"JFIF\x00" + b"\x00" * 9
          + b"\xff\xc0\x00\x11\x08\x00\x40\x00\x80\x03" + b"\x00" * 12 + b"\xff\xd9")
    html = build(fig('highlight="0,0,64,32"', "figures/real.jpg"), base_dir=tmp)
    check("a jpg is measured from its SOF marker past an APP0 segment (128x64)",
          'aspect-ratio:128 / 64' in html and 'width:50%;height:50%' in html,
          html[-400:])
    write(tmp, "figures/fake.png", b"not a png at all, only bytes\n" * 3)
    refused("a .png that is not a PNG is refused, naming the figure",
            fig('highlight="0,0,5,5"', "figures/fake.png"), tmp, 1,
            "figures/fake.png", "not a PNG")
    try:
        build(fig('highlight="150,0,60,10"'), base_dir=tmp)
    except SpecBuildError as exc:
        check("a refusal names the figure, not a gallery row",
              "row '" not in exc.message and "gallery-items" not in exc.message
              and "`figure`" in exc.message, exc.message)

    print("== highlight inside an item (the verify's shape) ==")
    write(tmp, "figures/tall.png", png_of(100, 300))
    one = ('::: item {#Q1 title="T"}\n¿Cuál?\n\n%s\n- A — uno\n- B — dos\n:::\n'
           % fig('highlight="10,20,30,40"').replace("#f1 ", ""))
    html = build(one, base_dir=tmp)
    check("item, one highlighted png: wrapped in the kit class, overlay inside it, no grid",
          '<div class="fig-hl"><img' in html and 'gal-hl-layer' in html
          and '<div class="gal' not in html and 'max-width' not in html
          and 'left:5%;top:20%;width:15%;height:40%' in html, html[:900])
    two = ('::: item {#Q1 title="T"}\n¿Cuál?\n\n'
           '::: figure {src="figures/big.png" alt="a" highlight="20,10,60,30"}\n:::\n\n'
           '::: figure {src="figures/tall.png" alt="b" highlight="10,200,50,50"}\n:::\n\n'
           '- A — uno\n- B — dos\n:::\n')
    html = build(two, base_dir=tmp)
    grid = html.split('<div class="gal shots"', 1)[-1].split("\n</div>\n", 1)[0]
    check("item, two rasters with highlights: one shots grid, each overlay measured on ITS image",
          html.count('<div class="gal shots"') == 1 and grid.count("<figure") == 2
          and grid.count('<div class="fig-hl">') == 2
          and 'aspect-ratio:200 / 100' in grid and 'aspect-ratio:100 / 300' in grid
          and 'top:66.667%' in grid, grid[:1200])



def main():
    tmp = tempfile.mkdtemp(prefix="spec-figure-")
    try:
        run(tmp)
        run_shots(tmp)
        run_highlight(tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    if failures:
        print("NOT OK — %d failure(s)" % len(failures))
        return 1
    print("OK — test_figure.py: svg inlined and png/jpg as data URIs, every "
          "refusal at the fence's line, the SVG rules owned by check_artifact, "
          "visual=\"svg\" satisfied by a figure, deterministic")
    return 0


def write(tmp, name, data):
    path = os.path.join(tmp, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb" if isinstance(data, bytes) else "w") as fh:
        fh.write(data)
    return path


def run(tmp):
    write(tmp, "figures/a.svg", SVG + "\n")
    write(tmp, "figures/prolog.svg",
          '<?xml version="1.0" encoding="UTF-8"?>\n' + SVG + "\n")
    write(tmp, "figures/shot.png", PNG)
    write(tmp, "figures/shot.jpg", PNG)
    write(tmp, "figures/shot.jpeg", PNG)
    write(tmp, "figures/noroot.svg", "<p>not a drawing</p>\n")

    print("== embed ==")
    html = build('Antes.\n\n::: figure {#f1 .wide src="figures/a.svg" '
                 'title="Un <título> & más"}\n:::\n', base_dir=tmp)
    # BL-511: the wrapper is capped at the viewBox width (40), the drawing kept.
    check("an svg is re-serialised inside one <figure> capped at its viewBox width",
          '<figure id="f1" class="wide" style="max-width:40px">\n' + embedded(SVG + "\n")[:-1]
          + "\n<figcaption>" in html,
          html)
    check("the caption is escaped text, not markup",
          "<figcaption>Un &lt;título&gt; &amp; más</figcaption>" in html, html)
    html = build('::: figure {src="figures/prolog.svg"}\n:::\n', base_dir=tmp)
    check("an XML prolog before the root is dropped, the drawing kept",
          "<?xml" not in html and SVG[4:] in html, html)
    check("no title, no <figcaption>", "<figcaption>" not in html, html)
    html = build('::: figure {src="figures/shot.png" alt="Una \\"captura\\" <b>"}\n'
                 ':::\n', base_dir=tmp)
    want = base64.b64encode(PNG).decode("ascii")
    check("a png becomes an <img> with a data URI and its alt, escaped",
          '<img src="data:image/png;base64,%s" alt="Una &quot;captura&quot; '
          '&lt;b&gt;">' % want in html, html)
    for ext in ("jpg", "jpeg"):
        html = build('::: figure {src="figures/shot.%s" alt="x"}\n:::\n' % ext,
                     base_dir=tmp)
        check("a .%s is image/jpeg" % ext, "data:image/jpeg;base64," in html, html)

    print()
    print("== refused at the fence's line ==")
    pre = "Un párrafo.\n\n"                        # the fence sits on line 3
    refused("no src", pre + "::: figure {title=t}\n:::\n", tmp, 3,
            "non-empty src")
    refused("an absolute src", pre + '::: figure {src="%s"}\n:::\n'
            % os.path.join(tmp, "figures", "a.svg"), tmp, 3, "is absolute")
    refused("an unknown extension", pre + '::: figure {src="a.gif"}\n:::\n',
            tmp, 3, "'.gif'", ".svg, .png, .jpg, .jpeg")
    refused("no extension at all", pre + '::: figure {src="figures/a"}\n:::\n',
            tmp, 3, "(none)")
    refused("a missing file", pre + '::: figure {src="figures/nope.svg"}\n:::\n',
            tmp, 3, "no such file", "figures/nope.svg")
    refused("a png with no alt", pre + '::: figure {src="figures/shot.png"}\n:::\n',
            tmp, 3, "needs alt=")
    refused("a png with a blank alt",
            pre + '::: figure {src="figures/shot.png" alt="  "}\n:::\n',
            tmp, 3, "needs alt=")
    refused("an svg with an alt",
            pre + '::: figure {src="figures/a.svg" alt="x"}\n:::\n',
            tmp, 3, "alt= is for a png/jpg")
    refused("an unknown attr", pre + '::: figure {src="figures/a.svg" width=3}\n:::\n',
            tmp, 3, "takes no attr 'width'")
    refused("a body", pre + '::: figure {src="figures/a.svg"}\nTexto.\n:::\n',
            tmp, 3, "takes no body")
    write(tmp, "figures/latin1.svg", b"<svg><text>\xe9</text></svg>")
    refused("an svg that is not UTF-8 is a SpecBuildError, not a crash",
            pre + '::: figure {src="figures/latin1.svg"}\n:::\n', tmp, 3,
            "cannot be read as UTF-8")
    refused("a file with no <svg> in it",
            pre + '::: figure {src="figures/noroot.svg"}\n:::\n', tmp, 3,
            "holds no <svg>")

    print()
    print("== the SVG rules, owned by check_artifact: an ALLOWLIST ==")
    check("spec_build keeps no copy of the rules: it calls check_artifact's",
          spec_build.check_artifact.svg_embed_sanitize
          is check_artifact.svg_embed_sanitize)
    # The file is parsed as strict XML and walked; what is not on the list is
    # refused. Each row: the source, and a word the refusal must name.
    refused_svg = [
        # code and HTML
        ("a <script>", '<svg><script>x()</script></svg>', "<script>"),
        ("a CDATA-wrapped <script>",
         '<svg><script><![CDATA[alert(1)]]></script></svg>', "<script>"),
        ("a <foreignObject>",
         '<svg><foreignObject><div>x</div></foreignObject></svg>', "<foreignObject>"),
        ("an <a href=javascript:>",
         '<svg><a href="javascript:alert(1)"><text>t</text></a></svg>', "<a>"),
        ("a <base href>", '<svg><base href="https://e.x/"/></svg>', "<base>"),
        ("a <form>", '<svg><form action="https://e.x/"/></svg>', "<form>"),
        ("a <link>", '<svg><link rel="stylesheet" href="https://e.x/a.css"/></svg>',
         "<link>"),
        ("an <img>", '<svg><img src="https://e.x/p.png"/></svg>', "<img>"),
        ("an <iframe>", '<svg><iframe/></svg>', "<iframe>"),
        ("an <object>", '<svg><object/></svg>', "<object>"),
        ("an <embed>", '<svg><embed/></svg>', "<embed>"),
        ("a <meta>", '<svg><meta/></svg>', "<meta>"),
        ("an <image>, which fetches", '<svg><image href="#a"/></svg>', "<image>"),
        ("an <animate>, which rewrites attributes",
         '<svg><a><animate attributeName="href" values="javascript:alert(1)"/></a></svg>',
         "<a>"),
        ("a <set>", '<svg><set attributeName="fill" to="red"/></svg>', "<set>"),
        ("an element in a foreign namespace",
         '<svg xmlns:h="http://www.w3.org/1999/xhtml"><h:g/></svg>', "foreign namespace"),
        ("an svg-looking element in a foreign namespace",
         '<svg xmlns:x="urn:x"><x:rect/></svg>', "foreign namespace"),
        # attributes
        ("an on* handler", '<svg><rect onclick="x()"/></svg>', "onclick"),
        ("an attribute not on the list", '<svg><rect formaction="x"/></svg>', "formaction"),
        ("a namespaced x:href with a declared namespace",
         '<svg xmlns:x="urn:x"><use x:href="javascript:alert(1)"/></svg>', "urn:x"),
        ("a data:text/html href",
         '<svg><use href="data:text/html,&lt;script&gt;alert(1)&lt;/script&gt;"/></svg>',
         "only a #fragment"),
        ("an external href", '<svg><use href="https://e.x/a.svg#g"/></svg>',
         "only a #fragment"),
        ("an external xlink:href",
         '<svg xmlns:xlink="http://www.w3.org/1999/xlink"><use xlink:href="o.svg#a"/></svg>',
         "only a #fragment"),
        ("a remote url() in a fill attribute",
         '<svg><rect fill="url(https://evil/p.svg#g)"/></svg>', "url(https://evil/p.svg#g)"),
        # paint
        ("a hex fill", '<svg><rect fill="#1E5F4B"/></svg>', '<rect fill="#1E5F4B">'),
        ("a short hex stroke", '<svg><line stroke="#fff"/></svg>', '<line stroke="#fff">'),
        ("an rgb() stroke", '<svg><path stroke="rgb(1, 2, 3)"/></svg>', "rgb("),
        ("an hsl() fill", '<svg><rect fill="hsl(10 20% 30%)"/></svg>', "hsl("),
        ("an oklch() fill", '<svg><rect fill="oklch(0.5 0.1 120)"/></svg>', "oklch("),
        ("a color() fill", '<svg><rect fill="color(srgb 1 0 0)"/></svg>', "color("),
        ("a CSS comment in style= before a hex",
         '<svg><rect style="fill:/**/#f00"/></svg>', "#f00"),
        ("an rgba() fill in style=",
         '<svg><text style="font-size:9px; fill: rgba(0,0,0,.5)">t</text></svg>', "rgba("),
        ("a remote url() in style=",
         '<svg><rect style="fill:url(https://e.x/p.svg#g)"/></svg>', "url(https://e.x/"),
        ("expression() in style=", '<svg><rect style="width:expression(alert(1))"/></svg>',
         "expression"),
        # the figure's own <style>
        ("a hex fill in <style>",
         '<svg><style>#f .chip{font-weight:600;fill:#FFFFFF}</style></svg>', "#FFFFFF"),
        ("a remote url() in <style>",
         '<svg><style>rect{fill:url(https://e.x/p.svg#g)}</style></svg>', "url(https://e.x/"),
        ("an @import in <style>", '<svg><style>@import url(https://e.x/a.css);</style></svg>',
         "@import"),
        ("behavior: in <style>", '<svg><style>rect{behavior:url(#x)}</style></svg>',
         "behavior"),
        ("-moz-binding in <style>", '<svg><style>rect{-moz-binding:url(#x)}</style></svg>',
         "-moz-binding"),
        # what does not parse as XML, or is not one <svg> element
        ("HTML-only markup inside <style> (the tokenizer differential)",
         '<svg><style><img src=x onerror=alert(1)></style></svg>', "does not parse"),
        ("unquoted attributes", '<svg><rect width=3/></svg>', "does not parse"),
        ("an element left open", '<svg><g></svg>', "does not parse"),
        ("a breakout </figure></main>", '<svg><g></g></figure></main></svg>',
         "does not parse"),
        ("an <iframe> after the root",
         '<svg viewBox="0 0 1 1"></svg><iframe src="https://evil.example/"></iframe>',
         "does not parse"),
        ("an unknown entity", '<svg><text>&bogus;</text></svg>', "does not parse"),
        ("a DOCTYPE, which can declare entities",
         '<!DOCTYPE svg [<!ENTITY x "y">]><svg><text>&x;</text></svg>', "DOCTYPE"),
        ("a root that is not <svg>", '<svgx></svgx>', "not <svg>"),
        ("an upper-case <SVG> (XML is case-sensitive)", '<SVG></SVG>', "not <svg>"),
    ]
    for label, src, needle in refused_svg:
        why, out = check_artifact.svg_embed_sanitize(src)
        check("refused: %s — names %r" % (label, needle),
              out is None and any(needle in w for w in why), repr(why))
    allowed_svg = [
        ("currentColor, a class, none",
         '<svg><rect class="acc" fill="none" stroke="currentColor"/></svg>'),
        ("a gradient url(#g) and a fragment href, in both namespaces",
         '<svg xmlns="http://www.w3.org/2000/svg" '
         'xmlns:xlink="http://www.w3.org/1999/xlink"><defs><linearGradient id="g">'
         '<stop offset="0"/></linearGradient></defs><rect fill="url(#g)"/>'
         '<use href="#g"/><use xlink:href="#g"/></svg>'),
        ("a var() fill", '<svg><rect fill="var(--s1)"/></svg>'),
        ("a comment, and an XML prolog before the root",
         '<?xml version="1.0"?>\n<!-- c --><svg><!-- <script> --><rect/></svg>\n'
         '<!-- after -->\n'),
        ("a fragment url() in <style>", '<svg><defs><linearGradient id="g"/></defs>'
         '<style>#f rect{fill:url(#g)}</style></svg>'),
        ("an HTML named entity, as a character", '<svg><text>a &middot; b</text></svg>'),
        ("the corpus's markers and title/desc",
         '<svg role="img" aria-labelledby="t"><title id="t">T</title><desc>D</desc>'
         '<defs><marker id="m" markerWidth="8" markerHeight="8" refX="4" refY="4" '
         'orient="auto"><path d="M0 0L8 4L0 8z"/></marker></defs>'
         '<line x1="0" y1="0" x2="9" y2="9" marker-end="url(#m)"/></svg>'),
    ]
    for label, src in allowed_svg:
        why, out = check_artifact.svg_embed_sanitize(src)
        check("allowed: %s" % label, why == [] and out is not None, repr(why))

    # What the page gets is the PARSED tree, re-serialised: every text node
    # escaped, so no tokenizer can read a tag the checker did not.
    print()
    print("== the build output is the checked tree, re-serialised ==")
    _w, out = check_artifact.svg_embed_sanitize(
        '<svg><title>&lt;/title&gt;&lt;script&gt;alert(1)&lt;/script&gt;</title>'
        '<style>#f text{fill:currentColor}</style>'
        '<text>a &middot; b &amp; c</text></svg>')
    check("<title> text holding </title><script> stays escaped text",
          out is not None and "<script" not in out
          and "&lt;/title&gt;&lt;script&gt;" in out, repr(out))
    check("an HTML entity arrives as its character, & is re-escaped",
          out is not None and "a · b &amp; c" in out, repr(out))
    _w, out = check_artifact.svg_embed_sanitize(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'xmlns:xlink="http://www.w3.org/1999/xlink"><g id="g"/><use xlink:href="#g"/></svg>')
    check("namespaces are dropped from names; xlink:href is written back as xlink:href",
          out is not None and out.startswith('<svg data-embed="')
          and '<use xlink:href="#e' in out and out.endswith('-g"/></svg>'),
          repr(out))

    # BL-452: an id is scoped to its own figure. Two figures that both define
    # `<marker id="m">` resolved url(#m) to the FIRST one in the document, and
    # an embed id equal to a page id (`raillist`) duplicated it ahead of the
    # real element. Every id takes the figure's own key, every reference to it
    # follows, and a reference to an id the file does not define is refused.
    print()
    print("== ids are scoped to their own figure ==")
    arrow = ('<svg aria-labelledby="t"><title id="t">T</title><defs>'
             '<marker id="m"><path d="M0 0L8 4z"/></marker>'
             '<linearGradient id="g"><stop offset="0"/></linearGradient></defs>'
             '<style>#l{stroke-width:2}</style>'
             '<line id="l" marker-end="url(#m)" style="fill:url(#g)"/>'
             '<use href="#l"/><g id="raillist"/></svg>')
    _w, out = check_artifact.svg_embed_sanitize(arrow)
    key = out and out.split('data-embed="', 1)[1][:8]
    scoped = "e%s-" % key
    check("every id carries the figure's key",
          out is not None and 'id="%sm"' % scoped in out and 'id="%sl"' % scoped in out
          and 'id="%st"' % scoped in out and 'id="raillist"' not in out, repr(out))
    check("url(#…) in an attribute and in style= follows the id",
          out is not None and 'marker-end="url(#%sm)"' % scoped in out
          and "fill:url(#%sg)" % scoped in out, repr(out))
    check("href=#… and aria-labelledby follow the id",
          out is not None and 'href="#%sl"' % scoped in out
          and 'aria-labelledby="%st"' % scoped in out, repr(out))
    check("a #id selector in <style> follows the id",
          out is not None and "#%sl" % scoped in out.split("<style>", 1)[1],
          repr(out))
    _w, other = check_artifact.svg_embed_sanitize(arrow.replace("T<", "U<"))
    check("the same ids in another file get another key",
          other is not None and 'id="%sm"' % scoped not in other, repr(other))
    for label, src, needle in [
            ("an href to an id the file does not define",
             '<svg><use href="#nowhere"/></svg>', "#nowhere"),
            ("a url(#…) to an id the file does not define",
             '<svg><line marker-end="url(#raillist)"/></svg>', "#raillist"),
            ("an aria reference to an id the file does not define",
             '<svg aria-labelledby="h1"><text>x</text></svg>', "#h1")]:
        why, out = check_artifact.svg_embed_sanitize(src)
        check("refused: %s" % label,
              out is None and any(needle in w for w in why), repr(why))

    # Second security pass. CSS is no longer searched for bad words: anything
    # that could hide one (a backslash escape, an @-rule, an unclosed comment,
    # a function not on the list) is refused, in style="" and in <style>.
    print()
    print("== CSS: an allowlist of properties and selectors, scoped to the figure ==")
    # Third security pass: a <style> selector applies to the whole DOCUMENT and
    # `position:fixed` lifts the figure out of <figure> (both confirmed in
    # headless Chrome). Only paint and text properties, only type/.class/#id
    # compounds with a descendant or `>` combinator, and every selector
    # rewritten under the figure's own `svg[data-embed="…"]`.
    for label, css, needle in [
            ("position:fixed", "position:fixed", "position"),
            ("background", "background:rgb(255,0,0)", "background"),
            ("display", "display:none", "display"),
            ("content", "content:'x'", "content"),
            ("transform", "transform:scale(9)", "transform"),
            ("width", "width:100vw", "width"),
            ("z-index", "z-index:9", "z-index"),
            ("a custom property definition", "--kit-accent:magenta", "--kit-accent"),
            ("a declaration with no colon", "fill", "not a declaration")]:
        for where, src in [
                ("style=", '<svg><rect style="%s"/></svg>' % css.replace("'", "&apos;")),
                ("<style>", "<svg><style>rect{%s}</style></svg>" % css)]:
            why, out = check_artifact.svg_embed_sanitize(src)
            check("refused in %s: %s — names %r" % (where, label, needle),
                  out is None and any(needle in w for w in why), repr(why))
    for label, sel, needle in [
            ("the universal selector", "*", "*"),
            ("body", "body", "body"),
            ("html", "html g", "html"),
            (":root", ":root", ":root"),
            ("body>*", "body>*", "body>*"),
            ("a pseudo-class", "rect:hover", "rect:hover"),
            ("a pseudo-element", "text::before", "text::before"),
            ("an attribute selector", "rect[x]", "rect[x]"),
            ("a sibling combinator ~", "rect ~ text", "rect ~ text"),
            ("a sibling combinator +", "rect + text", "rect + text"),
            ("an empty selector in a list", "rect,", "''")]:
        why, out = check_artifact.svg_embed_sanitize(
            "<svg><style>%s{fill:none}</style></svg>" % sel)
        check("refused selector: %s — names %r" % (label, needle),
              out is None and any(needle in w for w in why), repr(why))
    for label, src, needle in [
            ("text in <style> that is not a rule",
             "<svg><style>rect{fill:none} stray</style></svg>", "not a rule"),
            ("a transform attribute on the root <svg>",
             '<svg transform="translate(0 -900)"><rect/></svg>', "transform"),
            ("overflow on the root <svg>", '<svg overflow="visible"><rect/></svg>',
             "overflow"),
            ("display on the root <svg>", '<svg display="block"><rect/></svg>',
             "display"),
            ("a data-embed written by the author", '<svg data-embed="x"><rect/></svg>',
             "data-embed")]:
        why, out = check_artifact.svg_embed_sanitize(src)
        check("refused: %s — names %r" % (label, needle),
              out is None and any(needle in w for w in why), repr(why))
    src = ('<svg><style>rect.a > text#t, g .b{fill:currentColor;font-size:12px;'
           'stroke-width:2} text{font-family:var(--mono)}</style>'
           '<g class="b"><rect class="a" style="fill:var(--s1);font-weight:600;'
           'stroke-dasharray:2 2;marker-end:url(#m)"/></g><marker id="m"/></svg>')
    key = hashlib.sha256(src.encode("utf-8")).hexdigest()[:8]
    why, out = check_artifact.svg_embed_sanitize(src)
    scope = 'svg[data-embed="%s"]' % key
    check("allowed: paint and text properties, type/.class/#id compounds, > and "
          "descendant, a comma list", why == [] and out is not None, repr(why))
    check("the root carries data-embed = the first 8 hex of the file's sha256",
          out is not None and out.startswith('<svg data-embed="%s">' % key), repr(out))
    check("every selector is rewritten under the figure's own root",
          out is not None and "<style>%s rect.a > text#e%s-t, %s g .b{" % (scope, key, scope)
          in out and "%s text{font-family:var(--mono)}" % scope in out, repr(out))
    # A selector keyed on the ROOT (its own id, as the canon asks, or `svg`)
    # must scope to the root as one compound: under a descendant combinator the
    # root is not its own descendant and every rule was silently dropped.
    rsrc = ('<svg id="fig-hp"><style>#fig-hp text{fill:currentColor} '
            'svg#fig-hp > .p, svg .q, g#fig-hp .r{fill:none}</style>'
            '<text>x</text></svg>')
    rkey = hashlib.sha256(rsrc.encode("utf-8")).hexdigest()[:8]
    _, rout = check_artifact.svg_embed_sanitize(rsrc)
    rscope = 'svg[data-embed="%s"]' % rkey
    check("a selector on the root's own id or `svg` scopes to the root itself",
          rout is not None and "<style>%s#e%s-fig-hp text{" % (rscope, rkey) in rout
          and "%s#e%s-fig-hp > .p, %s .q, %s g#e%s-fig-hp .r{"
          % (rscope, rkey, rscope, rscope, rkey) in rout, repr(rout))
    check("style= keeps its allowed declarations",
          out is not None and 'style="fill:var(--s1);font-weight:600;' in out, repr(out))

    print("== CSS: refused by shape, not searched for bad words ==")
    for label, css, needle in [
            ("a CSS escape spelling url(", "fill:\\75rl(https://e.x/a.svg#g)",
             "backslash"),
            ("a CSS escape spelling @import", "@im\\port 'https://e.x/a.css';",
             "backslash"),
            ("an @font-face rule", "@font-face{font-family:x}", "@"),
            ("an @media rule", "@media print{rect{fill:none}}", "@"),
            ("image-set(), which fetches a string", 'fill:image-set("https://e.x/a.png")',
             "image-set("),
            ("a quoted url('#g')", "fill:url('#g')", "url("),
            ("url( #g ) with spaces", "fill:url( #g )", "url("),
            ("javascript:", "fill:javascript:alert(1)", "javascript:"),
            ("expression()", "width:expression(alert(1))", "expression"),
            ("behavior:", "behavior:url(#x)", "behavior"),
            ("-moz-binding", "-moz-binding:url(#x)", "-moz-binding"),
            ("an unclosed comment", "fill:none /* never closed", "unclosed"),
    ]:
        for where, src in [
                ("style=", '<svg><rect style="%s"/></svg>'
                 % css.replace('"', "&quot;")),
                ("<style>", "<svg><style>rect{%s}</style></svg>" % css)]:
            if where == "<style>" and css.startswith("@"):
                src = "<svg><style>%s</style></svg>" % css
            why, out = check_artifact.svg_embed_sanitize(src)
            check("refused in %s: %s — names %r" % (where, label, needle),
                  out is None and any(needle in w for w in why), repr(why))
    for label, src, needle in [
            ("a </ inside style=", '<svg><rect style="fill:none&lt;/style"/></svg>',
             "</"),
            ("a < in <style> text (entity-escaped)",
             "<svg><style>rect{fill:none}&lt;/style&gt;</style></svg>", "<"),
            ("a < in <style> text (CDATA)",
             "<svg><style><![CDATA[rect{fill:none} /* <img src=x onerror=a()> */]]>"
             "</style></svg>", "<"),
            ("an & in <style> text", "<svg><style>rect{fill:none} &amp;</style></svg>",
             "&"),
            ("a ]]> in <style> text", "<svg><style>rect{fill:none} ]]&gt;</style></svg>",
             "]]>"),
            ("an attribute name ElementTree accepts and HTML does not share",
             '<svg><rect fill.x="1"/></svg>', "fill.x"),
            ("a non-ASCII attribute name", '<svg><rect \u00e9="1"/></svg>', "\u00e9"),
    ]:
        why, out = check_artifact.svg_embed_sanitize(src)
        check("refused: %s — names %r" % (label, needle),
              out is None and any(needle in w for w in why), repr(why))

    # Round trip: what Python's HTML tokenizer reads from the output, placed in
    # a page, is exactly the XML tree that was checked — same elements, same
    # attributes, in order, and nothing else.
    print()
    print("== round trip: the HTML parser reads back the checked tree ==")
    tricky = [
        ("attribute values with a newline, a backtick and quotes",
         '<svg><text x="1" aria-label="a&#10;b `c` &quot;d&quot; \'e\' &lt;f&gt;">t</text></svg>'),
        ("<desc> holding </desc><script>",
         "<svg><desc>&lt;/desc&gt;&lt;script&gt;alert(1)&lt;/script&gt;</desc></svg>"),
        ("a numeric reference to < and & in text",
         "<svg><text>&#60;script&#62; &#38;lt;</text></svg>"),
        ("a processing instruction and a comment inside the root",
         '<svg><?php echo 1 ?><!-- <script>x</script> --><rect/></svg>'),
        ("<svg> nested in <svg>", '<svg><svg x="1"><rect/></svg></svg>'),
        ("xml:space and xml:lang", '<svg xml:lang="es"><text xml:space="preserve"> a </text></svg>'),
        ("<style> text with a child combinator and quotes",
         "<svg><style>#f g > text{font-family:'Inter',\"x\"}</style></svg>"),
    ]
    import html.parser as _hp

    class Seq(_hp.HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.seq = []

        def handle_starttag(self, tag, attrs):
            self.seq.append((tag, [(k, v) for k, v in attrs]))

    def scoped(name, val, key):
        # BL-452: what the page gets for an id and each kind of reference.
        if name == "id":
            return "e%s-%s" % (key, val)
        if name in ("href", "xlink:href"):
            return "#e%s-%s" % (key, val[1:])
        if name in ("aria-labelledby", "aria-describedby"):
            return " ".join("e%s-%s" % (key, r) for r in val.split())
        return val.replace("url(#", "url(#e%s-" % key)

    def tree_seq(el, key):
        out = [(check_artifact._svg_embed_name(el.tag)[0].lower(),
                [(check_artifact._svg_embed_attr(k).lower(),
                  scoped(check_artifact._svg_embed_attr(k), v, key))
                 for k, v in el.attrib.items()])]
        for child in el:
            out += tree_seq(child, key)
        return out

    corpus = os.environ.get("AIDEX_SPEC_CORPUS", "")
    figs = os.path.join(corpus, "corpus-specs", "figures") if corpus else ""
    sources = [(l, sv) for l, sv in allowed_svg + tricky]
    if figs and os.path.isdir(figs):
        carried = [f for f in sorted(os.listdir(figs)) if f.endswith(".svg")
                   and not check_artifact.svg_embed_violations(
                       open(os.path.join(figs, f), encoding="utf-8").read())]
        check("the corpus's 7 embeddable SVGs are all in the round trip",
              len(carried) == 7, repr(carried))
        sources += [("corpus " + f, open(os.path.join(figs, f), encoding="utf-8").read())
                    for f in carried]
    else:
        print("SKIP the corpus SVGs in the round trip: AIDEX_SPEC_CORPUS not set")
    for label, src in sources:
        why, out = check_artifact.svg_embed_sanitize(src)
        if out is None:
            check("round trip: %s is embeddable" % label, False, repr(why))
            continue
        p = Seq()
        p.feed("<div>" + out + "</div>")
        p.close()
        got = p.seq[1:]
        root = check_artifact._svg_embed_parse(src)
        key = hashlib.sha256(src.encode("utf-8")).hexdigest()[:8]
        want = tree_seq(root, key)
        # The one attribute the sanitizer adds: the scope key on the root.
        want[0][1].insert(0, ("data-embed", key))
        bad = [t for t, a in got if t == "script"] + [
            k for _t, a in got for k, _v in a if k.startswith("on")]
        check("round trip: %s — the HTML parser reads the same %d element(s), "
              "no script, no on*" % (label, len(want)),
              got == want and not bad and p.seq[0][0] == "div",
              "\n  html: %r\n  xml:  %r" % (got, want))

    write(tmp, "figures/trailing.svg",
          '<svg viewBox="0 0 1 1"></svg><iframe src="https://evil.example/"></iframe>')
    refused("trailing HTML after the root refuses the BUILD",
            pre + '::: figure {src="figures/trailing.svg"}\n:::\n', tmp, 3,
            "does not parse")
    write(tmp, "figures/comment-first.svg",
          '<!-- <svgx> is not the root --><svg viewBox="0 0 2 2"><rect/></svg>\n')
    html = build('::: figure {src="figures/comment-first.svg"}\n:::\n', base_dir=tmp)
    check("the root is found past a leading comment, and only it is inlined",
          '<figure style="max-width:2px">\n<svg data-embed="%s" viewBox="0 0 2 2">'
          '<rect/></svg>\n</figure>'
          % hashlib.sha256(b'<!-- <svgx> is not the root --><svg viewBox="0 0 2 2">'
                           b'<rect/></svg>\n').hexdigest()[:8] in html, html)
    # BL-511: no usable viewBox width, no cap — the browser does not scale such a
    # drawing, so there is nothing to hold back, and a bad number must not reach CSS.
    for name, root in (("no viewBox", "<svg>"),
                       ("a NaN width", '<svg viewBox="0 0 nan 10">'),
                       ("three numbers", '<svg viewBox="0 0 360">'),
                       ("a zero width", '<svg viewBox="0 0 0 10">')):
        write(tmp, "figures/nocap.svg", root + "<rect/></svg>\n")
        html = build('::: figure {src="figures/nocap.svg"}\n:::\n', base_dir=tmp)
        check("%s: the <figure> carries no max-width" % name,
              "<figure>\n<svg data-embed=" in html and "max-width" not in html, html)
    write(tmp, "figures/svgx.svg", '<svgx></svgx>\n')
    refused("<svgx> is not an <svg> root",
            pre + '::: figure {src="figures/svgx.svg"}\n:::\n', tmp, 3,
            "holds no <svg>")
    write(tmp, "figures/hex.svg", '<svg><rect fill="#123456"/><script>1</script></svg>')
    refused("an svg breaking the rules is refused at the fence, every rule named",
            pre + '::: figure {src="figures/hex.svg"}\n:::\n', tmp, 3,
            "is refused", "<script>", '<rect fill="#123456">')

    print()
    print("== figure_extract.py: figure N of a page, as a file ==")
    sys.path.insert(0, HERE)
    import figure_extract
    page = write(tmp, "page.html", (
        "<main><figure>%s<figcaption>c</figcaption></figure>\n"
        '<p>x</p><figure><img alt="a" src="data:image/png;base64,%s"></figure>\n'
        "<figure><table><tr><td>t</td></tr></table></figure></main>\n")
        % (SVG, base64.b64encode(PNG).decode("ascii")))
    check("an svg figure is its <svg> element, byte for byte",
          figure_extract.extract(page, 1) == ("svg", SVG.encode("utf-8")))
    check("a data-URI png is decoded to the file it encodes",
          figure_extract.extract(page, 2) == ("png", PNG))
    for n, needle in ((3, "neither"), (4, "has 3 figure"), (0, "has 3 figure")):
        try:
            figure_extract.extract(page, n)
            check("figure %d is refused" % n, False, "extracted")
        except ValueError as e:
            check("figure %d is refused (%s)" % (n, needle), needle in str(e), str(e))

    print()
    print("== the page ==")
    one = build('::: figure {src="figures/a.svg" title="t"}\n:::\n'
                '::: figure {src="figures/shot.png" alt="a"}\n:::\n', base_dir=tmp)
    two = build('::: figure {src="figures/a.svg" title="t"}\n:::\n'
                '::: figure {src="figures/shot.png" alt="a"}\n:::\n', base_dir=tmp)
    check("the same spec builds byte-identically twice", one == two)

    page = ('::: masthead {visual="svg"}\n# Una figura\n\nUna página con su '
            'dibujo.\n:::\n\n%s::: notes {title="Notas generales"}\n:::\n')
    for label, fig, want in [
            ("with a figure, a masthead declaring visual=\"svg\" passes the "
             "contract", '::: figure {src="figures/a.svg" title="t"}\n:::\n\n', 0),
            ("…and without one the same page fails it: the declaration is "
             "not the drawing", "", 1)]:
        spec = write(tmp, "page.spec.md", page % fig)
        out = os.path.join(tmp, "reports", "page.html")
        if os.path.exists(out):
            os.remove(out)
        # From `/`: src is relative to the SPEC, never to the cwd.
        r = subprocess.run([sys.executable, BUILD, spec, "-o", out],
                           capture_output=True, text=True, cwd="/")
        said = r.stdout + r.stderr
        check(label, (r.returncode == 0) == (want == 0)
              and (want == 0 or "no visual" in said),
              "exit %d: %s" % (r.returncode, said[-600:]))


def run_shots(tmp):
    """BL-493/BL-626: an item's figures (raster or svg) written together are one
    `.gal.shots` grid (2-4 columns by count); a lone figure stays full width and
    carries `data-viewer`;
    and the page built from such an item passes the contract (an item with a
    `.gal` is NOT judged as a gallery row)."""
    write(tmp, "figures/a.svg", SVG + "\n")
    for n in "1234567":
        write(tmp, "figures/s%s.png" % n, PNG)

    def item(*figs):
        return ('::: item {#Q1 title="T"}\n¿Cuál?\n\n%s\n- A — uno\n- B — dos\n:::'
                % "".join('::: figure {src="figures/%s"%s}\n:::\n\n'
                          % (f, "" if f.endswith(".svg") else ' alt="c"')
                          for f in figs))

    print()
    print("== an item's images: a thumbnail grid (BL-493) ==")
    html = build(item("s1.png", "s2.png", "s3.png", "s4.png"), base_dir=tmp)
    grid = html.split('<div class="gal shots"', 1)[-1].split("</div>", 1)[0]
    check("four rasters are one grid of four figures, four columns",
          html.count('<div class="gal shots" data-cols="4">') == 1
          and grid.count("<figure") == 4, html[:400])
    check("...between the question and the options",
          html.index("¿Cuál?") < html.index("gal shots") < html.index('type="radio"'))
    for n, cols in ((2, 2), (3, 3), (5, 4), (7, 4)):
        html = build(item(*["s%d.png" % i for i in range(1, n + 1)]), base_dir=tmp)
        check("%d rasters make %d columns" % (n, cols),
              'class="gal shots" data-cols="%d"' % cols in html)
    html = build(item("s1.png"), base_dir=tmp)
    check("one raster stays a lone full-width figure, marked for the viewer (BL-626)",
          'class="gal' not in html and html.count("<figure") == 1
          and html.count("<figure data-viewer") == 1)
    html = build(item("a.svg"), base_dir=tmp)
    check("one svg stays a lone full-width figure, marked for the viewer (BL-626)",
          'class="gal' not in html and html.count("<figure data-viewer") == 1)
    html = build(item("a.svg", "s1.png"), base_dir=tmp)
    grid = html.split('<div class="gal shots"', 1)[-1].split("</div>", 1)[0]
    check("an svg and one raster are one mixed grid of two, in written order (BL-626)",
          'class="gal shots" data-cols="2"' in html and grid.count("<figure") == 2
          and grid.index("<svg") < grid.index("<img") and "data-viewer" not in html, html[:500])
    html = build(item("s1.png", "a.svg", "s2.png"), base_dir=tmp)
    grid = html.split('<div class="gal shots"', 1)[-1].split("</div>", 1)[0]
    check("an svg between two rasters stays inside the one grid of three (BL-626)",
          'class="gal shots" data-cols="3"' in html and grid.count("<figure") == 3
          and grid.index("<img") < grid.index("<svg") < grid.rindex("<img"), html[:500])
    prose = ('::: item {#Q1 title="T"}\n¿Cuál?\n\n::: figure {src="figures/s1.png" alt="c"}\n:::\n\n'
             'Una frase entre las dos.\n\n::: figure {src="figures/s2.png" alt="c"}\n:::\n\n- A — uno\n- B — dos\n:::')
    html = build(prose, base_dir=tmp)
    check("prose between two rasters splits the run: no grid, order kept",
          'class="gal' not in html and html.count("<figure") == 2
          and html.index("<img") < html.index("Una frase entre las dos.")
          < html.rindex("<img"), html[:500])
    html = build(item("s1.png", "s2.png", "a.svg"), base_dir=tmp)
    grid = html.split('<div class="gal shots"', 1)[-1].split("</div>", 1)[0]
    check("two rasters then an svg: the grid holds all three (BL-626)",
          grid.count("<figure") == 3 and "<svg" in grid)
    html = build(item("s1.png", "s2.png").replace("- A — uno", "::: chart {type=bar title=\"c\"}\nx,1\n:::\n\n- A — uno"),
                 base_dir=tmp)
    check("a chart after the figures is not a figure: it ends the run, outside the grid",
          'data-cols="2"' in html and "<svg" not in html.split('<div class="gal shots"', 1)[-1].split("</div>", 1)[0]
          and "<svg" in html)

    spec = write(tmp, "shots.spec.md", ('::: masthead {visual="none: capturas, no dibujo"}\n'
        '# Capturas\n\nUna página con capturas.\n:::\n\n::: group {#G title="Grupo"}\n%s\n:::\n\n'
        '::: notes {title="Notas generales"}\n:::\n' % item(
            "s1.png", "s2.png", "s3.png", "s4.png")))
    out = os.path.join(tmp, "reports", "shots.html")
    r = subprocess.run([sys.executable, BUILD, spec, "-o", out],
                       capture_output=True, text=True, cwd="/")
    check("the page with the grid passes check-artifact (not a gallery row)",
          r.returncode == 0, (r.stdout + r.stderr)[-500:])
    spec = write(tmp, "mixed.spec.md", ('::: masthead {visual="none: capturas, no dibujo"}\n'
        '# Mixta\n\nUna página con una cuadrícula png + svg.\n:::\n\n::: group {#G title="Grupo"}\n%s\n:::\n\n'
        '::: notes {title="Notas generales"}\n:::\n' % item("s1.png", "a.svg")))
    out = os.path.join(tmp, "reports", "mixed.html")
    r = subprocess.run([sys.executable, BUILD, spec, "-o", out],
                       capture_output=True, text=True, cwd="/")
    check("the page with a mixed png+svg grid passes check-artifact (BL-626)",
          r.returncode == 0 and 'class="gal shots" data-cols="2"' in open(out, encoding="utf-8").read(),
          (r.stdout + r.stderr)[-500:])


if __name__ == "__main__":
    sys.exit(main())
