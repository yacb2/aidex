#!/usr/bin/env python3
"""Wrap ad-hoc report content in the document envelope (route B of the
local-first artifact rule). Logic lives here; wrap-report.sh is the entry.

Reads page content on stdin — exactly what `artifact-design` teaches you to
write, and exactly what the Artifact tool expects at publish time: styles and
markup, no doctype/html/head/body of your own. Emits a complete document on
stdout by calling the same `_shell.document()` the dash renderers use.

A leading <style>...</style> block in the input is lifted into <head> so the
page's own rules sit after the minimal reset and win; everything else stays in
<body>.
"""
import argparse
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from _shell import document  # noqa: E402

LEADING_STYLE = re.compile(r"\A\s*((?:<style\b[^>]*>.*?</style>\s*)+)", re.S | re.I)


def split_head_style(content):
    """Return (head_extra, body). Only a style block at the very top is lifted —
    a <style> further down is the author's deliberate placement, left alone."""
    m = LEADING_STYLE.match(content)
    if not m:
        return "", content.strip()
    return m.group(1).strip(), content[m.end():].strip()


def main():
    p = argparse.ArgumentParser(description="Wrap report content in the document envelope")
    p.add_argument("--title", required=True, help="document title (browser tab)")
    p.add_argument("--lang", default="en", help="BCP-47 language of the content (default: en)")
    p.add_argument("--favicon", default="", help="one or two emoji for the tab icon")
    p.add_argument("--in", dest="infile", help="read content from this file instead of stdin")
    args = p.parse_args()

    content = (open(args.infile, encoding="utf-8").read() if args.infile
               else sys.stdin.read())
    if not content.strip():
        print("ERROR: no content on stdin (nothing to wrap)", file=sys.stderr)
        return 2
    if re.search(r"<!doctype\s+html", content, re.I):
        print("ERROR: content already has a doctype — pass page content only, "
              "not a full document", file=sys.stderr)
        return 2

    head_extra, body = split_head_style(content)
    sys.stdout.write(document(args.title, body, lang=args.lang,
                              favicon=args.favicon, head_extra=head_extra))
    return 0


if __name__ == "__main__":
    sys.exit(main())
