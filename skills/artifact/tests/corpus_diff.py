#!/usr/bin/env python3
"""Verify one converted page: build its spec, diff ids and visible text.

Usage:
    python3 corpus_diff.py <spec.md> <original.html>     # human-readable diff
    python3 corpus_diff.py --quiet <spec.md> <original>  # exit status only

Exit 0 when the conversion is clean: the `data-id` sequence is IDENTICAL and
the visible-text token sequence is IDENTICAL. Exit 1 otherwise, with the first
divergence printed in context — a conversion is never eyeballed, so the failure
has to say which word drifted and where.

What counts as visible text, and what is excluded from both sides, is
`corpus_html.py`'s single definition; read its docstring before arguing with a
diff this prints.
"""

import argparse
import difflib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts"))

import corpus_html                                       # noqa: E402
import spec_build                                        # noqa: E402
from spec_parser import SpecSyntaxError                   # noqa: E402

CONTEXT = 6


def build_body(spec_path, lang="es"):
    with open(spec_path, encoding="utf-8") as fh:
        text = fh.read()
    return spec_build.build(text, lang=lang,
                            base_dir=os.path.dirname(os.path.abspath(spec_path)))


def compare(spec_path, page_path, lang="es"):
    """`(ok, [problem, ...])`."""
    try:
        body = build_body(spec_path, lang=lang)
    except (SpecSyntaxError, spec_build.SpecBuildError) as exc:
        return False, ["build refused the spec at line %d: %s"
                       % (exc.line, exc.message)]
    return compare_body(body, page_path)


def compare_body(body, page_path):
    """`compare`, for a body the caller already built — the goal gate builds
    each spec once and needs to know, besides the diff, whether it built."""
    with open(page_path, encoding="utf-8") as fh:
        page = fh.read()

    want = corpus_html.content_root(page)
    got = corpus_html.content_root(body)

    problems = []

    wi, gi = corpus_html.ids(want), corpus_html.ids(got)
    if wi != gi:
        problems.append("ids differ\n  original: %s\n  built:    %s\n%s"
                        % (wi, gi, _unified(wi, gi, "id")))

    wt, gt = corpus_html.tokens(want), corpus_html.tokens(got)
    if wt != gt:
        problems.append("visible text differs (%d words in the page, %d built)\n%s"
                        % (len(wt), len(gt), _first_divergence(wt, gt)))

    return not problems, problems


def _unified(a, b, label):
    lines = difflib.unified_diff(a, b, fromfile="original " + label + "s",
                                 tofile="built " + label + "s", lineterm="",
                                 n=2)
    return "\n".join("  " + ln for ln in lines)


def _first_divergence(want, got):
    """The first word that drifted, with the words either side of it.

    A whole-text diff of a 25,000-word page is unreadable and, worse, invites
    eyeballing. One divergence at a time is what a fix cycle actually uses.
    """
    sm = difflib.SequenceMatcher(None, want, got, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        lo = max(0, i1 - CONTEXT)
        out = [
            "  first divergence at word %d of the page (%d of the build):" % (i1, j1),
            "    before:   …%s" % " ".join(want[lo:i1]),
            "    original: %s" % (" ".join(want[i1:i1 + CONTEXT]) or "(nothing)"),
            "    built:    %s" % (" ".join(got[j1:j1 + CONTEXT]) or "(nothing)"),
        ]
        n = sum(1 for t, *_ in sm.get_opcodes() if t != "equal")
        out.append("  %d divergent run(s) in all" % n)
        return "\n".join(out)
    return "  (no divergence found — lengths differ only in trailing blanks)"


def main(argv):
    p = argparse.ArgumentParser(prog="corpus_diff.py", description=__doc__.split("\n")[0])
    p.add_argument("spec")
    p.add_argument("page")
    p.add_argument("--lang", default="es")
    p.add_argument("--quiet", action="store_true")
    args = p.parse_args(argv)

    ok, problems = compare(args.spec, args.page, lang=args.lang)
    if not args.quiet:
        if ok:
            print("clean: %s" % os.path.basename(args.spec))
        else:
            print("DIRTY: %s" % os.path.basename(args.spec))
            for pr in problems:
                print(pr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
