#!/usr/bin/env python3
"""Test suite for memory-audit-nudge.sh.

Self-contained: builds its own project trees and memory directories under a temp HOME,
so it never reads the real fleet and never writes a stamp anyone else would see.

The hook's contract is that silence is the common case — it runs on every session start
in every project — so most of these cases assert that NOTHING is printed. The four-cell
stamp-age x directory-changed matrix is the core; the rest holds the fail-open property.

  python3 hooks/test-memory-audit-nudge.py
"""
import json, os, shutil, subprocess, sys, tempfile, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(REPO, "hooks", "memory-audit-nudge.sh")
SWEEP = os.path.join(REPO, "skills", "aidex", "scripts", "memory-sweep.py")

fails = []
TOTAL = [0]


def check(name, ok, detail=""):
    TOTAL[0] += 1
    print(("  PASS  " if ok else "  FAIL  ") + name +
          (("   <- " + str(detail)[:200]) if detail and not ok else ""))
    if not ok:
        fails.append(name)


HOME = tempfile.mkdtemp(prefix="memnudge-home-")
PROJ = os.path.join(HOME, "Documents", "projects", "demo-ws")
os.makedirs(PROJ, exist_ok=True)
SLUG = PROJ.replace("/", "-")
MEMDIR = os.path.join(HOME, ".claude", "projects", SLUG, "memory")
os.makedirs(MEMDIR, exist_ok=True)
STAMPDIR = os.path.join(HOME, ".claude", "aidex", "memory-audit-stamp")
os.makedirs(STAMPDIR, exist_ok=True)

DAY = 86400


def memory(name, body="a durable fact"):
    with open(os.path.join(MEMDIR, name), "w") as fh:
        fh.write("---\nname: x\nmetadata:\n  type: project\n---\n\n%s\n" % body)


def digest():
    n = newest = total = 0
    for f in os.listdir(MEMDIR):
        if not f.endswith(".md"):
            continue
        st = os.stat(os.path.join(MEMDIR, f))
        n += 1
        total += st.st_size
        newest = max(newest, int(st.st_mtime))
    return "%d:%d:%d" % (n, newest, total)


def stamp(age_days, dig=None, raw=None):
    p = os.path.join(STAMPDIR, SLUG + ".json")
    if raw is not None:
        open(p, "w").write(raw)
        return
    json.dump({"at": int(time.time()) - age_days * DAY,
               "date": "2026-01-01",
               "digest": digest() if dig is None else dig}, open(p, "w"))


def unstamp():
    p = os.path.join(STAMPDIR, SLUG + ".json")
    if os.path.exists(p):
        os.remove(p)


def run(cwd=PROJ, session="s1"):
    env = dict(os.environ)
    env["HOME"] = HOME
    payload = json.dumps({"hook_event_name": "SessionStart", "source": "startup",
                          "cwd": cwd, "session_id": session})
    p = subprocess.run(["sh", HOOK], input=payload, env=env,
                       capture_output=True, text=True, timeout=60)
    try:
        out = json.loads(p.stdout) if p.stdout.strip() else None
    except Exception:
        out = None
    return p.returncode, out, p.stdout


def message(out):
    return ((out or {}).get("hookSpecificOutput") or {}).get("systemMessage") or ""


def fresh_session():
    """A new session id, so the once-per-session marker never masks a case."""
    fresh_session.n += 1
    return "s%d" % fresh_session.n
fresh_session.n = 0


memory("one.md")
memory("two.md")

print("== the four cells of stamp-age x directory-changed ==")

stamp(40, dig="0:0:0")                       # stale stamp, directory changed
rc, out, _ = run(session=fresh_session())
check("stale stamp + changed directory speaks", message(out) != "", out)
check("the line names the file count", "2 file(s)" in message(out), message(out))
check("and says how stale it is", "40d ago" in message(out), message(out))
check("it never blocks startup", rc == 0, rc)

stamp(40)                                     # stale stamp, digest matches: unchanged
rc, out, _ = run(session=fresh_session())
check("stale stamp + unchanged directory is SILENT", out is None, out)

stamp(3, dig="0:0:0")                        # fresh stamp, directory changed
rc, out, _ = run(session=fresh_session())
check("fresh stamp + changed directory is SILENT", out is None, out)

stamp(3)                                      # fresh stamp, unchanged
rc, out, _ = run(session=fresh_session())
check("fresh stamp + unchanged directory is SILENT", out is None, out)

print("== the boundary is 30 days, and it is a boundary ==")

stamp(29, dig="0:0:0")
rc, out, _ = run(session=fresh_session())
check("29 days is still fresh", out is None, out)
stamp(31, dig="0:0:0")
rc, out, _ = run(session=fresh_session())
check("31 days is stale", message(out) != "", out)

print("== absent stamp, empty directory ==")

unstamp()
rc, out, _ = run(session=fresh_session())
check("never audited + files present speaks", "never audited" in message(out), message(out))

empty_proj = os.path.join(HOME, "Documents", "projects", "empty-ws")
os.makedirs(empty_proj, exist_ok=True)
os.makedirs(os.path.join(HOME, ".claude", "projects",
                         empty_proj.replace("/", "-"), "memory"), exist_ok=True)
rc, out, _ = run(cwd=empty_proj, session=fresh_session())
check("an empty memory directory is silent", out is None, out)

rc, out, _ = run(cwd=os.path.join(HOME, "Documents", "projects", "no-memory-here"),
                 session=fresh_session())
check("a project with no memory directory is silent", out is None and rc == 0, out)

print("== once per project per session ==")

unstamp()
sid = fresh_session()
rc, out, _ = run(session=sid)
check("first invocation speaks", message(out) != "", out)
rc, out2, _ = run(session=sid)
check("second invocation in the same session is silent", out2 is None, out2)
rc, out3, _ = run(session=fresh_session())
check("but a new session speaks again", message(out3) != "", out3)

print("== the slug is resolved forward from cwd, never decoded backwards ==")

# An underscored project path: the memory directory carries dashes, so the plain
# `/`->`-` form does not exist on disk and only the `_`->`-` candidate resolves.
# Decoding a directory name backwards is what resolved a slug to an existing but WRONG
# directory on 2026-08-31; going forward and keeping the candidate that exists cannot.
u_proj = os.path.join(HOME, "Documents", "projects", "echo_lab_ws")
os.makedirs(u_proj, exist_ok=True)
u_slug = u_proj.replace("_", "-").replace("/", "-")
u_mem = os.path.join(HOME, ".claude", "projects", u_slug, "memory")
os.makedirs(u_mem, exist_ok=True)
open(os.path.join(u_mem, "a.md"), "w").write("---\nmetadata:\n  type: project\n---\nx\n")
rc, out, _ = run(cwd=u_proj, session=fresh_session())
check("an underscored project path resolves to its dashed slug", message(out) != "", out)

check("and it did NOT resolve to some other project's directory",
      "1 file(s)" in message(out), message(out))

print("== cwd is not always the project root ==")

unstamp()
sub = os.path.join(PROJ, "frontend", "src")
os.makedirs(sub, exist_ok=True)
rc, out, _ = run(cwd=sub, session=fresh_session())
check("a session in a subdirectory nudges about its PROJECT", message(out) != "", out)
nfiles = len([f for f in os.listdir(MEMDIR) if f.endswith(".md")])
check("and reports the project's file count (%d), not the subdirectory's" % nfiles,
      "%d file(s)" % nfiles in message(out), message(out))

# The walk must not turn $HOME into a catch-all ancestor. ~/.claude/projects/-<home>/memory
# is a real memory directory, so an unbounded walk would make every session in any
# non-project directory nudge about the user-level memory.
home_slug = HOME.replace("/", "-")
home_mem = os.path.join(HOME, ".claude", "projects", home_slug, "memory")
os.makedirs(home_mem, exist_ok=True)
open(os.path.join(home_mem, "u.md"), "w").write("---\nmetadata:\n  type: user\n---\nx\n")

stray = os.path.join(HOME, "Downloads", "scratch")
os.makedirs(stray, exist_ok=True)
rc, out, _ = run(cwd=stray, session=fresh_session())
check("a session outside any project does NOT nudge about the home directory",
      out is None, out)

rc, out, _ = run(cwd=HOME, session=fresh_session())
check("but an exact cwd of the home directory still resolves", message(out) != "", out)

print("== --stamp is what silences it, and only when passed ==")

# End-to-end: the acceptance case "changed directory under a fresh stamp is silent" is
# only meaningful if something actually writes stamps. That something is the sweep.
unstamp()
memory("three.md")
rc, out, _ = run(session=fresh_session())
check("drifted again, so it speaks", message(out) != "", out)

env = dict(os.environ)
env["HOME"] = HOME
env["AIDEX_MEMORY_ROOT"] = os.path.join(HOME, ".claude", "projects")
subprocess.run([sys.executable, SWEEP, "--project=" + SLUG], env=env,
               capture_output=True, text=True, timeout=120)
rc, out, _ = run(session=fresh_session())
check("a PLAIN sweep does not stamp — a look is not an audit", message(out) != "", out)

subprocess.run([sys.executable, SWEEP, "--project=" + SLUG, "--stamp"], env=env,
               capture_output=True, text=True, timeout=120)
rc, out, _ = run(session=fresh_session())
check("--stamp silences the nudge", out is None, out)

memory("four.md")
rc, out, _ = run(session=fresh_session())
check("a change under a FRESH stamp stays silent — both conditions are required",
      out is None, out)


def backdate(days):
    """Age the stamp in place, keeping the digest it recorded.

    Testing digest sensitivity needs a STALE stamp: the hook requires stale AND changed,
    so a rewrite one second after stamping is correctly silent and proves nothing about
    the digest.
    """
    p = os.path.join(STAMPDIR, SLUG + ".json")
    d = json.load(open(p))
    d["at"] = int(time.time()) - days * DAY
    json.dump(d, open(p, "w"))


backdate(40)
rc, out, _ = run(session=fresh_session())
check("that same change under a STALE stamp does speak", message(out) != "", out)

# The digest has to notice a rewrite that leaves the file COUNT identical. Phases 6-8 of
# this plan rewrite memories in place, which is exactly that shape: count unchanged, only
# size and mtime move. A count-only digest would go silent on the whole cleanup.
os.remove(os.path.join(MEMDIR, "four.md"))
subprocess.run([sys.executable, SWEEP, "--project=" + SLUG, "--stamp"], env=env,
               capture_output=True, text=True, timeout=120)
backdate(40)
rc, out, _ = run(session=fresh_session())
check("stale stamp over an untouched directory: silent", out is None, out)

before = digest()
memory("three.md", "a completely different and much longer durable fact than it had")
check("the rewrite left the file count unchanged",
      before.split(":")[0] == digest().split(":")[0], (before, digest()))
rc, out, _ = run(session=fresh_session())
check("a rewrite at an unchanged file count is still detected", message(out) != "", out)

print("== --stamp refuses to stamp what it did not audit ==")

# A bare sweep touches every directory. Stamping all of them after a run that reviewed a
# handful silences the nudge fleet-wide — and a tiered cleanup reaching some projects and
# not others is exactly that shape.
p = subprocess.run([sys.executable, SWEEP, "--stamp"], env=env,
                   capture_output=True, text=True, timeout=180)
check("--stamp without --project= is refused", p.returncode == 2, p.returncode)
check("and says why", "nobody audited" in p.stderr, p.stderr[:200])

print("== fails open and silent ==")

stamp(0, raw="{not json")
rc, out, _ = run(session=fresh_session())
check("a malformed stamp is silent, not noisy", out is None and rc == 0, out)

stamp(0, raw=json.dumps({"digest": "1:2:3"}))
rc, out, _ = run(session=fresh_session())
check("a stamp with no timestamp is silent", out is None and rc == 0, out)

env2 = dict(os.environ)
env2["HOME"] = HOME
p = subprocess.run(["sh", HOOK], input="not json at all", env=env2,
                   capture_output=True, text=True, timeout=60)
check("malformed stdin exits 0 silently", p.returncode == 0 and not p.stdout.strip(),
      p.stdout)

p = subprocess.run(["sh", HOOK], input="{}", env=env2,
                   capture_output=True, text=True, timeout=60)
check("no cwd exits 0 silently", p.returncode == 0 and not p.stdout.strip(), p.stdout)

shutil.rmtree(HOME, ignore_errors=True)

print("\nmemory-audit-nudge: %d checks, %d failed" % (TOTAL[0], len(fails)))
if fails:
    print("failed: " + ", ".join(fails))
sys.exit(1 if fails else 0)
