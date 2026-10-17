#!/usr/bin/env bash
# test-grader-fixtures.sh — every regex / file_exists grader of every native eval case behaves on
# its own fixture pair: grader-fixtures/<grader>.pass.* must satisfy it and <grader>.fail.* must not.
# Also: a tool_used grader that sets `max` must set `min` too (min defaults to 1, so a bare
# `max: 0` reads "expected 1..0" and fails every run). Promoted from the campaign gate (R6).
# Layer: shell + python, a static check over tracked fixtures; nothing runs a model.
#
# Checked: every case that ships a grader-fixtures/ directory, and every scn-* case (which must).
# The older cases (no pairs yet) are skipped.
#
# Fixtures may contain @@kit:<hash>@@ placeholders, expanded from <skill>/evals/native/.grader-kit/.
# AIDEX_GRADER_ROOT points the scan at another tree (the revert check uses a corrupted copy).
#
# Run with: bash tests/native-eval/test-grader-fixtures.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT="${AIDEX_GRADER_ROOT:-$(cd "$HERE/../.." && pwd -P)}"

python3 -I - "$ROOT" <<'PY'
import glob, os, re, sys
from fnmatch import fnmatchcase

root = sys.argv[1]

def unq(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] == "'":
        return v[1:-1].replace("''", "'")
    if len(v) >= 2 and v[0] == v[-1] == '"':
        return v[1:-1].encode().decode("unicode_escape")
    return v

def front(path):
    """Minimal front-matter reader: top-level keys and one nested level."""
    text = open(path).read()
    m = re.match(r"---\n(.*?)\n---", text, re.S)
    out, parent = {}, None
    for line in (m.group(1).splitlines() if m else []):
        if not line.strip():
            continue
        k, _, v = line.strip().partition(":")
        if line.startswith("  ") and parent:
            out[parent][k] = unq(v)
        elif v.strip() == "":
            parent = k; out[k] = {}
        else:
            parent = None; out[k] = unq(v)
    return out

total, bad = 0, []
for d in sorted(glob.glob(os.path.join(root, "skills/*/evals/native/*/"))):
    if not os.path.isdir(os.path.join(d, "grader-fixtures")) and not os.path.basename(d.rstrip("/")).startswith("scn-"):
        continue  # opt-in by shipping grader-fixtures/; scn-* cases must always ship it
    name = os.path.basename(os.path.dirname(os.path.dirname(os.path.dirname(d.rstrip("/"))))) + "--" + os.path.basename(d.rstrip("/"))
    for g in sorted(glob.glob(os.path.join(d, "graders/*.md"))):
        gname = os.path.basename(g)[:-3]
        fm = front(g)
        if fm.get("type") == "tool_used" and "max" in fm:
            total += 1
            if "min" not in fm:
                bad.append(f"{name}/{gname}: tool_used max without min")
            continue
        if fm.get("type") not in ("regex", "file_exists"):
            continue
        total += 1
        fx = os.path.join(d, "grader-fixtures", gname)
        p, f = glob.glob(fx + ".pass.*"), glob.glob(fx + ".fail.*")
        if not p or not f:
            bad.append(f"{name}/{gname}: missing fixture pair"); continue
        kit = os.path.join(os.path.dirname(d.rstrip("/")), ".grader-kit")
        expand = lambda t: re.sub(r"@@kit:([0-9a-f]+)@@", lambda m: open(os.path.join(kit, m.group(1))).read(), t)
        pt, ft = expand(open(p[0]).read()), expand(open(f[0]).read())
        if fm["type"] == "regex":
            flags = (re.M if "m" in fm.get("flags", "") else 0) | (re.I if "i" in fm.get("flags", "") else 0)
            rx = re.compile(fm["pattern"], flags)
            want = fm.get("match", "contains") == "contains"
            good = (bool(rx.search(pt)) == want) and (bool(rx.search(ft)) != want)
        else:
            # file_exists: fixtures hold one created path per line; the glob must match a line
            # of pass and no line of fail ('*' only, as the eval does).
            pat = fm["path"]
            hit = lambda t: any(fnmatchcase(l.strip(), pat) for l in t.splitlines() if l.strip())
            good = hit(pt) and not hit(ft)
        if not good:
            bad.append(f"{name}/{gname}: fixture pair disagrees")

if total == 0:
    print("FAIL: no regex / file_exists / tool_used-max grader found under skills/*/evals/native/*/ — the scan checked nothing")
    sys.exit(1)
if bad:
    print(f"FAIL: {len(bad)} of {total} graders:")
    for b in bad: print("  " + b)
    sys.exit(1)
FLOOR = 42  # graders checked when this was promoted; fewer means coverage shrank (cases or fixtures lost)
if total < FLOOR:
    print(f"FAIL: only {total} graders checked, floor is {FLOOR} — a case, a grader or a grader-fixtures/ dir disappeared")
    sys.exit(1)
print(f"PASS: {total} graders (floor {FLOOR}) agree with their fixture pairs")
PY
