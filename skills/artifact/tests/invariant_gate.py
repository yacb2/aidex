#!/usr/bin/env python3
"""The LOOP-008 invariant gate: seven lines, fixed order, exit 0 only when all are green.

    catalog: N       rows of tests/invariants/catalog.md (N >= 12)
    corpus: X/Y      goal-gate corpus specs built with the current builder, run through
                     `render-probe.sh --invariants`; X = pages with zero violations,
                     a spec the builder refuses counts as a failing page
    generated: X/Y   WIRED: tests/generated_gate.py (300 seeded specs from a fixed base seed; Y >= 300)
    mutations: X/Y   WIRED: tests/mutations_gate.py's own line; its `--expected` count is the
                     minimum Y, so a shrunk case set reads RED; no line reads `0/unknown`
    rounds / galleries / hunts-clean
                     STUBS: later units replace them; until then they print 0/0, 0/0
                     and 0 and the gate stays RED (counts below the loop-spec minimums)

Every line has an explicit minimum, so a 0/0 never reads green: catalog >= 12, corpus total >= 1,
generated >= 300, rounds >= 50, mutations >= 1, galleries >= 1, hunts-clean >= 2.

Test seams (the gate's own test drives them, nothing else should):
  AIDEX_RENDER_PROBE      replaces scripts/render-probe.sh (a fake probe, no browser)
  AIDEX_GATE_LINE_SCRIPTS replaces the directory the WIRED line scripts are read from
  AIDEX_INVARIANT_STUBS   comma list `key=value` replacing stub lines, e.g.
                          `generated=300/300,rounds=50/50,mutations=1/1,galleries=1/1,hunts-clean=2`.
                          An overridden line prints with a ` (override)` suffix and the gate never
                          exits 0 while one is active: the seam cannot fake a green run.

The corpus is private (see goal-gate.sh): AIDEX_SPEC_CORPUS, else the workspace default
`<workspace>/.context/research/2026-09-24-artifact-spec-corpus` when it exists, else
`corpus: 0/unknown`. --verbose lists each failing page and the invariants fired.
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import defect_gate  # noqa: E402  (corpus_specs, build_dir, build_spec: one corpus reader)

SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(SCRIPTS, "render-probe.sh")
CATALOG = os.path.join(HERE, "invariants", "catalog.md")
MIN = {"catalog": 12, "corpus": 1, "generated": 300, "rounds": 50, "mutations": 1,
       "galleries": 1, "hunts-clean": 2}
STUBS = {"generated": "0/0", "rounds": "0/0", "mutations": "0/0", "galleries": "0/0",
         "hunts-clean": "0"}
# Lines measured by their own script (one stdout line `<key>: X/Y`); a pinned script also answers
# `--expected` with its Y, which becomes that line's minimum so the case set cannot shrink unseen.
WIRED = {"mutations": ("mutations_gate.py", True), "generated": ("generated_gate.py", False)}
LINE_SCRIPTS = os.environ.get("AIDEX_GATE_LINE_SCRIPTS") or HERE


def wired_line(key):
    """`X/Y` from the line's own script, or `0/unknown` when it gives no such line."""
    script, pinned = WIRED[key]
    path = os.path.join(LINE_SCRIPTS, script)
    r = subprocess.run([sys.executable, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    m = re.fullmatch(r"%s: (\d+/\d+)\n?" % re.escape(key), r.stdout)
    if not m or r.returncode not in (0, 1):
        print("invariant-gate: %s gave no `%s: X/Y` line (rc=%d): %s"
              % (script, key, r.returncode, (r.stderr.strip() or r.stdout.strip())[-300:]), file=sys.stderr)
        return "0/unknown"
    if pinned:
        e = subprocess.run([sys.executable, path, "--expected"], stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True)
        if e.returncode != 0 or not e.stdout.strip().isdigit():
            print("invariant-gate: %s --expected gave no count" % script, file=sys.stderr)
            return "0/unknown"
        MIN[key] = max(MIN[key], int(e.stdout.strip()))
    return m.group(1)


def catalog_rows():
    with open(CATALOG, encoding="utf-8") as f:
        return sum(1 for ln in f if re.match(r"^\| [A-Z]+-\d+ \|", ln))


def default_corpus():
    """The workspace's private corpus, found by climbing from this file (the loop worktree
    sits under <workspace>/_tmp/wt/, the main checkout under <workspace>/aidex/)."""
    d = HERE
    while True:
        c = os.path.join(d, ".context", "research", "2026-09-24-artifact-spec-corpus")
        if os.path.isfile(os.path.join(c, "corpus-sample.json")):
            return c
        if os.path.dirname(d) == d:
            return ""
        d = os.path.dirname(d)


def corpus_line(verbose):
    """(line, green). Builds every spec, probes the built pages in one browser run."""
    if not os.environ.get("AIDEX_SPEC_CORPUS"):
        os.environ["AIDEX_SPEC_CORPUS"] = default_corpus()
    specs = defect_gate.corpus_specs()
    if specs is None:
        print("invariant-gate: AIDEX_SPEC_CORPUS unset or without corpus-sample.json"
              " — the corpus was not measured", file=sys.stderr)
        return "corpus: 0/unknown", False
    pages, trees, failed = [], [], {}
    for spec, project in specs:
        tree, reports = defect_gate.build_dir(project)
        trees.append(tree)
        page, why = defect_gate.build_spec(spec, reports)
        if page:
            pages.append(page)
        else:
            failed[os.path.basename(spec)] = why
    fired = {}
    try:
        if pages:
            r = subprocess.run(["bash", PROBE, "--invariants"] + pages, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
            summary = re.search(r"^INVARIANTS pages=(\d+) violations=(\d+)$", r.stdout, re.M)
            if r.returncode not in (0, 1) or not summary or int(summary.group(1)) != len(pages):
                print("invariant-gate: probe gave no verdict on %d page(s) (rc=%d): %s"
                      % (len(pages), r.returncode, r.stderr.strip() or r.stdout.strip()[-200:]),
                      file=sys.stderr)
                return "corpus: 0/unknown", False
            for ln in r.stdout.splitlines():
                m = re.match(r"^INV (\S+) (\S+) (.*)$", ln)
                if m:
                    fired.setdefault(m.group(2), []).append((m.group(1), m.group(3)))
    finally:
        for t in trees:
            shutil.rmtree(t, ignore_errors=True)
    total = len(specs)
    names = {os.path.basename(pg) for pg in pages}          # distinct pages, not distinct lines
    clean = len(names - set(fired))
    if verbose:
        mig = sorted(os.path.basename(sp) for sp, _ in specs if defect_gate.is_migrated(sp))
        if mig:
            print("  migrated specs built (corpus MIGRATIONS.md): %s" % ", ".join(mig),
                  file=sys.stderr)
        for name, why in sorted(failed.items()):
            print("  %s: %s" % (name, why), file=sys.stderr)
        per = {}
        for name, vs in sorted(fired.items()):
            for i in {v[0] for v in vs}:
                per[i] = per.get(i, 0) + 1
            print("  %s: %s" % (name, ", ".join(sorted({v[0] for v in vs}))), file=sys.stderr)
        for i, n in sorted(per.items()):
            print("  %s fires on %d page(s)" % (i, n), file=sys.stderr)
    nmig = sum(1 for sp, _ in specs if defect_gate.is_migrated(sp))
    return ("corpus: %d/%d%s" % (clean, total, " (%d migrated)" % nmig if nmig else ""),
            clean == total and total >= MIN["corpus"])


def main(argv):
    verbose = "--verbose" in argv
    n = catalog_rows()
    cline, cgreen = corpus_line(verbose)
    # STUBS, replaced by later units of LOOP-008 (generator, round runner, mutations,
    # ui-contract galleries, hunts). Each prints a zero so the gate cannot read as done.
    stubs, overridden = dict(STUBS), set()
    for kv in filter(None, os.environ.get("AIDEX_INVARIANT_STUBS", "").split(",")):
        k, _, v = kv.partition("=")
        if k in stubs:
            stubs[k] = v
            overridden.add(k)
    for k in WIRED:
        if k not in overridden:
            stubs[k] = wired_line(k)
    lines = ["catalog: %d" % n, cline] + ["%s: %s%s" % (k, stubs[k], " (override)" if k in overridden else "")
                                          for k in STUBS]
    print("\n".join(lines))
    green = n >= MIN["catalog"] and cgreen
    for k, v in stubs.items():
        m = re.match(r"^(\d+)/(\d+)$", v)
        if m:
            x, y = int(m.group(1)), int(m.group(2))
            green = green and x == y and y >= MIN[k]
        else:
            green = green and v.isdigit() and int(v) >= MIN[k]
    return 0 if green and not overridden else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
