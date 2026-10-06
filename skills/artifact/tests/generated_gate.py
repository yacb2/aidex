#!/usr/bin/env python3
"""The LOOP-008 generated gate: seeded specs, each a valid page or a loud refusal.

    python3 generated_gate.py [--seed S] [--count N] [--verbose] [--shrink-dir DIR]
                              [--shrink-budget SECONDS]

stdout is exactly one line, `generated: X/Y`; everything else goes to stderr. Y = N (default
300); the specs are generate(S), generate(S+1), ... (S defaults to BASE_SEED, printed on
stderr), so `--seed <failing seed> --count 1 --verbose` reproduces one failure. Exit 0 iff
X == Y and Y >= 300 (the loop spec's floor).

A spec PASSES when
  * the builder refuses it loudly: exit non-zero, a message, no `Traceback (most recent call
    last)`, no page and no `.aidex-artifact-prev/` residue left behind, or
  * it builds and `render-probe.sh --invariants` reports no violation for that page.
All built pages go through ONE probe call. Pass criteria are strict on purpose: a probe with no
verdict fails every page it should have judged (an unmeasured page is never a pass).

--verbose lists each failure with its seed and keys, then the failures grouped into classes.
--shrink-dir shrinks failures (representatives of each class first, within --shrink-budget,
default 300 s; the probe is re-run per batch of candidates) and writes `<seed>.spec.md` there;
a failure the budget did not reach is written as generated. A shrunk spec is the SMALLEST
the greedy search found that still shows the same key (the rarest invariant the seed fires,
or the same refusal shape), not a proof of minimality.

Test seams: AIDEX_RENDER_PROBE replaces scripts/render-probe.sh with a fake.
"""
import argparse
import concurrent.futures
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import spec_gen  # noqa: E402

SCRIPTS = os.path.join(os.path.dirname(HERE), "scripts")
SPEC_BUILD = os.path.join(SCRIPTS, "spec_build.py")
PROBE = os.environ.get("AIDEX_RENDER_PROBE") or os.path.join(SCRIPTS, "render-probe.sh")
BASE_SEED = 20261007
MIN_COUNT = 300
BUILD_TIMEOUT = 120
PROBE_TIMEOUT = 900
WORKERS = max(2, min(6, os.cpu_count() or 2))
TRACEBACK = "Traceback (most recent call last)"
PASS_KINDS = ("built", "refused")


def classify_build(rc, output, page_exists, residue):
    """What one builder run was: built | refused (both can pass) | traceback | half-written |
    silent-refusal | no-page (all fail). `residue` = anything left in .aidex-artifact-prev/."""
    if TRACEBACK in output:
        return "traceback"
    if rc < 0 or "Fatal Python error" in output:
        return "crashed"
    if rc == 0:
        return "built" if page_exists else "no-page"
    if page_exists or residue:
        return "half-written"
    if not output.strip():
        return "silent-refusal"
    return "refused"


def exception_name(output):
    """`OverflowError` out of the last line of a traceback, else ''."""
    last = [ln for ln in output.strip().splitlines() if ln.strip()][-1:]
    m = re.match(r"^([A-Za-z_][\w.]*(?:Error|Exception|Exit)):", last[0]) if last else None
    return m.group(1) if m else ""


def build_one(root, tag, spec, intent="edge"):
    """Write one spec (and the assets its blocks name) in its own directory and build it.
    Returns {tag, kind, key, page, detail}; `key` is None when the build alone passes."""
    d = os.path.join(root, tag)
    os.makedirs(d)
    for name, data in spec_gen.ASSETS.items():
        with open(os.path.join(d, name), "wb") as f:
            f.write(data)
    spec_path, page = os.path.join(d, tag + ".spec.md"), os.path.join(d, tag + ".html")
    with open(spec_path, "w", encoding="utf-8", newline="") as f:
        f.write(spec)
    try:
        r = subprocess.run([sys.executable, SPEC_BUILD, spec_path, "-o", page],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=BUILD_TIMEOUT)
        out, rc = r.stdout.decode("utf-8", "replace"), r.returncode
    except subprocess.TimeoutExpired:
        return {"tag": tag, "kind": "timeout", "key": ("BUILD", "timeout", ""), "page": None,
                "detail": "build past %ds" % BUILD_TIMEOUT}
    prev = os.path.join(d, ".aidex-artifact-prev")
    residue = os.path.isdir(prev) and bool(os.listdir(prev))
    kind = classify_build(rc, out, os.path.exists(page), residue)
    lines = [ln.strip() for ln in out.strip().splitlines() if ln.strip()]
    detail = next((ln for ln in lines if ln.startswith("FAIL [")), lines[0] if lines else "")[:200]
    key = None if kind in PASS_KINDS else ("BUILD", kind, exception_name(out))
    # a refusal only counts as a pass for a spec that may be refused: an intended-valid spec the
    # builder refuses is a defect, and a refusal-only spec must refuse with its own message
    if kind == "refused" and intent == "valid":
        key = ("BUILD", "valid-refused", "")
    elif kind == "refused" and intent == "refusal-only" \
            and not any(m in out for m in spec_gen.REFUSAL_MESSAGE.values()):
        key = ("BUILD", "wrong-refusal", "")
    elif kind == "built" and intent == "refusal-only":
        key = ("BUILD", "refusal-only-built", "")
    return {"tag": tag, "kind": kind, "key": key, "detail": detail,
            "page": page if kind == "built" and intent != "refusal-only" else None}


def probe(pages):
    """{page basename: {invariant id: first message}} for the pages with a violation, or None when the probe
    gave no verdict (the same check as invariant_gate.corpus_line)."""
    if not pages:
        return {}
    try:
        r = subprocess.run(["bash", PROBE, "--invariants"] + pages, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, text=True, timeout=PROBE_TIMEOUT)
    except subprocess.TimeoutExpired:
        print("generated-gate: probe past %ds on %d page(s)" % (PROBE_TIMEOUT, len(pages)),
              file=sys.stderr)
        return None
    summary = re.search(r"^INVARIANTS pages=(\d+) violations=(\d+)$", r.stdout, re.M)
    if r.returncode not in (0, 1) or not summary or int(summary.group(1)) != len(pages):
        print("generated-gate: probe gave no verdict on %d page(s) (rc=%d): %s"
              % (len(pages), r.returncode, r.stderr.strip() or r.stdout.strip()[-200:]),
              file=sys.stderr)
        return None
    fired, lines = {}, 0
    for ln in r.stdout.splitlines():
        m = re.match(r"^INV (\S+) (\S+) (.*)$", ln)
        if m:
            lines += 1
            fired.setdefault(m.group(2), {}).setdefault(m.group(1), m.group(3))
    given = {os.path.basename(p) for p in pages}
    n = int(summary.group(2))
    why = ("%d INV line(s) but violations=%d" % (lines, n) if lines != n else
           "INV lines for pages that were not given: %s" % sorted(set(fired) - given)
           if not set(fired) <= given else
           "exit %d with violations=%d" % (r.returncode, n) if (r.returncode == 0) != (n == 0) else "")
    if why:
        print("generated-gate: probe output is inconsistent (%s); no verdict" % why, file=sys.stderr)
        return None
    return fired


def exhibits(items, with_probe=True):
    """items: [(tag, spec[, intent])]. For each, the set of failure keys it shows: ("BUILD", kind, exc)
    for a build failure, ("INV", id) per fired invariant, ("BUILD", "no-verdict", "") for a built
    page the probe could not judge. An empty set = the spec passes."""
    root = tempfile.mkdtemp(prefix="generated-gate-")
    try:
        with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
            built = list(pool.map(lambda it: build_one(root, *it), items))
        out = [set([b["key"]]) if b["key"] else set() for b in built]
        info = {b["tag"]: b["detail"] for b in built}
        for b in built:
            info["built:" + b["tag"]] = b["kind"]
            info["kind:" + b["kind"]] = info.get("kind:" + b["kind"], 0) + 1
        pages = [b["page"] for b in built if b["page"]]
        if pages and with_probe:
            fired = probe(pages)
            for b, keys in zip(built, out):
                if b["page"] is None:
                    continue
                if fired is None:
                    keys.add(("BUILD", "no-verdict", ""))
                else:
                    for i, msg in fired.get(os.path.basename(b["page"]), {}).items():
                        keys.add(("INV", i))
                        info["%s %s" % (b["tag"], i)] = msg
        return out, info
    finally:
        shutil.rmtree(root, ignore_errors=True)


def pick_targets(failures):
    """seed -> the key to shrink toward: the rarest key it shows (NAV-4 would otherwise win every
    consultation page and hide the rarer classes); ties by key order."""
    count = {}
    for keys in failures.values():
        for k in keys:
            count[k] = count.get(k, 0) + 1
    return {s: min(sorted(keys), key=lambda k: count[k]) for s, keys in failures.items()}


def shrink_jobs(jobs, deadline, batch, max_pages, log):
    """jobs: {seed: (spec, key, intent)}. Lockstep greedy shrink: each round evaluates one batch of
    candidates per active job in a single browser run. Returns {seed: smallest spec reached}."""
    best = {s: j[0] for s, j in jobs.items()}
    gens, chunks = {}, {}
    for s, (spec, _, _) in jobs.items():
        gens[s] = spec_gen.shrinker(spec, batch)
        try:
            chunks[s] = next(gens[s])
        except StopIteration:
            del gens[s]
    rnd = 0
    while gens and time.time() < deadline:
        order = sorted(gens)
        per = max(1, max_pages // batch)
        group = order[(rnd * per) % len(order):][:per] or order[:per]
        rnd += 1
        items = [("s%d_%d_%d" % (s, rnd, i), c, jobs[s][2]) for s in group for i, c in enumerate(chunks[s])]
        need_probe = any(jobs[s][1][0] == "INV" for s in group)
        shown, _ = exhibits(items, with_probe=need_probe)
        at = 0
        for s in group:
            n = len(chunks[s])
            verdicts = [jobs[s][1] in shown[at + i] for i in range(n)]
            hit = next((c for c, v in zip(chunks[s], verdicts) if v), None)
            if hit is not None:
                best[s] = hit
            at += n
            try:
                chunks[s] = gens[s].send(verdicts)
            except StopIteration:
                del gens[s]
                log("shrunk seed %d to %d lines" % (s, best[s].count("\n")))
    if gens:
        log("generated-gate: %d shrink job(s) stopped by the budget (written as far as they got)"
            % len(gens))
    return best


def source_digest():
    """sha256 of the generator and the gate, so a loop can notice an edit to either."""
    h = hashlib.sha256()
    for name in ("spec_gen.py", "generated_gate.py"):
        with open(os.path.join(HERE, name), "rb") as f:
            h.update(f.read())
    return h.hexdigest()[:16]


def fmt_key(k):
    return ":".join(x for x in k if x)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seed", type=int, default=BASE_SEED)
    ap.add_argument("--count", type=int, default=MIN_COUNT)
    ap.add_argument("--verbose", action="store_true")
    ap.add_argument("--shrink-dir")
    ap.add_argument("--shrink-budget", type=float, default=300)
    a = ap.parse_args(argv)
    log = lambda m: print(m, file=sys.stderr)          # noqa: E731
    t0 = time.time()
    log("generated-gate: base seed %d, %d specs (seeds %d..%d)"
        % (a.seed, a.count, a.seed, a.seed + a.count - 1))
    seeds = list(range(a.seed, a.seed + a.count))
    specs = {s: spec_gen.generate(s) for s in seeds}
    intents = {s: spec_gen.intent(s) for s in seeds}
    log("generated-gate: sha256 %s (spec_gen.py + generated_gate.py)" % source_digest())
    shown, details = exhibits([("g%d" % s, specs[s], intents[s]) for s in seeds])
    failures = {s: sorted(k) for s, k in zip(seeds, shown) if k}
    x, y = a.count - len(failures), a.count
    log("generated-gate: measured %d specs in %.0f s, %d failing; builds: %s"
        % (y, time.time() - t0, len(failures),
           ", ".join("%s %d" % (k[5:], v) for k, v in sorted(details.items()) if k.startswith("kind:"))))

    def why(s, k):
        return details.get("g%d %s" % (s, k[1]) if k[0] == "INV" else "g%d" % s, "")[:140]

    targets = pick_targets(failures)
    if a.verbose:
        for s in sorted(failures):
            log("  FAIL seed=%d %s" % (s, " | ".join(fmt_key(k) + ": " + why(s, k) for k in failures[s])))
    final = dict(specs)
    if a.shrink_dir and failures:
        os.makedirs(a.shrink_dir, exist_ok=True)
        by_key = {}
        for s in sorted(failures, key=lambda s: len(specs[s])):
            by_key.setdefault(targets[s], []).append(s)
        reps = {s for ss in by_key.values() for s in ss[:2]}
        start = time.time()
        for name, chosen, share, batch in (
                ("representatives", reps, 0.6, 10),
                ("the rest", set(failures) - reps, 1.0, 4)):
            jobs = {s: (final[s], targets[s], intents[s]) for s in sorted(chosen)}
            if jobs:
                log("generated-gate: shrinking %s (%d)" % (name, len(jobs)))
                final.update(shrink_jobs(jobs, start + share * a.shrink_budget, batch, 120, log))
        for s in failures:
            with open(os.path.join(a.shrink_dir, "%d.spec.md" % s), "w", encoding="utf-8", newline="") as f:
                f.write(final[s])
    if a.verbose:
        groups = {}
        for s in failures:
            for k in failures[s]:
                groups.setdefault(k, []).append(s)
        log("CLASSES (a seed can be in several; smallest spec per key):")
        for k, ss in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            # a shrunk file is known to show its OWN target key only; for another key the
            # seed counts at its generated size
            size = lambda s: len(final[s] if targets[s] == k else specs[s])  # noqa: E731
            small = min(ss, key=size)
            shrunk = bool(a.shrink_dir) and targets[small] == k
            where = os.path.join(a.shrink_dir, "%d.spec.md" % small) if shrunk else "seed %d, unshrunk" % small
            log("  %4d  %-24s %s (seed %d, %d bytes)\n        message on the unshrunk page: %s"
                % (len(ss), fmt_key(k), where, small, size(small), why(small, k)))
    print("generated: %d/%d" % (x, y))
    return 0 if x == y and y >= MIN_COUNT else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
