#!/usr/bin/env python3
"""Test suite for memory-save-gate.sh.

Self-contained: builds its own memory directories under a temp HOME, so it never
reads or writes the real fleet. It exercises the REPO copy of memory-sweep.py via
AIDEX_MEMORY_SWEEP — the installed copy can lag the repo, and on 2026-08-31 it did.

The gate's contract is that it cannot prevent work by failing, so the fail-open cases
are not an afterthought here: a hook that blocks when its own dependency breaks is
worse than no hook.

  python3 hooks/test-memory-save-gate.py
"""
import json, os, subprocess, sys, tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOOK = os.path.join(REPO, "hooks", "memory-save-gate.sh")
SWEEP = os.path.join(REPO, "skills", "aidex", "scripts", "memory-sweep.py")
FIXTURES = os.path.join(REPO, "skills", "aidex", "tests", "fixtures")

fails = []
TOTAL = [0]


def check(name, ok, detail=""):
    TOTAL[0] += 1
    print(("  PASS  " if ok else "  FAIL  ") + name +
          (("   <- " + str(detail)[:200]) if detail and not ok else ""))
    if not ok:
        fails.append(name)


HOME = tempfile.mkdtemp(prefix="memgate-home-")
MEMDIR = os.path.join(HOME, ".claude", "projects", "-probe-proj", "memory")
os.makedirs(MEMDIR, exist_ok=True)

# unpushed-is-not-a-fact can only speak when the memory's slug resolves to a real git
# repo — with no repo it returns nothing, deliberately ("cannot verify: never accuse").
# So that one case lives under a slug that decodes to THIS repo. Read-only: the check
# runs `git cat-file` and `git for-each-ref`, nothing that writes.
REPO_SLUG = REPO.replace("_", "-").replace("/", "-")
GITMEMDIR = os.path.join(HOME, ".claude", "projects", REPO_SLUG, "memory")
os.makedirs(GITMEMDIR, exist_ok=True)


def run(payload, sweep=SWEEP, raw=None):
    """Returns (returncode, parsed-json-or-None, stdout)."""
    env = dict(os.environ)
    env["HOME"] = HOME
    if sweep is None:
        env.pop("AIDEX_MEMORY_SWEEP", None)
        env["AIDEX_MEMORY_SWEEP"] = os.path.join(HOME, "does-not-exist.py")
    else:
        env["AIDEX_MEMORY_SWEEP"] = sweep
    body = raw if raw is not None else json.dumps(payload)
    p = subprocess.run(["sh", HOOK], input=body, env=env,
                       capture_output=True, text=True, timeout=60)
    try:
        out = json.loads(p.stdout) if p.stdout.strip() else None
    except Exception:
        out = None
    return p.returncode, out, p.stdout


def write_ev(name, content):
    return {"tool_name": "Write",
            "tool_input": {"file_path": os.path.join(MEMDIR, name), "content": content}}


def decision(out):
    return ((out or {}).get("hookSpecificOutput") or {}).get("permissionDecision")


def reason(out):
    hs = (out or {}).get("hookSpecificOutput") or {}
    return hs.get("permissionDecisionReason") or hs.get("additionalContext") or ""


TYPED = "---\nname: x\nmetadata:\n  type: project\n---\n\n%s\n"

print("== blocks: the shapes that cannot be undone once written ==")

rc, out, _ = run(write_ev("s.md", TYPED % 'Set api_key = "Ab3xQ7zL9mNp2Rt5" in the config.'))
check("a credential-shaped token is denied", decision(out) == "deny", out)
check("the message names the check id", "no-secrets" in reason(out), reason(out))
check("and carries the waiver syntax", "memory-gate: waived" in reason(out), reason(out))
check("a block still exits 0 — the DECISION is the JSON, not the status", rc == 0, rc)

def git_ev(name, content):
    return {"tool_name": "Write",
            "tool_input": {"file_path": os.path.join(GITMEMDIR, name), "content": content}}

rc, out, _ = run(git_ev("u.md", TYPED % "I just fixed it in commit `deadbee` on a local branch."))
check("an unreachable commit SHA is denied", decision(out) == "deny", out)
check("named as unpushed-is-not-a-fact", "unpushed-is-not-a-fact" in reason(out), reason(out))

# The other half of that check: a SHA that IS reachable must pass, or the check is just
# "mentions a hex string" and every honest commit citation becomes a block.
head = subprocess.run(["git", "-C", REPO, "rev-parse", "--short=8", "HEAD"],
                      capture_output=True, text=True).stdout.strip()
rc, out, _ = run(git_ev("uok.md", TYPED % ("The fix landed in commit `%s`." % head)))
check("a reachable commit SHA is not denied (%s)" % head, decision(out) != "deny", reason(out))

# With no resolvable project the check must stay silent rather than accuse.
rc, out, _ = run(write_ev("u2.md", TYPED % "I just fixed it in commit `deadbee`."))
check("no resolvable repo means no accusation", decision(out) != "deny", out)

print("== allows: everything the checks only advise on ==")

# pending-needs-a-ticket is ADVISORY, not blocking. Phase 1 measured it firing on 21%
# of 429 real memories; a gate at that rate teaches people to bypass it. The plan's
# Contract block said BLOCK and was amended to match the code, not the other way round.
rc, out, _ = run(write_ev("p.md", TYPED % "Wiring the exporter is still pending."))
check("a 'pending' claim with no BL-NNN is NOT denied", decision(out) != "deny", out)
check("but it is nudged", "pending-needs-a-ticket" in reason(out), reason(out))

rc, out, _ = run(write_ev("n.md", TYPED % "The runner lives in `scripts/does-not-exist.sh`."))
check("a missing named thing is nudged, not denied", decision(out) != "deny", out)

rc, out, _ = run(write_ev("c.md", TYPED % "The staging mailer catches every outbound message."))
check("a clean memory produces no output at all", out is None, out)
check("and exits 0", rc == 0, rc)

print("== the waiver downgrades blocks, except no-secrets ==")

waived = TYPED % ("memory-gate: waived — the SHA is quoted from an upstream changelog\n\n"
                  "Upstream fixed it in commit `deadbee`.")
rc, out, _ = run(write_ev("w.md", waived))
check("a waived block is allowed", decision(out) != "deny", out)

waived_secret = TYPED % ('memory-gate: waived — I promise it is fine\n\n'
                         'api_key = "Ab3xQ7zL9mNp2Rt5"')
rc, out, _ = run(write_ev("ws.md", waived_secret))
check("no-secrets refuses to be waived", decision(out) == "deny", out)

print("== scope: only memory files, only the resulting body ==")

ev = {"tool_name": "Write",
      "tool_input": {"file_path": os.path.join(HOME, "notes.md"),
                     "content": 'api_key = "Ab3xQ7zL9mNp2Rt5"'}}
rc, out, _ = run(ev)
check("a path outside the glob passes untouched", out is None and rc == 0, out)

ev = {"tool_name": "Write",
      "tool_input": {"file_path": os.path.join(MEMDIR, "sub", "deep.md"),
                     "content": 'api_key = "Ab3xQ7zL9mNp2Rt5"'}}
rc, out, _ = run(ev)
check("a path BELOW memory/ is not a memory file", out is None, out)

rc, out, _ = run({"tool_name": "Read",
                  "tool_input": {"file_path": os.path.join(MEMDIR, "s.md")}})
check("a non-write tool is ignored", out is None and rc == 0, out)

# Edit/MultiEdit carry a fragment, not the resulting file. Only no-secrets runs there.
rc, out, _ = run({"tool_name": "Edit", "tool_input": {
    "file_path": os.path.join(MEMDIR, "e.md"), "old_string": "a",
    "new_string": 'api_key = "Ab3xQ7zL9mNp2Rt5"'}})
check("Edit still catches a secret in the fragment", decision(out) == "deny", out)

rc, out, _ = run({"tool_name": "Edit", "tool_input": {
    "file_path": os.path.join(MEMDIR, "e.md"), "old_string": "a",
    "new_string": "Wiring the exporter is still pending."}})
check("but a fragment is not judged as a whole memory", out is None, out)

rc, out, _ = run({"tool_name": "MultiEdit", "tool_input": {
    "file_path": os.path.join(MEMDIR, "e.md"),
    "edits": [{"old_string": "a", "new_string": "harmless"},
              {"old_string": "b", "new_string": 'api_key = "Ab3xQ7zL9mNp2Rt5"'}]}})
check("MultiEdit scans every edit's new_string", decision(out) == "deny", out)

print("== the index: real indexes must pass ==")

# The plan named "the index regenerator" as this test's subject. No such script exists
# in the repo (verified 2026-08-31: skills/aidex/scripts/ holds no regenerator), so the
# subject is the known-good index fixtures instead. If one ever fails, the defect is in
# whatever produced the index, which is the correct place for it to surface.
idx_seen = 0
for root, _, files in os.walk(FIXTURES):
    if "known-good" not in root and "fixture-idx" not in root:
        continue
    for f in files:
        if f != "MEMORY.md":
            continue
        idx_seen += 1
        content = open(os.path.join(root, f)).read()
        rc, out, _ = run(write_ev("MEMORY.md", content))
        check("known-good index passes the gate (%s)" % os.path.basename(root),
              decision(out) != "deny", reason(out))
check("at least one known-good index was actually tested", idx_seen > 0, idx_seen)

# And the index check has teeth — otherwise the line above proves nothing.
fat = "\n".join("- [Item %d](f%d.md) — %s" % (i, i, "word " * 60) for i in range(40))
rc, out, _ = run(write_ev("MEMORY.md", fat))
check("an index carrying its content IS denied", decision(out) == "deny", out)
check("named as index-is-an-index", "index-is-an-index" in reason(out), reason(out))

print("== fails open on every internal error ==")

rc, out, _ = run(write_ev("s.md", TYPED % 'api_key = "Ab3xQ7zL9mNp2Rt5"'), sweep=None)
check("missing memory-sweep.py allows the write", out is None and rc == 0, out)

rc, out, _ = run(None, raw="this is not json")
check("malformed stdin allows the write", out is None and rc == 0, out)

rc, out, _ = run(None, raw="")
check("empty stdin allows the write", out is None and rc == 0, out)

rc, out, _ = run({"tool_name": "Write", "tool_input": {}})
check("a Write with no file_path allows", out is None and rc == 0, out)

broken = os.path.join(HOME, "broken-sweep.py")
open(broken, "w").write("raise RuntimeError('import blew up')\n")
rc, out, _ = run(write_ev("s.md", TYPED % 'api_key = "Ab3xQ7zL9mNp2Rt5"'), sweep=broken)
check("a module that raises on import allows the write", out is None and rc == 0, out)

# One broken CHECK must not decide the write either — the others still run.
partial = os.path.join(HOME, "partial-sweep.py")
open(partial, "w").write(
    open(SWEEP).read() +
    "\ndef _boom(path, body, ctx):\n    raise RuntimeError('check blew up')\n"
    "CHECKS['unpushed-is-not-a-fact'] = _boom\n")
rc, out, _ = run(write_ev("s.md", TYPED % 'api_key = "Ab3xQ7zL9mNp2Rt5"'), sweep=partial)
check("a check that raises does not stop the others", decision(out) == "deny", out)

print("== the decision log records the decision, never the body ==")

logf = os.path.join(HOME, ".claude", "aidex", "memory-gate.jsonl")
check("the log exists after the runs above", os.path.isfile(logf), logf)
if os.path.isfile(logf):
    raw = open(logf).read()
    check("it never contains a blocked secret", "Ab3xQ7zL9mNp2Rt5" not in raw)
    rows = [json.loads(l) for l in raw.splitlines() if l.strip()]
    check("every row carries a decision and its rules",
          all(r.get("decision") in ("deny", "nudge") and isinstance(r.get("rules"), list)
              for r in rows), rows[:2])
    check("denies were logged", any(r["decision"] == "deny" for r in rows))
    check("nudges were logged", any(r["decision"] == "nudge" for r in rows))

print("\nmemory-save-gate: %d checks, %d failed" % (TOTAL[0], len(fails)))
if fails:
    print("failed: " + ", ".join(fails))
sys.exit(1 if fails else 0)
