#!/usr/bin/env python3
"""Write figure N of a page to a file, byte for byte, and print its sha256.

    python3 figure_extract.py <page.html> <N> <out-stem>

N is 1-based over EVERY `<figure>` of the page in document order — the same
numbering `goal_gate.FIGURE_ELEMENT` gives the figure census. The figure's first
`<svg>…</svg>` is written as `<out-stem>.svg`, exactly as the page holds it; a
base64 data-URI `<img>` is DECODED to `<out-stem>.png` / `.jpg`. Nothing is
repaired: a drawing that breaks the kit's SVG rules is extracted as it is, and
the `::: figure` block is what refuses it.

Prints `<path> <sha256> <ext>`. Exit 1 when figure N does not exist or holds
neither an inline SVG nor a data-URI image.
"""
import base64
import hashlib
import os
import re
import sys

# Every `<figure>` of a page, in document order. The ONE numbering: the figure
# census's `fig=` and the goal gate both read it from here.
FIGURE_ELEMENT = re.compile(r"<figure\b.*?</figure>", re.S | re.I)
SVG = re.compile(r"<svg\b.*?</svg>", re.S | re.I)
IMG = re.compile(r'<img\b[^>]*?\bsrc\s*=\s*["\']data:image/(png|jpe?g);base64,'
                 r'([^"\']+)["\']', re.S | re.I)


def extract(page, n):
    """`(ext, bytes)` of figure `n` of `page`, or raise ValueError."""
    with open(page, encoding="utf-8", errors="replace") as fh:
        figs = FIGURE_ELEMENT.findall(fh.read())
    if not 1 <= n <= len(figs):
        raise ValueError("the page has %d figure(s), not a figure %d"
                         % (len(figs), n))
    fig = figs[n - 1]
    svg, img = SVG.search(fig), IMG.search(fig)
    if svg and (not img or svg.start() < img.start()):
        return "svg", svg.group(0).encode("utf-8")
    if img:
        ext = "png" if img.group(1).lower() == "png" else "jpg"
        return ext, base64.b64decode(re.sub(r"\s+", "", img.group(2)))
    raise ValueError("figure %d holds neither an inline <svg> nor a data-URI "
                     "<img>" % n)


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: figure_extract.py <page.html> <N> <out-stem>\n")
        return 2
    try:
        ext, data = extract(argv[0], int(argv[1]))
    except ValueError as e:
        sys.stderr.write("figure-extract: %s\n" % e)
        return 1
    out = "%s.%s" % (argv[2], ext)
    with open(out, "wb") as fh:
        fh.write(data)
    print("%s %s %s" % (out, hashlib.sha256(data).hexdigest(), ext))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
