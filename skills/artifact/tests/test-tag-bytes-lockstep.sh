#!/usr/bin/env bash
# test-tag-bytes-lockstep.sh — BL-759: check_artifact.py's _TAG_BYTES and the copy in
# usage-retro/facets/read_artifacts.py (a standalone tool) must stay the same pattern, and
# strip_item_markup / blank_item_comments must agree on which comments are comments.
#
# Run with: bash skills/artifact/tests/test-tag-bytes-lockstep.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILLS="$HERE/../.."
python3 -I - "$SKILLS" <<'PY'
import importlib.util, re, sys
skills = sys.argv[1]
sys.path.insert(0, skills + "/artifact/scripts/dash")
import check_artifact as c
src = open(skills + "/audit/scripts/usage-retro/facets/read_artifacts.py").read()
m = re.search(r"^_TAG_BYTES = (\(.*?\))\n", src, re.M | re.S)
fails = []
if not m:
    fails.append("read_artifacts.py has no _TAG_BYTES")
elif eval(m.group(1)).replace("\\'", "'") != c._TAG_BYTES.replace("\\x27", "'"):  # \x27 and a quote are one char
    fails.append("_TAG_BYTES differs between check_artifact.py and read_artifacts.py")
page = ('<p>a</p><!-- <div data-id="gone"> --><div data-id="x1"></div>'
        '<!--> <div data-id="x2" title="a > b"></div><!-- c --!><div data-id="x3"></div>')
ids = lambda t: [g[1] for g in (mm.groups() for mm in c.ITEM_OPEN.finditer(t))]
want = ["x1", "x2", "x3"]
for name, fn in (("strip_item_markup", c.strip_item_markup), ("blank_item_comments", c.blank_item_comments)):
    if ids(fn(page)) != want:
        fails.append("%s reads %s, want %s" % (name, ids(fn(page)), want))
if len(c.blank_item_comments(page)) != len(page):
    fails.append("blank_item_comments changed the length")
for f in fails:
    print("FAIL: " + f)
print("PASS: tag-bytes lockstep" if not fails else "FAILED: %d" % len(fails))
sys.exit(1 if fails else 0)
PY
