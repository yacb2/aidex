#!/usr/bin/env python3
"""Body of contract-night-gate.sh; read that file's header for what the gate is for.

Seams for the gate's own test: AIDEX_GATE_SCRIPTS (the scripts dir the misuse
cases run against), AIDEX_GATE_FIXTURES (the dir holding misuse-replay/ and
refusal-fixes/) and AIDEX_GATE_REPO (the root test_cmd runs from).

Not-a-refusal rows: a refusal-split.tsv row whose check starts with
`not-a-refusal:` is CLASSIFIED (it counts toward `refusal-split: done`) but is
left out of the top-refusals counter AND out of its 60% denominator, because the
gate did not wrongly refuse that page. `deliberate` rows stay in both.
"""

import csv
import os
import shlex
import subprocess
import sys
import tempfile
from collections import Counter
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
SKILL = os.path.dirname(HERE)
REPO = os.environ.get("AIDEX_GATE_REPO") or os.path.dirname(os.path.dirname(SKILL))
ENV = "AIDEX_SCRIPT_CENSUS"
DEFAULT_CENSUS = os.path.expanduser(
    "~/Documents/projects/aidex_ws/.context/research/2026-10-07-aidex-review-state-of-art/census")
SCRIPTS = os.environ.get("AIDEX_GATE_SCRIPTS") or os.path.join(SKILL, "scripts")
FIXTURES = os.environ.get("AIDEX_GATE_FIXTURES") or os.path.join(HERE, "fixtures")
ARM_ROWS, ARM_BRIEFS, ARM_REPS = 18, 6, 3


def die(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(2)


def read_tsv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE))


def header(path):
    with open(path, newline="", encoding="utf-8") as f:
        return next(csv.reader(f, delimiter="\t", quoting=csv.QUOTE_NONE), [])


def norm_script(name):
    base = os.path.basename(name.strip())
    return os.path.splitext(base)[0].replace("-", "_")


def val(row, key):
    return (row.get(key) or "").strip()


def first_line(text):
    text = text.strip()
    return text.splitlines()[0] if text else ""


# ---- misuse -----------------------------------------------------------------

INTERP = {".sh": "bash", ".py": "python3", ".mjs": "node"}


def run_case(case, tmp, census_script):
    """Return (matched, rc, first output line)."""
    name = val(case, "script")
    expect = val(case, "expect")
    if os.path.isabs(name) or ".." in name:
        return False, "-", "refused script name: " + name
    if norm_script(name) != norm_script(census_script):
        return False, "-", "case script %s is not the census script %s" % (name, census_script)
    interp = INTERP.get(os.path.splitext(name)[1])
    if not interp:
        return False, "-", "unsupported script type: " + name
    path = os.path.join(SCRIPTS, name)
    if not os.path.isfile(path):
        return False, "-", "script not found: " + name
    if expect == "accept":
        want = None
    elif expect.startswith("usage:") and len(expect) > len("usage:"):
        # Several parts joined by " ;; " must ALL sit on the same usage line
        # (the form and the reason); an empty part makes the case invalid.
        want = expect[len("usage:"):].split(" ;; ")
        if not all(w.strip() for w in want):
            return False, "-", "invalid expect: " + expect
    else:
        return False, "-", "invalid expect: " + expect
    fixdir = os.path.join(FIXTURES, "misuse-replay")
    args = [a.replace("{FIX}", fixdir).replace("{TMP}", tmp)
            for a in shlex.split(case.get("args") or "")]
    stdin_name = val(case, "stdin")
    stdin = subprocess.DEVNULL
    if stdin_name:
        sp = os.path.join(fixdir, stdin_name)
        if not os.path.isfile(sp):
            return False, "-", "stdin file not found: " + stdin_name
        stdin = open(sp, "rb")
    try:
        p = subprocess.run([interp, path] + args, cwd=tmp, stdin=stdin, timeout=60,
                           capture_output=True, text=True, errors="replace")
    except subprocess.TimeoutExpired:
        return False, "timeout", ""
    finally:
        if stdin_name:
            stdin.close()
    out = p.stderr + p.stdout
    if want is None:
        ok = p.returncode == 0
    else:
        ok = p.returncode == 2 and any(
            l.lstrip().lower().startswith("usage:") and all(w in l for w in want)
            for l in out.splitlines())
    return ok, p.returncode, first_line(out)


def misuse(census, verbose_lines):
    """(matched, X or None). X must be > 0 and cover calls.tsv's tool-misuse rows."""
    ids = [val(r, "id") for r in read_tsv(os.path.join(census, "review.tsv"))
           if val(r, "class") == "tool-misuse"]
    calls = read_tsv(os.path.join(census, "calls.tsv"))
    script_of = {val(r, "id"): val(r, "script") for r in calls}
    in_calls = sum(1 for r in calls if val(r, "cls") == "tool-misuse")
    cases = {}
    cpath = os.path.join(FIXTURES, "misuse-replay", "cases.tsv")
    if os.path.isfile(cpath):
        for c in read_tsv(cpath):
            cases.setdefault(val(c, "id"), c)
    matched = 0
    for i in ids:
        if i not in cases:
            verbose_lines.append("misuse unmatched %s: no case" % i)
            continue
        if i not in script_of:
            verbose_lines.append("misuse unmatched %s: id not in calls.tsv" % i)
            continue
        with tempfile.TemporaryDirectory() as tmp:
            ok, rc, line = run_case(cases[i], tmp, script_of[i])
        if ok:
            matched += 1
        else:
            verbose_lines.append("misuse unmatched %s: rc=%s %s" % (i, rc, line))
    if not ids or len(ids) < in_calls:
        verbose_lines.append("misuse X unknown: %d tool-misuse in review.tsv, %d in calls.tsv"
                             % (len(ids), in_calls))
        return matched, None
    return matched, len(ids)


# ---- refusal split / top refusals ------------------------------------------

def refusal_state(census):
    """(total, {id: check}) or None for the split when the file is missing."""
    refusals = {val(r, "id") for r in read_tsv(os.path.join(census, "calls.tsv"))
                if val(r, "cls") == "gate-refusal"}
    path = os.path.join(census, "refusal-split.tsv")
    if not os.path.isfile(path):
        return len(refusals), None
    split = {}
    for r in read_tsv(path):
        i, check = val(r, "id"), val(r, "check")
        if i in refusals and check and check != "unclear":
            split.setdefault(i, check)
    return len(refusals), split


FIX_KINDS = ("autofix", "message", "canon")


def fix_passes(row):
    """A fix row counts when its kind is valid, its test_cmd names an existing
    test file under skills/artifact/tests/ or tests/, and the command exits 0."""
    cmd = val(row, "test_cmd")
    if val(row, "kind") not in FIX_KINDS or not cmd:
        return False
    try:
        toks = shlex.split(cmd)
    except ValueError:
        return False
    named = [t for t in toks
             if (t.startswith("skills/artifact/tests/") or t.startswith("tests/"))
             and ".." not in t.split("/") and os.path.isfile(os.path.join(REPO, t))]
    if not named:
        return False
    try:
        return subprocess.run(["bash", "-c", cmd], cwd=REPO, timeout=600,
                              capture_output=True).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def top_refusals(total, split, verbose_lines):
    if split is None or total == 0:
        return "top-refusals: unknown", False
    NAR = "not-a-refusal:"
    denom = total - sum(1 for c in split.values() if c.startswith(NAR))
    if denom <= 0:
        return "top-refusals: unknown", False
    counts = sorted(Counter(c for c in split.values() if not c.startswith(NAR)).items(),
                    key=lambda kv: (-kv[1], kv[0]))
    prefix, acc = [], 0
    for check, n in counts:
        prefix.append(check)
        acc += n
        if acc * 100 >= 60 * denom:
            break
    else:
        return "top-refusals: 0/unknown", False
    fixes = {}
    fpath = os.path.join(FIXTURES, "refusal-fixes", "fixes.tsv")
    if os.path.isfile(fpath):
        for r in read_tsv(fpath):
            fixes.setdefault(val(r, "check"), []).append(r)
    have = 0
    for check in prefix:
        rows = fixes.get(check, [])
        if rows and all(fix_passes(r) for r in rows):
            have += 1
        else:
            verbose_lines.append("top check without a passing fix: " + check)
    return "top-refusals: %d/%d" % (have, len(prefix)), have == len(prefix)


# ---- bench -------------------------------------------------------------------

def bench(census, verbose_lines):
    rows = []
    path = os.path.join(census, "bench", "results.tsv")
    if os.path.isfile(path):
        rows = read_tsv(path)
    arms, parsed_by = {}, {}
    for arm in ("main", "branch"):
        mine = [r for r in rows if val(r, "arm") == arm]
        try:
            parsed = [(val(r, "brief"), int(val(r, "rep")), int(val(r, "pages")),
                       int(val(r, "refusals")), val(r, "agent_id")) for r in mine]
        except ValueError:
            parsed = []
        keys = {(b, rep) for b, rep, _, _, _ in parsed}
        briefs = Counter(b for b, _ in keys)
        good = (len(parsed) == ARM_ROWS and len(keys) == ARM_ROWS and len(briefs) == ARM_BRIEFS
                and all(n == ARM_REPS for n in briefs.values())
                and {rep for _, rep in keys} == {1, 2, 3}
                and all(p > 0 and r >= 0 for _, _, p, r, _ in parsed))
        parsed_by[arm] = parsed if good else None
        arms[arm] = Fraction(sum(x[3] for x in parsed), sum(x[2] for x in parsed)) if good else None
        verbose_lines.append("bench %s: %d rows, %s" % (arm, len(mine),
                             "measured" if good else "not measured"))
    if arms["main"] is not None and arms["branch"] is not None:
        pm, pb = parsed_by["main"], parsed_by["branch"]
        pages = lambda ps: {b: sum(p for bb, _, p, _, _ in ps if bb == b) for b in {x[0] for x in ps}}
        ids = [x[4] for x in pm + pb]
        why = None
        if {x[0] for x in pm} != {x[0] for x in pb}:
            why = "arms use different briefs"
        elif pages(pm) != pages(pb):
            why = "pages per brief differ between arms"
        elif len(set(ids)) != 2 * ARM_ROWS or not all(ids):
            why = "agent_ids are not 36 distinct non-empty values"
        if why:
            verbose_lines.append("bench arms not comparable: " + why)
            arms = {"main": None, "branch": None}
    fmt = lambda v: "unknown" if v is None else "%.2f" % float(v)
    b, a = arms["main"], arms["branch"]
    line = "bench: %s -> %s" % (fmt(b), fmt(a))
    if b is not None and b == 0:
        return line + " (no baseline)", False
    return line, b is not None and a is not None and a <= Fraction(7, 10) * b


# ---- census rerun -------------------------------------------------------------

def rerun(census):
    with tempfile.TemporaryDirectory() as out:
        steps = (("census.py", ["python3", "census.py", "--out", out]),
                 ("report.py", ["python3", "report.py", "--in", os.path.join(out, "calls.tsv")]))
        for name, cmd in steps:
            try:
                rc = subprocess.run(cmd, cwd=census, timeout=1800,
                                    capture_output=True).returncode
            except subprocess.TimeoutExpired:
                rc = "timeout"
            if rc != 0:
                return "census: rerun FAILED (%s rc %s)" % (name, rc), False
    return "census: rerun ok", True


def main(argv):
    verbose = "--verbose" in argv
    census = os.environ.get(ENV) or DEFAULT_CENSUS
    if not os.path.isdir(census):
        die("%s: %s is not a directory" % (ENV, census))
    for need in ("calls.tsv", "review.tsv"):
        if not os.path.isfile(os.path.join(census, need)):
            die("%s: %s lacks %s" % (ENV, census, need))

    for fname, cols in (("calls.tsv", ("id", "cls", "script")), ("review.tsv", ("id", "class"))):
        missing = [c for c in cols if c not in header(os.path.join(census, fname))]
        if missing:
            die("%s: %s lacks column %s" % (ENV, os.path.join(census, fname), ",".join(missing)))

    extra = []
    m, x = misuse(census, extra)
    total, split = refusal_state(census)
    if split is None or total == 0:
        split_line, split_ok = "refusal-split: unknown", False
    elif len(split) == total:
        split_line, split_ok = "refusal-split: done", True
    else:
        split_line, split_ok = "refusal-split: %d/%d" % (len(split), total), False
    top_line, top_ok = top_refusals(total, split, extra)
    bench_line, bench_ok = bench(census, extra)
    if "--no-rerun" in argv:
        census_line, census_ok = "census: skipped", False
    else:
        census_line, census_ok = rerun(census)

    print("misuse: %d/%s" % (m, "unknown" if x is None else x))
    print(split_line)
    print(top_line)
    print(bench_line)
    print(census_line)
    if verbose:
        for l in extra:
            print(l)
    sys.exit(0 if (x is not None and m == x and split_ok and top_ok and bench_ok and census_ok) else 1)


if __name__ == "__main__":
    main(sys.argv[1:])
