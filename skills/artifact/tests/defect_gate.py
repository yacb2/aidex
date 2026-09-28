#!/usr/bin/env python3
"""The contract-defect gate (LOOP-006). Four lines, one fixed order, every run:

    classes: K/N   N = the union of contract_defects.CHECKS and the registry's
                   folders (a class with no folder, or a folder with no check,
                   still counts in N); K = those with a check AND an original
    red: R/N       classes whose check FAILS on every `original*.html` (a class
                   frozen on two real pages is red only when both are)
    green: G/N     classes whose check PASSES on `rebuilt.html`; absent, empty,
                   or with no <main> (not a page) = not green
    corpus: C/T    T = the goal-gate corpus pages (AIDEX_SPEC_CORPUS's
                   corpus-sample.json) plus every rebuilt.html that exists;
                   C = those with no finding from any check

Exit 0 only when every numerator equals its denominator and N >= MIN_CLASSES.

The registry holds the owner's real pages, so like the corpus it is private and
lives outside this repo, wherever AIDEX_DEFECT_REGISTRY points (one folder per
class: original.html [, original-2.html …], class.md, later rebuilt.html).
Unset, or not a directory: `classes/red/green: 0/unknown` and exit 1. The
corpus unset reads `corpus: 0/unknown`, never 0/0. `--verbose` lists every
failing page on stderr.
"""

import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts", "dash"))

import contract_defects                                     # noqa: E402

MIN_CLASSES = 4          # the loop spec's floor: N >= 4


def corpus_pages():
    """[abs path] of the goal-gate sample, or None when it cannot be read."""
    corpus = os.environ.get("AIDEX_SPEC_CORPUS", "")
    sample = os.path.join(corpus, "corpus-sample.json") if corpus else ""
    if not sample or not os.path.isfile(sample):
        return None
    data = json.load(open(sample, encoding="utf-8"))
    root = os.path.expanduser(data["root"])
    return [os.path.join(root, p["path"]) for p in data["pages"]]


def is_page(path):
    """A rebuilt page is a page: non-empty and carrying a <main>."""
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return False
    text = open(path, encoding="utf-8", errors="replace").read()
    try:
        tree = contract_defects.parse(text)
    except Exception:                                # noqa: BLE001 — not a page
        return False
    return any(n.tag == "main" for n in tree.root.walk())


def registry_lines(registry, verbose):
    """(lines, all_full, rebuilt pages)."""
    folders = sorted(d for d in os.listdir(registry)
                     if os.path.isdir(os.path.join(registry, d)))
    slugs = sorted(set(folders) | set(contract_defects.CHECKS))
    n = len(slugs)
    known = red = green = 0
    rebuilt = []
    for slug in slugs:
        folder = os.path.join(registry, slug)
        originals = sorted(glob.glob(os.path.join(folder, "original*.html")))
        if slug not in contract_defects.CHECKS or not originals:
            if verbose:
                print("  unknown class: %s" % slug, file=sys.stderr)
            continue
        known += 1
        if all(contract_defects.findings(p, [slug]) for p in originals):
            red += 1
        elif verbose:
            print("  not red: %s" % slug, file=sys.stderr)
        again = os.path.join(folder, "rebuilt.html")
        if os.path.isfile(again):
            rebuilt.append(again)
            if is_page(again) and not contract_defects.findings(again, [slug]):
                green += 1
            elif verbose:
                print("  not green: %s" % slug, file=sys.stderr)
    lines = ["classes: %d/%d" % (known, n), "red: %d/%d" % (red, n),
             "green: %d/%d" % (green, n)]
    return lines, (known == red == green == n and n >= MIN_CLASSES), rebuilt


def main(argv):
    verbose = "--verbose" in argv
    registry = os.environ.get("AIDEX_DEFECT_REGISTRY", "")
    if registry and os.path.isdir(registry):
        lines, reg_ok, rebuilt = registry_lines(registry, verbose)
    else:
        print("defect-gate: AIDEX_DEFECT_REGISTRY unset or not a directory — "
              "the classes were not measured", file=sys.stderr)
        lines = ["classes: 0/unknown", "red: 0/unknown", "green: 0/unknown"]
        reg_ok, rebuilt = False, []

    pages = corpus_pages()
    if pages is None:
        print("defect-gate: AIDEX_SPEC_CORPUS unset or without "
              "corpus-sample.json — the corpus was not measured", file=sys.stderr)
        lines.append("corpus: 0/unknown")
        corpus_ok = False
    else:
        pages += rebuilt
        clean = 0
        for page in pages:
            if not (is_page(page) if page in rebuilt else os.path.isfile(page)):
                if verbose:
                    print("  not a page: %s" % page, file=sys.stderr)
                continue
            found = contract_defects.findings(page)
            if not found:
                clean += 1
            elif verbose:
                for s, line, msg in found:
                    print("  %s:%d [%s] %s" % (page, line, s, msg), file=sys.stderr)
        lines.append("corpus: %d/%d" % (clean, len(pages)))
        corpus_ok = clean == len(pages)

    print("\n".join(lines))
    return 0 if (reg_ok and corpus_ok) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
