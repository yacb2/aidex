#!/usr/bin/env python3
"""Verify one converted page: build its spec, diff ids and visible text.

Usage:
    python3 corpus_diff.py <spec.md> <original.html>     # human-readable diff
    python3 corpus_diff.py --quiet <spec.md> <original>  # exit status only

Exit 0 when the conversion is clean: the `data-id` sequence is IDENTICAL and
the visible-text token sequence is IDENTICAL. One allowance (owner ruling
2026-09-28, the consult contract wins): a group id or the general-notes item
that only the build has is not counted, the notes item's title with it, as long
as every original id keeps its order. Each option's input type (radio or
checkbox), and which option is recommended and which is checked, are compared
too (`corpus_html.option_flags`, rule in `_first_flag_divergence`). Inside an option's label the " — "
separator the builder leaves implicit and the kit's badge word are read in one
canonical form (`corpus_html.py`). Exit 1 otherwise, with the first
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

    wi = corpus_html.ids(want)
    gi = corpus_html.ids(got, skip=_contract_additions(got, set(wi)))
    if wi != gi:
        problems.append("ids differ\n  original: %s\n  built:    %s\n%s"
                        % (wi, gi, _unified(wi, gi, "id")))

    wt, gt = corpus_html.tokens(want), corpus_html.tokens(got)
    if wt != gt:
        problems.append("visible text differs (%d words in the page, %d built)\n%s"
                        % (len(wt), len(gt), _first_divergence(wt, gt)))

    wf = corpus_html.option_flags(want, original=True)
    gf = corpus_html.option_flags(got)
    bad = _first_flag_divergence(wf, gf)
    if bad:
        problems.append("option marks differ\n" + bad)

    return not problems, problems


def _first_flag_divergence(want, got):
    """The first option whose marks drifted, or "" when they hold.

    The input type (radio or checkbox) and recommended must be identical.
    Checked must hold for every option the original checked; the build may
    ALSO check the recommended option of an item the ORIGINAL marks decided
    and in which it checked no option
    (`open_verdict`; `decided=yes` shows a verdict: the consult contract wins,
    owner ruling 2026-09-28).
    """
    def show(f):
        return "%s recommended=%s checked=%s" % (f[4], f[1], f[2])
    if len(want) != len(got):
        return "  %d options in the page, %d built" % (len(want), len(got))
    for i, (w, g) in enumerate(zip(want, got)):
        if w[4] != g[4] or w[1] != g[1] or (w[2] and not g[2]) or (g[2] and not w[2] and not (g[1] and w[3])):
            return ("  option %d (%s): original %s, built %s"
                    % (i + 1, w[0][:50], show(w), show(g)))
    return ""


def _contract_additions(got, original_ids):
    """The consult contract's own blocks that the build added: the group
    nodes whose id the page never had (returned, so their id is skipped), and
    the general-notes item likewise (detached from `got`, its title with it) —
    one notes item at most: a second one is an added id like any other.

    Owner ruling 2026-09-28: the consult contract wins over this judge. A page
    rewritten to put its items in groups and give the reader a notes box is
    still the same page when every ORIGINAL id keeps its order — the caller's
    comparison still fails any other added, missing or reordered id. A group's
    heading is not exempt: it is compared as visible text like any heading.
    """
    groups, notes_done = [], False
    for node in list(got.walk()):
        ident = node.attrs.get("data-id")
        if ident is None or ident in original_ids:
            continue
        if node.has("consult-notes") and not notes_done:   # a page has ONE
            node.parent.children.remove(node)
            notes_done = True
        elif node.has("consult-group"):
            groups.append(node)
    return groups


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
