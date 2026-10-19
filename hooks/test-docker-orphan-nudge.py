#!/usr/bin/env python3
"""Test suite for docker-orphan-nudge.sh (BL-810, BL-811).

Layer: the hook as a process, fed SessionStart stdin, under a temp HOME. The hook is
copied into a temp plugin tree whose orphan-sweep.sh is a fake that logs its argv and
PATH, so no test ever reaches a Docker daemon.

Protects: silence unless the last complete scan found a candidate orphan; once a day at
most; no removal command in the message, which says to verify by hand and points only at
the read-only `orphan-sweep.sh --all` listing; the scan is launched
detached, with docker's directories on PATH, only when the summary is stale.

  python3 hooks/test-docker-orphan-nudge.py
"""
import json, os, shutil, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK_SRC = os.path.join(REPO, "hooks", "docker-orphan-nudge.sh")

fails = []
TOTAL = [0]


def check(name, ok, detail=""):
    TOTAL[0] += 1
    print(("  PASS  " if ok else "  FAIL  ") + name +
          (("   <- " + str(detail)[:300]) if detail and not ok else ""))
    if not ok:
        fails.append(name)


ROOT = tempfile.mkdtemp(prefix="dknudge-")
HOME = os.path.join(ROOT, "home")
PLUGIN = os.path.join(ROOT, "plugin")
os.makedirs(os.path.join(PLUGIN, "hooks"))
SWEEP_DIR = os.path.join(PLUGIN, "skills", "worktree", "scripts")
os.makedirs(SWEEP_DIR)
HOOK = os.path.join(PLUGIN, "hooks", "docker-orphan-nudge.sh")
shutil.copy(HOOK_SRC, HOOK)
SWEEP_LOG = os.path.join(ROOT, "sweep.log")
with open(os.path.join(SWEEP_DIR, "orphan-sweep.sh"), "w") as fh:
    # Sleeps so a hook that waited for it would be measurably slow.
    fh.write('echo "$* | PATH=$PATH" >> "%s"\nsleep 2\n' % SWEEP_LOG)

DIR = os.path.join(HOME, ".claude", "tmp", "docker-orphans")
SUMMARY = os.path.join(DIR, "summary")
STAMP = os.path.join(DIR, "nudged")
LOCK = os.path.join(DIR, "scan.lock")
TODAY = time.strftime("%Y-%m-%d")


def reset():
    shutil.rmtree(DIR, ignore_errors=True)
    if os.path.exists(SWEEP_LOG):
        os.remove(SWEEP_LOG)


def summary(status="ok", candidates=0, names="", at=1760000000, age_h=0):
    os.makedirs(DIR, exist_ok=True)
    with open(SUMMARY, "w") as fh:
        fh.write("scanned_at=%d\nstatus=%s\ncandidates=%d\ncandidate_projects=%s\n" % (at, status, candidates, names))
    t = time.time() - age_h * 3600
    os.utime(SUMMARY, (t, t))


def run():
    env = {"HOME": HOME, "PATH": os.environ["PATH"]}
    t0 = time.time()
    p = subprocess.run(["bash", HOOK], input=json.dumps({"hook_event_name": "SessionStart", "source": "startup"}),
                       capture_output=True, text=True, env=env, timeout=10)
    return p, time.time() - t0


def message(p):
    if not p.stdout.strip():
        return None
    return json.loads(p.stdout)["systemMessage"]


def wait_for(path, present=True, limit=6.0):
    end = time.time() + limit
    while time.time() < end:
        if os.path.exists(path) == present:
            return True
        time.sleep(0.1)
    return False


try:
    print("== no summary: silent, launches the scan detached ==")
    reset()
    p, dt = run()
    check("no summary: silent", message(p) is None, p.stdout)
    check("no summary: exit 0", p.returncode == 0, p.returncode)
    check("no summary: hook does not wait for the scan", dt < 1.5, dt)
    check("no summary: scan launched", wait_for(SWEEP_LOG))
    time.sleep(0.2)
    log = open(SWEEP_LOG).read() if os.path.exists(SWEEP_LOG) else ""
    check("scan runs --all --write-summary", log.startswith("--all --write-summary |"), log)
    check("scan PATH carries docker's directories", "PATH=/usr/local/bin:/opt/homebrew/bin:" in log, log)
    check("lock released when the scan ends", wait_for(LOCK, present=False))

    print("== a held lock: no second scan ==")
    reset()
    os.makedirs(LOCK)
    run()
    time.sleep(0.5)
    check("held lock: no scan launched", not os.path.exists(SWEEP_LOG))

    print("== candidates: one line, no command, once a day ==")
    reset()
    summary(candidates=2, names="bpsync-check shop_ws-wt-gone")
    p, _ = run()
    m = message(p) or ""
    check("candidates: speaks", "2 compose project(s)" in m, p.stdout)
    check("candidates: names the projects", "bpsync-check shop_ws-wt-gone" in m, m)
    check("candidates: says nothing was deleted", "Nothing was deleted" in m, m)
    check("candidates: says verify by hand", "verify by hand before removing anything" in m, m)
    check("candidates: no removal command in the message", "docker " not in m and "rm " not in m and "down" not in m, m)
    # `/aidex:worktree status` runs the default, workspace-scoped sweep, which prints
    # `down -v` / `volume rm` for a live worktree outside $WS_PARENT/$WS_NAME-wt-*.
    check("candidates: pointer is the label-judged listing, not status",
          'bash "%s" --all' % os.path.realpath(os.path.join(SWEEP_DIR, "orphan-sweep.sh")) in m and "worktree status" not in m, m)
    check("fresh summary: no scan launched", not wait_for(SWEEP_LOG, limit=0.5))
    p, _ = run()
    check("candidates: silent the second time today", message(p) is None, p.stdout)
    with open(STAMP, "w") as fh:
        fh.write("2000-01-01\n")
    p, _ = run()
    check("candidates: speaks again on a later day", message(p) is not None, p.stdout)

    print("== no candidate: silent ==")
    reset()
    summary(candidates=0)
    p, _ = run()
    check("zero candidates: silent", message(p) is None, p.stdout)

    print("== an incomplete scan never speaks ==")
    reset()
    summary(status="degraded", candidates=2, names="x y")
    p, _ = run()
    check("status not ok: silent", message(p) is None, p.stdout)

    print("== a stale summary is still read, and refreshed ==")
    reset()
    summary(candidates=1, names="old", age_h=21)
    p, _ = run()
    check("stale: speaks from the last summary", "old" in (message(p) or ""), p.stdout)
    check("stale: scan relaunched", wait_for(SWEEP_LOG))
    wait_for(LOCK, present=False)
finally:
    shutil.rmtree(ROOT, ignore_errors=True)

print("\nRESULT: %d passed, %d failed" % (TOTAL[0] - len(fails), len(fails)))
sys.exit(1 if fails else 0)
