#!/usr/bin/env python3
"""Wrap ad-hoc report content in the document envelope (route B of the
local-first artifact rule). Logic lives here; wrap-report.sh is the entry.

Reads page content on stdin — exactly what `artifact-design` teaches you to
write, and exactly what the Artifact tool expects at publish time: styles and
markup, no doctype/html/head/body of your own. Emits a complete document on
stdout by calling the same `_shell.document()` the dash renderers use, or writes it to
`--out <file>` and verifies the artifact contract on that file before returning.

A leading <style>...</style> block in the input is lifted into <head> so the
page's own rules sit after the minimal reset and win; everything else stays in
<body>.
"""
import argparse
import os
import re
import subprocess
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
    p.add_argument("--out", dest="outfile",
                   help="write the document here and run check-artifact.sh on it. Prefer "
                        "this over a shell redirect: the contract check is the step a run "
                        "drops first, and it cannot run against a pipe (BL-126)")
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
    doc = document(args.title, body, lang=args.lang,
                   favicon=args.favicon, head_extra=head_extra)

    if not args.outfile:
        sys.stdout.write(doc)
        # A pipe has no path, so the `siblings` check has no directory to scan and the
        # caller is free to never run the check at all — which is what happened in 1 of 2
        # field probes. Make the omission audible instead of silent.
        print("NOTE: wrapped to stdout, so the artifact contract was NOT verified. "
              "Re-run with --out <file> to have it checked, or run check-artifact.sh "
              "on the file yourself.", file=sys.stderr)
        return 0

    # Create at most ONE missing level, and only when its own parent exists.
    #
    # The documented anchorless fallback writes to `.context/reports/`, a directory
    # that does not exist until the first report — so the procedure's own happy path
    # used to end in a traceback. But an unconditional makedirs is the wrong fix:
    # both failures observed in the field were a WRONG CWD, and makedirs would have
    # turned each into a silently misplaced file instead of an error. One level deep
    # tells the two apart, because a wrong cwd is missing more than the leaf.
    outdir = os.path.dirname(os.path.abspath(args.outfile))
    if not os.path.isdir(outdir):
        if os.path.isdir(os.path.dirname(outdir)):
            os.makedirs(outdir, exist_ok=True)
        else:
            print(f"ERROR: cannot write {args.outfile} — {outdir} does not exist and "
                  f"neither does its parent, so this is a wrong working directory "
                  f"rather than a first report (cwd={os.getcwd()})", file=sys.stderr)
            return 4

    with open(args.outfile, "w", encoding="utf-8") as fh:
        fh.write(doc)

    checker = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "check-artifact.sh")
    if not os.path.isfile(checker):
        print(f"ERROR: wrote {args.outfile} but check-artifact.sh is missing at {checker} "
              f"— the contract was not verified", file=sys.stderr)
        return 3
    # Say where it landed, absolutely. `--out` takes a relative path in the
    # documented flow, so a run standing in the wrong project writes a perfectly
    # valid report into a neighbour's `.context/` and exits 0 — the one-level
    # makedirs cannot tell that apart from a first report, and widening it would
    # break the primary placement (a report is a sibling of its anchor, anywhere
    # in the tree). Printing the resolved path is what makes the landing visible,
    # and it is this suite's own rule for consultation pages.
    print(os.path.abspath(args.outfile))

    rc = subprocess.run(["bash", checker, args.outfile]).returncode
    if rc != 0:
        print(f"ERROR: {args.outfile} was written but FAILS the artifact contract above. "
              f"Fix the content and re-run; do not open or hand over this file.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
