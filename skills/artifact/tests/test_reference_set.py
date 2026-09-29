#!/usr/bin/env python3
"""reference-set.sh: every manifest entry lands on the built page, or the run fails.

Layer: script integration, no browser (`--no-probe`); the probe half is
`test-render-probe.sh`'s. Regressions caught: an entry dropped from the page, an
engine figure not built, a not-expressible reason not shown, and a manifest row
whose directory is missing being skipped instead of failing loudly.

Stdlib only: `python3 test_reference_set.py`, prints OK, exits 0.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(os.path.dirname(HERE), "scripts", "reference-set.sh")
FIXTURE = os.path.join(HERE, "fixtures", "reference-set")
failures = []


def check(label, cond, detail=""):
    if cond:
        print("  ok: " + label)
    else:
        failures.append(label)
        print("FAIL: %s%s" % (label, (": " + detail) if detail else ""))


def run(set_dir, out_dir):
    return subprocess.run(["bash", SCRIPT, "--no-probe", set_dir, out_dir],
                          capture_output=True, text=True)


tmp = tempfile.mkdtemp(prefix="test-reference-set-")
try:
    print("== a complete set ==")
    out = os.path.join(tmp, "out")
    r = run(FIXTURE, out)
    check("the build succeeds", r.returncode == 0, r.stdout + r.stderr)
    page = os.path.join(out, "reference-set.html")
    html = open(page, encoding="utf-8").read() if os.path.isfile(page) else ""
    manifest = open(os.path.join(FIXTURE, "set.tsv"), encoding="utf-8").read()
    ids = [ln.split("\t")[0] for ln in manifest.splitlines()[1:] if ln.strip()]
    for ident in ids:
        check("entry %s: its id is in a section heading" % ident,
              re.search(r"<h2[^>]*>[^<]*\b%s\b" % ident, html) is not None)
        check("entry %s: its baseline figure is on the page" % ident,
              'id="%s-base"' % ident in html)
    check("alfa: the engine figure is on the page", 'id="alfa-eng"' in html)
    check("alfa: its boxes are drawn", "Paso tres" in html)
    check("beta: the reason is shown", "No expresable todavía: wireframe: "
          "razón sintética de prueba" in html)
    check("beta: no engine figure", 'id="beta-eng"' not in html)
    h1 = re.search(r"<h1[^>]*>(.*?)</h1>", html, re.S)
    check("the H1 states the finding, counted from the manifest (1 of 2)",
          h1 is not None and "El motor dibuja 1 de 2 figuras" in h1.group(1),
          h1.group(1) if h1 else "no h1")
    check("the count line for one says it in the singular",
          '">1 no es expresable todavía. Cada sección' in html)
    check("the handoff prints the page and the rubric, no shots without a probe",
          page in r.stdout and "05-visual-review.md" in r.stdout
          and "shot:" not in r.stdout, r.stdout)

    print("== order and plural: wireframes last, set order kept within a group ==")
    ordd = os.path.join(tmp, "ord")
    shutil.copytree(FIXTURE, ordd)
    shutil.copytree(os.path.join(ordd, "beta"), os.path.join(ordd, "gamma"))
    shutil.copytree(os.path.join(ordd, "alfa"), os.path.join(ordd, "delta"))
    with open(os.path.join(ordd, "set.tsv"), "w", encoding="utf-8") as fh:
        fh.write("id\tkind\tsource\nbeta\twireframe\tx\ngamma\twireframe\tx\n"
                 "alfa\tpipeline\tx\ndelta\ttree\tx\n")
    r = run(ordd, os.path.join(tmp, "ord-out"))
    oh = open(os.path.join(tmp, "ord-out", "reference-set.html"),
              encoding="utf-8").read() if r.returncode == 0 else ""
    at = [oh.find('id="s-%s"' % i) for i in ("alfa", "delta", "beta", "gamma")]
    check("drawable entries come first, wireframes after, manifest order inside "
          "each group", r.returncode == 0 and -1 not in at and at == sorted(at),
          str(at) + r.stderr)
    check("the count line for two says it in the plural",
          '">2 no son expresables todavía. Cada sección' in oh)

    print("== a manifest entry with no directory ==")
    bad = os.path.join(tmp, "bad")
    shutil.copytree(FIXTURE, bad)
    with open(os.path.join(bad, "set.tsv"), "a", encoding="utf-8") as fh:
        fh.write("gamma\ttree\tsynthetic/gamma.svg\n")
    bad_out = os.path.join(tmp, "bad-out")
    r = run(bad, bad_out)
    check("the run fails", r.returncode != 0, "exit %d" % r.returncode)
    check("the error names the entry", "gamma" in r.stderr, r.stderr)
    check("no page is built from a partial set",
          not os.path.exists(os.path.join(bad_out, "reference-set.html")))
finally:
    shutil.rmtree(tmp, ignore_errors=True)

if failures:
    print("NOT OK — %d failure(s)" % len(failures))
    sys.exit(1)
print("OK — reference set: every entry on the page, engine figure, reason,"
      " and a missing directory fails loudly")
