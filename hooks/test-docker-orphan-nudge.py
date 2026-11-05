#!/usr/bin/env python3
"""Test suite for docker-orphan-nudge.sh (BL-810, BL-811).

Layer: the hook as a process, fed SessionStart stdin, under a temp HOME. The hook is
copied into a temp plugin tree whose orphan-sweep.sh is a fake that logs its argv and
PATH, so no test ever reaches a Docker daemon.

Protects: silence unless the last complete scan found a candidate orphan of the session's
own project (BL-903: the stdin cwd, resolved like the worktree skill, names it); once a
day at most per project; no removal command in the message, which says to verify by hand and points only at
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
# The real shared library: the hook resolves the session's project with it.
os.makedirs(os.path.join(PLUGIN, "skills", "conventions", "scripts"))
shutil.copy(os.path.join(REPO, "skills", "conventions", "scripts", "_lib.sh"),
            os.path.join(PLUGIN, "skills", "conventions", "scripts", "_lib.sh"))
SWEEP_LOG = os.path.join(ROOT, "sweep.log")
# The hook runs from its own empty cwd, so a config dir resolved against the cwd shows.
CWD = os.path.join(ROOT, "cwd")
os.makedirs(CWD)
with open(os.path.join(SWEEP_DIR, "orphan-sweep.sh"), "w") as fh:
    # Sleeps so a hook that waited for it would be measurably slow.
    fh.write('echo "$* | PATH=$PATH | CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR" >> "%s"\nsleep 2\n' % SWEEP_LOG)

# Session projects (BL-903). A split workspace: recomed_ws holds .context/, its nested
# repo backend/ a .git and no .context/; the workspace root is the project.
PROJECTS = os.path.join(ROOT, "projects")
# "My Shop.WS" is not a compose name: it normalises to myshopws, as compose names do.
for name in ("shop_ws", "recomed_ws", "recomed", "travel_ws", "My Shop.WS"):
    os.makedirs(os.path.join(PROJECTS, name, ".context"))
SHOP = os.path.join(PROJECTS, "shop_ws")
RECOMED = os.path.join(PROJECTS, "recomed_ws")
os.makedirs(os.path.join(RECOMED, "backend", "app"))
subprocess.run(["git", "init", "-q", os.path.join(RECOMED, "backend")], check=True)

DIR = os.path.join(HOME, ".claude", "tmp", "docker-orphans")
SUMMARY = os.path.join(DIR, "summary")
STAMP = os.path.join(DIR, "nudged-shop_ws")
LOCK = os.path.join(DIR, "scan.lock")
TODAY = time.strftime("%Y-%m-%d")


def reset():
    shutil.rmtree(DIR, ignore_errors=True)
    if os.path.exists(SWEEP_LOG):
        os.remove(SWEEP_LOG)


def summary(status="ok", candidates=0, names="", at=1760000000, age_h=0, d=DIR):
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, "summary")
    with open(path, "w") as fh:
        fh.write("scanned_at=%d\nstatus=%s\ncandidates=%d\ncandidate_projects=%s\n" % (at, status, candidates, names))
    t = time.time() - age_h * 3600
    os.utime(path, (t, t))


def run(cwd=SHOP, **extra):
    env = {"HOME": HOME, "PATH": os.environ["PATH"], **extra}
    t0 = time.time()
    stdin = {"hook_event_name": "SessionStart", "source": "startup"}
    if cwd is not None:
        stdin["cwd"] = cwd
    p = subprocess.run(["bash", HOOK], input=json.dumps(stdin),
                       capture_output=True, text=True, env=env, timeout=10, cwd=CWD)
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
    summary(candidates=3, names="bpsync-check shop_ws-wt-gone shop_ws-wt-old")
    p, _ = run()
    m = message(p) or ""
    check("candidates: speaks", "2 compose project(s)" in m, p.stdout)
    check("candidates: names the projects", "(shop_ws-wt-gone shop_ws-wt-old)" in m, m)
    check("candidates: says nothing was deleted", "Nothing was deleted" in m, m)
    check("candidates: says verify by hand", "verify by hand before removing anything" in m, m)
    check("candidates: no removal command in the message", "docker " not in m and "rm " not in m and "down" not in m, m)
    # `/aidex:worktree status` runs the default, workspace-scoped sweep, which prints
    # `down` (no -v) / `rmi` / `network rm` for a live worktree moved with a plain `mv` whose
    # stack is stopped (stale working_dir, no container running).
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
    summary(candidates=1, names="shop_ws-wt-old", age_h=21)
    p, _ = run()
    check("stale: speaks from the last summary", "shop_ws-wt-old" in (message(p) or ""), p.stdout)
    check("stale: scan relaunched", wait_for(SWEEP_LOG))
    wait_for(LOCK, present=False)

    print("== only the session's own project is shown (BL-903) ==")
    # A travel_ws session showed recomed_ws-wt-bl210-p5: the hook discarded its stdin and
    # the once-a-day stamp went to whichever project started first.
    BL210 = "recomed_ws-wt-bl210-p5"
    for label, cwd, names, want in [
            ("unrelated project", os.path.join(PROJECTS, "travel_ws"), BL210, None),
            ("owning project", RECOMED, BL210, ["1 compose project(s)", "containers (%s)," % BL210]),
            ("subdirectory of a nested repo", os.path.join(RECOMED, "backend", "app"), BL210,
             ["containers (%s)," % BL210]),
            ("the project's own compose project", RECOMED, "recomed_ws", ["containers (recomed_ws),"]),
            ("other projects dropped from count and list", RECOMED,
             "bpsync-check recomed-wt-x %s shop_ws-wt-gone" % BL210,
             ["1 compose project(s)", "containers (%s)," % BL210]),
            ("prefix project does not take the longer name", os.path.join(PROJECTS, "recomed"), BL210, None),
            ("longer project does not take the prefix name", RECOMED, "recomed-wt-x recomed_wsx-wt-x", None),
            ("uppercase, space and dot normalised like compose", os.path.join(PROJECTS, "My Shop.WS"),
             "myshopws-wt-a other_ws-wt-b", ["1 compose project(s)", "containers (myshopws-wt-a),"]),
            ("no cwd in stdin", None, BL210, None)]:
        reset()
        summary(candidates=len(names.split()), names=names)
        m = message(run(cwd=cwd)[0])
        check("%s: %s" % (label, "silent" if want is None else "names it"),
              m is None if want is None else all(w in (m or "") for w in want), m)
    reset()
    summary(candidates=1, names=BL210)
    run(cwd=os.path.join(PROJECTS, "travel_ws"))
    check("same day: an unrelated project first does not silence the owner",
          BL210 in (message(run(cwd=RECOMED)[0]) or ""))
    summary(candidates=2, names=BL210 + " shop_ws-wt-gone")
    check("same day: one project's notice does not silence another's",
          "shop_ws-wt-gone" in (message(run()[0]) or ""))

    print("== the summary is read from CLAUDE_CONFIG_DIR, never a hard-coded ~/.claude ==")
    # A session started with CLAUDE_CONFIG_DIR=~/.claude-work read and stamped the personal
    # ~/.claude. Surrounding whitespace is trimmed (BL-892). A leading ~ or ~/ is the home
    # directory; unset, empty, relative or ~user means $HOME/.claude, never a tree under the cwd.
    for label, cfg, where in [("set", os.path.join(ROOT, "cfg"), os.path.join(ROOT, "cfg")),
                              ("padded", " %s \t" % os.path.join(ROOT, "cfg-padded"),
                               os.path.join(ROOT, "cfg-padded")),
                              ("tilde-user", "~root/x", ".claude"),
                              # Only ASCII whitespace is trimmed (a UTF-8 [:space:] also
                              # matched U+00A0, unlike the Python hooks).
                              ("nbsp", "\u00a0" + os.path.join(ROOT, "cfg-nbsp"), ".claude"),
                              ("empty", "", ".claude"), ("tilde", "~/x", "x"),
                              ("relative", "rel", ".claude")]:
        home = os.path.join(ROOT, "h-" + label)
        shutil.rmtree(CWD)
        os.makedirs(CWD)
        summary(candidates=1, names="shop_ws-wt-cfg-" + label,
                d=os.path.join(home, where, "tmp", "docker-orphans"))
        p, _ = run(HOME=home, CLAUDE_CONFIG_DIR=cfg, LC_ALL="en_US.UTF-8")
        check("CLAUDE_CONFIG_DIR %s: speaks from that summary" % label,
              "cfg-" + label in (message(p) or ""), p.stdout)
        check("CLAUDE_CONFIG_DIR %s: nothing created in the cwd" % label, os.listdir(CWD) == [],
              os.listdir(CWD))
        if label in ("set", "padded", "tilde"):
            check("CLAUDE_CONFIG_DIR %s: nothing written under $HOME/.claude" % label,
                  not os.path.exists(os.path.join(home, ".claude")))

    print("== the scan is launched for the same config dir ==")
    # Once a day per config dir: the detached scan must write the summary this hook reads,
    # so it inherits CLAUDE_CONFIG_DIR and holds its lock in that directory.
    reset()
    home, cfg = os.path.join(ROOT, "h-scan"), os.path.join(ROOT, "cfg-scan")
    run(HOME=home, CLAUDE_CONFIG_DIR=cfg)
    check("missing summary under cfg: scan.lock taken under it",
          os.path.isdir(os.path.join(cfg, "tmp", "docker-orphans", "scan.lock")))
    want, end = "CLAUDE_CONFIG_DIR=%s\n" % cfg, time.time() + 6
    log = ""
    while want not in log and time.time() < end:   # a scan an earlier row launched may log first
        time.sleep(0.1)
        log = open(SWEEP_LOG).read() if os.path.exists(SWEEP_LOG) else ""
    check("missing summary under cfg: the scan carries CLAUDE_CONFIG_DIR", want in log,
          log.replace(os.environ["PATH"], "<PATH>"))
    check("missing summary under cfg: nothing under $HOME/.claude",
          not os.path.exists(os.path.join(home, ".claude")))
    wait_for(os.path.join(cfg, "tmp", "docker-orphans", "scan.lock"), present=False)
finally:
    shutil.rmtree(ROOT, ignore_errors=True)

print("\nRESULT: %d passed, %d failed" % (TOTAL[0] - len(fails), len(fails)))
sys.exit(1 if fails else 0)
