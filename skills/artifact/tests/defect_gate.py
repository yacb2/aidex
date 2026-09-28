#!/usr/bin/env python3
"""The contract-defect gate (LOOP-006). Four lines, one fixed order, every run:

    classes: K/N   N = the union of contract_defects.CHECKS (source
                   classes), RENDER (render classes) and the registry's folders
                   (a class with no folder, or a folder with no check, still
                   counts in N); K = those with a check AND an original
    red: R/N       classes whose check FAILS on every `original*.html` (a class
                   frozen on two real pages is red only when both are)
    green: G/N     classes whose check PASSES on `rebuilt.html`; absent, empty,
                   or with no <main> (not a page) = not green
    corpus: C/T    T = the goal-gate corpus pages (AIDEX_SPEC_CORPUS's
                   corpus-sample.json) plus every rebuilt.html that exists;
                   C = those clean on every gate (below)

A render class is judged by the rendered page, not the source:
`render-probe.sh --contract SLUG PAGE` (render-probe.mjs behind it). Red needs
exit 1 AND a stdout line `CONTRACT <slug> findings=<n>` with n >= 1; green needs
exit 0 AND `CONTRACT <slug> findings=0`. Anything else — another exit code, a
missing line, a run past AIDEX_PROBE_TIMEOUT seconds (default 60) — is an error,
neither red nor green: until that CLI exists (or with no Playwright) the render
classes count in N and in K and never in R or G. AIDEX_RENDER_PROBE replaces the
probe script (the tests drive the gate with fakes).

The corpus line is FULL by default — the loop's stop condition (LOOP-006
decision 4): a page is clean when every source check passes, `check-artifact.sh`
and `render-probe.sh` exit 0 on it, and every render class answers clean
(Playwright via AIDEX_PLAYWRIGHT_DIR). AIDEX_CORPUS_FAST=1 is the opt-in fast
path: source checks only, printed as `corpus: C/T (source only)` so a fast line
is never read as the stop condition.

Exit 0 only when every numerator equals its denominator and N >= MIN_CLASSES.

The registry holds the owner's real pages, so like the corpus it is private and
lives outside this repo, wherever AIDEX_DEFECT_REGISTRY points (one folder per
class: original.html [, original-2.html …], class.md, later rebuilt.html).
Unset, or not a directory: `classes/red/green: 0/unknown` and exit 1. The
corpus unset reads `corpus: 0/unknown`, never 0/0. `--verbose` lists every
failing page on stderr with what it failed (`<slug>`, `check-artifact rc=N`,
`render-probe rc=N`, `<render slug> (no answer)`).
"""

import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "scripts", "dash"))

import contract_defects                                     # noqa: E402

MIN_CLASSES = 4          # the loop spec's floor: N >= 4
SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(SCRIPTS, "render-probe.sh")
TIMEOUT = float(os.environ.get("AIDEX_PROBE_TIMEOUT") or 60)     # seconds per page
CHECK_ARTIFACT = os.path.join(SCRIPTS, "check-artifact.sh")
# Classes decided on the rendered page by render-probe's `--contract SLUG`.
RENDER = ("text-style-drift", "figure-text-contrast", "svg-label-outside-its-box")


def _run(cmd):
    """(exit code, stdout) of a gate script; (None, "") past TIMEOUT."""
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                           text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, ""
    return r.returncode, r.stdout


def verdict(slug, page):
    """True = a finding, False = clean, None = could not tell (render error)."""
    if slug in contract_defects.CHECKS:
        return bool(contract_defects.findings(page, [slug]))
    rc, out = _run(["bash", PROBE, "--contract", slug, page])
    m = re.search(r"^CONTRACT %s findings=(\d+)\s*$" % re.escape(slug), out, re.M)
    if m and rc == 1 and int(m.group(1)) >= 1:
        return True
    if m and rc == 0 and int(m.group(1)) == 0:
        return False
    return None


def corpus_failures(page, fast, every):
    """What `page` fails, in gate order; stops at the first unless `every`."""
    out = sorted({s for s, _, _ in contract_defects.findings(page)})
    if fast or (out and not every):
        return out
    for name, cmd in (("check-artifact", ["bash", CHECK_ARTIFACT, page]),
                      ("render-probe", ["bash", PROBE, page])):
        rc, _ = _run(cmd)
        if rc != 0:
            out.append("%s %s" % (name, "timeout" if rc is None else "rc=%d" % rc))
            if not every:
                return out
    for slug in RENDER:
        v = verdict(slug, page)
        if v is not False:
            out.append("%s (%s)" % (slug, "finding" if v else "no answer"))
            if not every:
                return out
    return out


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
    slugs = sorted(set(folders) | set(contract_defects.CHECKS) | set(RENDER))
    n = len(slugs)
    known = red = green = 0
    rebuilt = []
    for slug in slugs:
        folder = os.path.join(registry, slug)
        originals = sorted(glob.glob(os.path.join(folder, "original*.html")))
        if (slug not in contract_defects.CHECKS and slug not in RENDER) \
                or not originals:
            if verbose:
                print("  unknown class: %s" % slug, file=sys.stderr)
            continue
        known += 1
        if all(verdict(slug, p) is True for p in originals):
            red += 1
        elif verbose:
            print("  not red: %s" % slug, file=sys.stderr)
        again = os.path.join(folder, "rebuilt.html")
        if os.path.isfile(again):
            rebuilt.append(again)
            if is_page(again) and verdict(slug, again) is False:
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
        fast = os.environ.get("AIDEX_CORPUS_FAST") == "1"
        clean = 0
        for page in pages:
            if not (is_page(page) if page in rebuilt else os.path.isfile(page)):
                if verbose:
                    print("  not a page: %s" % page, file=sys.stderr)
                continue
            failed = corpus_failures(page, fast, verbose)
            if not failed:
                clean += 1
            elif verbose:
                print("  %s: %s" % (page, ", ".join(failed)), file=sys.stderr)
        lines.append("corpus: %d/%d%s" % (clean, len(pages),
                                          " (source only)" if fast else ""))
        corpus_ok = clean == len(pages)

    print("\n".join(lines))
    return 0 if (reg_ok and corpus_ok) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
