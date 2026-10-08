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
sys.path.insert(0, HERE)
from spec_parser import quote_value  # noqa: E402  the one writer of attr syntax


def fail(msg):
    sys.stderr.write("reference-set: %s\n" % msg)
    sys.exit(1)


def read_manifest(set_dir):
    path = os.path.join(set_dir, "set.tsv")
    if not os.path.isfile(path):
        fail("no manifest at %s" % path)
    rows = []
    with open(path, encoding="utf-8-sig") as fh:
        lines = [ln.rstrip("\n") for ln in fh if ln.strip()]
    # The header is skipped only when it is one; a headerless manifest keeps row one.
    if lines and lines[0].split("\t")[0] == "id":
        lines = lines[1:]
    for ln in lines:
        cols = ln.split("\t")
        # spec_parser.NAME: an id starts with a letter.
        if len(cols) < 3 or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", cols[0]):
            fail("bad manifest row (want id<TAB>kind<TAB>source; the id starts "
                 "with a letter): %r" % ln)
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
    # The heading is read twice: quote_value covers the attr layer, the doubled
    # backslash covers md_body's double-backslash escape, so the page shows the kind as typed.
    out = ['::: section {#s-%s heading=%s}'
           % (ident, quote_value("%s (%s)" % (ident, kind.replace("\\", "\\\\")))), "",
           '::: figure {#%s-base src="figures/%s.svg" title="A mano (línea base)"}'
           % (ident, ident), ":::", ""]
    engine = os.path.join(entry, "engine.diagram")
    if os.path.isfile(engine):
        head, _, body = read_file(engine).partition("\n")
        m = re.fullmatch(r"shape=([a-z-]+)\s*", head)
        if not m:
            fail("%s: first line must be shape=<shape>" % engine)
        # A colon-only line closes the diagram block; a code-fence line can
        # swallow its closer. Neither belongs in an engine body.
        if re.search(r"^(:::+[ \t]*|[ \t]*(```|~~~).*)$", body, re.M):
            fail("%s: a body line of only colons or a code fence would break the "
                 "diagram block" % engine)
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
    # What the engine can draw first, the wireframes (a different route) last;
    # the manifest's order holds inside each group (sorted() is stable).
    rows = sorted(read_manifest(set_dir), key=lambda r: r[1] == "wireframe")
    os.makedirs(os.path.join(out_dir, "figures"), exist_ok=True)
    drawn = sum(os.path.isfile(os.path.join(set_dir, r[0], "engine.diagram")) for r in rows)
    # The H1 is the finding, counted from the manifest; the line under it says
    # what the rest are and how a section reads.
    spec = ['::: masthead {title="El motor dibuja %d de %d figuras de referencia" '
            'eyebrow="Motor de diagramas"}' % (drawn, len(rows)),
            "%s todavía. Cada sección pone la figura hecha a mano junto a lo "
            "que el motor dibuja hoy."
            % ("1 no es expresable" if len(rows) - drawn == 1
               else "%d no son expresables" % (len(rows) - drawn)),
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
