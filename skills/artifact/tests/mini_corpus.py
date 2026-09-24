#!/usr/bin/env python3
"""Lay out a SYNTHETIC spec corpus in <dir>, in the shape `AIDEX_SPEC_CORPUS` names.

    python3 mini_corpus.py <dir>

The real corpus is built from the owner's private pages and lives outside this
repo, so the gate's own test needs a corpus it can always build. This one is
three invented pages (`fixtures/mini-corpus/`): each "original" page is BUILT
from its spec, so `corpus_diff` matches it by construction and every line the
gate prints is measured, not stubbed. Written here, at test time, are only the
files that depend on where <dir> is: the pages, `corpus-sample.json` (whose
`root` is absolute) and `baseline.json` (the pages' own sizes).
"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "fixtures", "mini-corpus")
BUILD = os.path.join(os.path.dirname(HERE), "scripts", "spec_build.py")


def main(argv):
    if len(argv) != 1:
        raise SystemExit("usage: mini_corpus.py <dir>")
    out = os.path.abspath(argv[0])
    shutil.copytree(SOURCE, out)
    root = os.path.join(out, "pages")
    pages, baseline = [], []
    specs = os.path.join(out, "corpus-specs")
    for name in sorted(os.listdir(specs)):
        if not name.endswith(".spec.md"):
            continue
        project, page = name[:-len(".spec.md")].split("__", 1)
        path = "%s/reports/%s.html" % (project, page)
        dest = os.path.join(root, path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        subprocess.run([sys.executable, BUILD, os.path.join(specs, name),
                        "-o", dest], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        size = os.path.getsize(dest)
        pages.append({"path": path, "project": project, "bytes": size})
        baseline.append({"path": path, "wrote_bytes": size,
                         "check_today_pass": True})
    with open(os.path.join(out, "corpus-sample.json"), "w") as fh:
        json.dump({"seed": 1, "root": root, "pages": pages}, fh, indent=2)
    with open(os.path.join(out, "baseline.json"), "w") as fh:
        json.dump(baseline, fh, indent=2)
    print(out)


if __name__ == "__main__":
    main(sys.argv[1:])
