#!/usr/bin/env python3
"""Guard the frozen corpus sample (`$AIDEX_SPEC_CORPUS/corpus-sample.json`).

The sample is FROZEN: it was drawn once, with a recorded seed, and committed.
This test does not re-draw it — a test that re-sampled would silently move the
baseline every phase measures against, which is the one thing the fixture
exists to prevent. It only checks that the frozen document is still the
document the later phases assume: 30 unique pages that still exist on disk,
with the seed on record.

The sample is built from the owner's private pages, so it does not ship with
this repo: it lives in the directory `AIDEX_SPEC_CORPUS` names. Unset, this
prints one `SKIP` line saying so and exits 0 — a skip is printed, never silent.

Stdlib only, no runner: `python3 test_corpus_sample.py`, prints OK, exits 0.
`test-goal-gate.sh` runs it, which is how the suite sees it.
"""
import json
import os
import sys

CORPUS = os.environ.get("AIDEX_SPEC_CORPUS", "")
FIXTURE = os.path.join(CORPUS, "corpus-sample.json")
EXPECTED = 30


def fail(msg):
    sys.stderr.write("test_corpus_sample: " + msg + "\n")
    raise SystemExit(1)


def main():
    if not CORPUS:
        print("SKIP test_corpus_sample: AIDEX_SPEC_CORPUS not set")
        return
    if not os.path.isfile(FIXTURE):
        fail("missing fixture %s" % FIXTURE)
    with open(FIXTURE) as fh:
        doc = json.load(fh)

    if "seed" not in doc:
        fail("no 'seed' key — the draw is not reproducible without it")
    if not isinstance(doc["seed"], int):
        fail("'seed' is %r, expected an int" % (doc["seed"],))

    root = doc.get("root")
    if not root:
        fail("no 'root' key — page paths are relative to it")
    if not os.path.isdir(root):
        # The sample is drawn from private sibling workspaces that do not exist
        # on a clone of this public repo. Everything above is checkable
        # anywhere; the on-disk existence assertions below are not.
        print("SKIP (corpus root %s not present on this machine)" % root)
        return

    pages = doc.get("pages")
    if not isinstance(pages, list):
        fail("'pages' is not a list")
    if len(pages) != EXPECTED:
        fail("%d entries, expected exactly %d" % (len(pages), EXPECTED))

    paths = [p.get("path") for p in pages]
    if any(not p for p in paths):
        fail("an entry has no 'path'")
    if len(set(paths)) != len(paths):
        dupes = sorted({p for p in paths if paths.count(p) > 1})
        fail("duplicate path(s): %s" % ", ".join(dupes))

    missing = [p for p in paths if not os.path.isfile(os.path.join(root, p))]
    if missing:
        fail("%d sampled page(s) no longer exist under %s: %s"
             % (len(missing), root, ", ".join(sorted(missing)[:3])))

    for entry in pages:
        if not entry.get("project"):
            fail("entry %s has no 'project'" % entry.get("path"))
        if not isinstance(entry.get("bytes"), int):
            fail("entry %s has no integer 'bytes'" % entry.get("path"))

    print("OK")


if __name__ == "__main__":
    main()
