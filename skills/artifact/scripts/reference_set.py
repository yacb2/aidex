#!/usr/bin/env python3
"""reference_set.py — a diagram reference set becomes one page spec, built.

    python3 reference_set.py <set-dir> <out-dir>

`<set-dir>/set.tsv` (header `id<TAB>kind<TAB>source`) lists the entries; each one
is a directory `<set-dir>/<id>/` holding `baseline.svg` and either
`engine.diagram` or `not-expressible.txt` (one line: the reason). The first line
of `engine.diagram` is `shape=<shape>` (the fence attribute), the rest is the
`diagram` body as written today.

Writes `<out-dir>/reference-set.spec.md`, the baselines under `<out-dir>/figures/`
and builds `<out-dir>/reference-set.html` with the kit's own build (`spec_build.py
--check`). One section per entry, the id and kind in its heading, the hand SVG
beside the engine's rendering or, when the engine has no shape for it, the reason.
An entry whose directory or files are missing is an error, never a skipped row.
"""
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def fail(msg):
    sys.stderr.write("reference-set: %s\n" % msg)
    sys.exit(1)


def read_manifest(set_dir):
    path = os.path.join(set_dir, "set.tsv")
    if not os.path.isfile(path):
        fail("no manifest at %s" % path)
    rows = []
    with open(path, encoding="utf-8") as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.strip()]
    for ln in lines[1:]:
        cols = ln.split("\t")
        if len(cols) < 3 or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_-]*", cols[0]):
            fail("bad manifest row (want id<TAB>kind<TAB>source): %r" % ln)
        rows.append(cols[:3])
    if not rows:
        fail("the manifest lists no entries")
    return rows


def read_file(path):
    if not os.path.isfile(path):
        fail("missing %s" % path)
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def section(set_dir, out_dir, ident, kind):
    entry = os.path.join(set_dir, ident)
    if not os.path.isdir(entry):
        fail("manifest entry %s has no directory %s" % (ident, entry))
    baseline = os.path.join(entry, "baseline.svg")
    if not os.path.isfile(baseline):
        fail("missing %s" % baseline)
    shutil.copy(baseline, os.path.join(out_dir, "figures", ident + ".svg"))
    out = ['::: section {#s-%s heading="%s (%s)"}' % (ident, ident, kind), "",
           '::: figure {#%s-base src="figures/%s.svg" title="A mano (línea base)"}'
           % (ident, ident), ":::", ""]
    engine = os.path.join(entry, "engine.diagram")
    if os.path.isfile(engine):
        head, _, body = read_file(engine).partition("\n")
        m = re.fullmatch(r"shape=([a-z-]+)\s*", head)
        if not m:
            fail("%s: first line must be shape=<shape>" % engine)
        out += ['::: diagram {#%s-eng shape=%s title="Motor, hoy"}'
                % (ident, m.group(1)), body.strip("\n"), ":::"]
    else:
        reason = read_file(os.path.join(entry, "not-expressible.txt")).strip()
        out += ["No expresable todavía: %s" % reason]
    return out + ["", ":::", ""]


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    set_dir, out_dir = argv
    rows = read_manifest(set_dir)
    os.makedirs(os.path.join(out_dir, "figures"), exist_ok=True)
    drawn = sum(os.path.isfile(os.path.join(set_dir, r[0], "engine.diagram")) for r in rows)
    spec = ['::: masthead {title="Conjunto de referencia de figuras" eyebrow="Motor de diagramas"}',
            "El motor dibuja %d de %d figuras; %d no son expresables todavía. Cada "
            "sección pone la figura hecha a mano junto a lo que el motor dibuja hoy."
            % (drawn, len(rows), len(rows) - drawn),
            ":::", ""]
    for ident, kind, _source in rows:
        spec += section(set_dir, out_dir, ident, kind)
    spec_path = os.path.join(out_dir, "reference-set.spec.md")
    with open(spec_path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(spec))
    return subprocess.call([sys.executable, os.path.join(HERE, "spec_build.py"),
                            spec_path, "-o",
                            os.path.join(out_dir, "reference-set.html"), "--check"])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
