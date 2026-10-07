#!/usr/bin/env python3
"""The LOOP-008 hunts gate: `hunts-clean: N`, exit 0 iff N >= 2.

    python3 hunts_gate.py [--state-dir D]            perform ONE new hunt round, append it to D/rounds.tsv, print N
    python3 hunts_gate.py [--state-dir D] --report   print N from the round log; runs nothing (the invariant gate calls this)

State (ledger.tsv, rounds.tsv) records the owner's own pages, so it lives in the PRIVATE workspace repo, never
in this public tree: default D = <workspace>/.context/research/2026-09-24-artifact-spec-corpus/hunts/.

A round (number R = rows already in the log, so deleting rows of the log reuses seeds; round 0 is the baseline) runs, with seeds
derived from R and recorded in the log:
  generated   generated_gate.py --seed G --count 100 --verbose
  rounds      rounds_gate.py    --seed S --count 20  --verbose
  real pages  render-probe --invariants over the REAL built pages: every *.html (recursive) under
              /Users/yoelacevedo/Documents/projects/*/.context/reports/ and under
              asset_lab_ws/.context/artifacts/, minus galleries (a `galler` path component; galleries_gate
              owns them), backup copies (a `.aidex-artifact-prev` component: the live page is already
              in the set), `_src/` fragments and `*.body.html`, and duplicate checkouts (a path component
              containing `-wt-`). Round 0: all of them. Later rounds: a sample of 35 chosen by the round's
              seed plus every page modified since the previous round (the log's mtime). Pages are
              input only, never rewritten, and are keyed by full path (names collide).

CLASS KEY of a failure (deterministic: no seed, no file name):
  generated   gen:<generated_gate class key>          e.g. gen:INV:CNT-2, gen:BUILD:valid-refused
  rounds      rounds:<rounds_gate check>              e.g. rounds:invariant:NAV-4, rounds:id-lost
  real page   real:<invariant id>:<page kind>         kind = consultation (has a .consult-item) | presentation
ledger.tsv lists the keys: `key<TAB>first round<TAB>note`. A key is KNOWN only when its note is non-empty
(a person explained it). A round is CLEAN only when every key it shows is known. An unknown key is appended
with an EMPTY note and keeps every later round dirty until a person fills the note in.
Evidence per real key: the kit stamp (`<meta name="artifact-kit" content="N">`, 0 when absent) of every page it
fires on, against the current kit (skills/artifact/assets/artifact-kit/VERSION). In round 0 (the full census) a NEW
real key whose pages carry 0 current kit gets the note `old-kit only (kit A..B, 0 current)`, written by this script
and nothing else; a key with >= 1 current-kit page keeps an EMPTY note (a live class: a person decides).
N = consecutive clean rounds at the END of the log; round 0 (the baseline) never counts.

A round never passes vacuously. A sub-run that gives no verdict (crash, timeout, wrong or missing
`<key>: X/Y` line, Y not the requested count, failures without a parsed class) yields the key
`harness:<sub>:no-verdict`; a generated run that built 0 pages or a rounds run that passed 0
sequences yields `harness:<sub>:all-refused`. `harness:*` keys always make the round dirty and are
never written to the ledger (a broken harness is not a defect class to be tolerated).

Test seams (the gate's own test uses them): AIDEX_HUNT_GENERATED / AIDEX_HUNT_ROUNDS (replace the two
gate scripts), AIDEX_RENDER_PROBE, AIDEX_HUNT_PAGES (colon-separated directories replacing the defaults),
AIDEX_HUNT_SAMPLE (sample size), AIDEX_HUNT_KIT_VERSION (the current kit), AIDEX_HUNT_TIMEOUT (seconds per sub-run).
"""
import argparse
import glob
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
DEFAULT_STATE = "/Users/yoelacevedo/Documents/projects/aidex_ws/.context/research/2026-09-24-artifact-spec-corpus/hunts"
PROJECTS = "/Users/yoelacevedo/Documents/projects"
DIR = DEFAULT_STATE
LEDGER = LOG = ""
GENERATED = os.environ.get("AIDEX_HUNT_GENERATED") or os.path.join(HERE, "generated_gate.py")
ROUNDS = os.environ.get("AIDEX_HUNT_ROUNDS") or os.path.join(HERE, "rounds_gate.py")
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(SCRIPTS, "render-probe.sh")
TIMEOUT = float(os.environ.get("AIDEX_HUNT_TIMEOUT") or 1800)
GEN_COUNT, ROUNDS_COUNT = 100, 20
PAGE_SAMPLE = int(os.environ.get("AIDEX_HUNT_SAMPLE") or 35)
NEEDED = 2


def seeds(r):
    return 31000000 + r * 1000, 32000000 + r * 100


def all_pages():
    """Every hunt page, full paths, sorted; galleries excluded."""
    if os.environ.get("AIDEX_HUNT_PAGES"):
        roots = os.environ["AIDEX_HUNT_PAGES"].split(":")
    else:
        roots = glob.glob(os.path.join(PROJECTS, "*", ".context", "reports")) \
            + [os.path.join(PROJECTS, "asset_lab_ws", ".context", "artifacts")]
    found = set()
    for root in roots:
        for dp, _, files in os.walk(root):
            found.update(os.path.join(dp, f) for f in files if f.endswith(".html"))
    def skip(p):
        parts = p.split(os.sep)
        return any("galler" in c.lower() or c in (".aidex-artifact-prev", "_src") or "-wt-" in c for c in parts) \
            or p.endswith(".body.html")
    return sorted(p for p in found if not skip(p))


def current_kit():
    v = os.environ.get("AIDEX_HUNT_KIT_VERSION")
    if v is None:
        with open(os.path.join(os.path.dirname(HERE), "assets", "artifact-kit", "VERSION"), encoding="utf-8") as f:
            v = f.read()
    return int(v.strip())


def kit_of(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            m = re.search(r'<meta name="artifact-kit" content="(\d+)"', f.read())
    except OSError:
        m = None
    return int(m.group(1)) if m else 0


def read_rows(path):
    if not os.path.isfile(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [ln.rstrip("\n").split("\t") for ln in f if ln.strip() and not ln.startswith("#")]


def clean_streak():
    n = 0
    for row in reversed(read_rows(LOG)):
        if len(row) > 2 and row[2] == "clean" and row[0] != "0":
            n += 1
        else:
            break
    return n


def run(cmd):
    """(rc, stdout, stderr) or None on timeout / failure to start."""
    try:
        r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=TIMEOUT)
    except (subprocess.TimeoutExpired, OSError):
        return None
    return r.returncode, r.stdout, r.stderr


def gate_sub(sub, script, seed, count):
    """Keys of one gate script run (generated or rounds)."""
    r = run([sys.executable, script, "--seed", str(seed), "--count", str(count), "--verbose"])
    bad = {"harness:%s:no-verdict" % sub}
    if r is None or r[0] not in (0, 1):
        return bad
    _, out, err = r        # exit code ignored past 0/1: a small --count exits 1 by the gates' own minimum
    m = re.fullmatch(r"%s: (\d+)/(\d+)\n?" % sub, out)
    if not m or int(m.group(2)) != count:
        return bad
    x = int(m.group(1))
    if sub == "generated":
        b = re.search(r"builds: built (\d+)", err)
        if not b:
            return bad
        if int(b.group(1)) == 0:
            return {"harness:generated:all-refused"}
        keys = {"gen:" + k for k in re.findall(r"^\s+\d+\s+(\S+)\s", err.split("CLASSES", 1)[-1], re.M)} \
            if "CLASSES" in err else set()
    else:
        if x == 0:
            return {"harness:rounds:all-refused"}
        keys = {"rounds:" + k for k in re.findall(r"^class (\S+): \d+ sequence", err, re.M)}
    if x < count and not keys:
        return bad                                      # failures that no class explains
    return keys


def real_pages(r, since):
    pages = all_pages()
    if r > 0 and len(pages) > PAGE_SAMPLE:
        fresh = [p for p in pages if since and os.path.getmtime(p) > since]
        pick = set(random.Random(seeds(r)[1]).sample(pages, PAGE_SAMPLE)) | set(fresh)
        pages = sorted(pick)
    return pages


def kind_of(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return "consultation" if "consult-item" in f.read() else "presentation"
    except OSError:
        return "presentation"


def probe_batch(pages):
    """[(invariant id, page path)] for pages with unique basenames, or None when no verdict."""
    r = run(["bash", PROBE, "--invariants"] + pages)
    if r is None or r[0] not in (0, 1):
        return None
    rc, out, _ = r
    s = re.search(r"^INVARIANTS pages=(\d+) violations=(\d+)$", out, re.M)
    lines = re.findall(r"^INV (\S+) (\S+) ", out, re.M)
    by_name = {os.path.basename(p): p for p in pages}
    if not s or int(s.group(1)) != len(pages) or int(s.group(2)) != len(lines) or (rc == 0) != (not lines) \
            or any(name not in by_name for _, name in lines):
        return None
    return [(inv, by_name[name]) for inv, name in lines]


def probe_keys(pages):
    """({key}, {key: [page paths]}). The probe reports basenames and names collide, so pages go in
    batches whose basenames are unique (pages are probed where they are: relative assets resolve)."""
    bad = ({"harness:real:no-verdict"}, {})
    if not pages:
        return bad
    batches = []
    for pg in pages:
        for b in batches:
            if os.path.basename(pg) not in {os.path.basename(x) for x in b}:
                b.append(pg)
                break
        else:
            batches.append([pg])
    where = {}
    for b in batches:
        found = probe_batch(b)
        if found is None:
            return bad
        for inv, pg in found:
            where.setdefault("real:%s:%s" % (inv, kind_of(pg)), set()).add(pg)
    return set(where), {k: sorted(v) for k, v in where.items()}


def report():
    n = clean_streak()
    print("hunts-clean: %d" % n)
    return 0 if n >= NEEDED else 1


def hunt():
    os.makedirs(DIR, exist_ok=True)
    r = len(read_rows(LOG))
    since = os.path.getmtime(LOG) if os.path.isfile(LOG) else 0
    g, s = seeds(r)
    pages = real_pages(r, since)
    real, where = probe_keys(pages)
    keys = gate_sub("generated", GENERATED, g, GEN_COUNT) | gate_sub("rounds", ROUNDS, s, ROUNDS_COUNT) | real
    cur, evidence = current_kit(), {}
    for k, ps in sorted(where.items()):
        kits = [kit_of(p) for p in ps]
        evidence[k] = "old-kit only (kit %d..%d, 0 current)" % (min(kits), max(kits)) if cur not in kits else ""
        print("hunts-gate: %s: %d page(s), kit %d..%d, %d current (kit %d), e.g. %s"
              % (k, len(ps), min(kits), max(kits), kits.count(cur), cur, ps[0]), file=sys.stderr)
    ledger = {row[0]: (row[2] if len(row) > 2 else "") for row in read_rows(LEDGER)}
    harness = {k for k in keys if k.startswith("harness:")}
    new = sorted(k for k in keys if k not in ledger and k not in harness)
    noted = {k for k in new if r == 0 and evidence.get(k)}
    unexplained = sorted(k for k in keys if ledger.get(k) == "")
    with open(LEDGER, "a", encoding="utf-8") as f:
        for k in new:
            f.write("%s\t%d\t%s\n" % (k, r, evidence.get(k, "") if r == 0 else ""))
    status = "dirty" if set(new) - noted or unexplained or harness else "clean"
    with open(LOG, "a", encoding="utf-8") as f:
        f.write("%d\t%s\t%s\t%s\t%s\n" % (
            r, "gen=%d rounds=%d pages=%d" % (g, s, len(pages)), status,
            ",".join(sorted(set(new) - noted) + unexplained + sorted(harness)) or "-",
            ",".join(sorted((k for k in keys if ledger.get(k)), key=str) + sorted(noted)) or "-"))
    return report()


def main(argv):
    global DIR, LEDGER, LOG
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--state-dir", default=DEFAULT_STATE)
    a = ap.parse_args(argv)
    DIR = a.state_dir
    LEDGER, LOG = os.path.join(DIR, "ledger.tsv"), os.path.join(DIR, "rounds.tsv")
    return report() if a.report else hunt()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
