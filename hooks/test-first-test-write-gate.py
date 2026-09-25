#!/usr/bin/env python3
"""Tests for hooks/first-test-write-gate.sh.

The hook denies the first Write of a NEW test file once per (session, agent) so the
testing core is read before the first test lands. The deny cells are the cheap half;
the allow cells guard the misfire that would get it unwired: blocking every test
write, blocking edits of existing tests, blocking non-test files, or never releasing.

The path table is also run through census.py's is_test: the census counts exactly the
writes this hook gates, and the two regexes drifting apart moves the census number
without an error.

Run: python3 hooks/test-first-test-write-gate.py
"""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HOOK = os.path.join(HERE, "first-test-write-gate.sh")
CENSUS = os.path.join(HERE, "..", "skills", "testing", "scripts", "census.py")

fails = []
total = 0


def check(name, ok):
    global total
    total += 1
    print(("  PASS  " if ok else "  FAIL  ") + name)
    if not ok:
        fails.append(name)


def run(home, stdin):
    p = subprocess.run(["sh", HOOK], input=stdin, capture_output=True, text=True,
                       env=dict(os.environ, HOME=home))
    return p.returncode, p.stdout


def call(home, path, tool="Write", session="s1", agent=None):
    ev = {"tool_name": tool, "session_id": session,
          "tool_input": {"file_path": path, "content": "x"}}
    if agent is not None:
        ev["agent_id"] = agent
    code, out = run(home, json.dumps(ev))
    decision, reason = "allow", ""
    if out.strip():
        try:
            h = json.loads(out)["hookSpecificOutput"]
            decision, reason = h["permissionDecision"], h["permissionDecisionReason"]
        except (ValueError, KeyError):
            decision = "UNPARSEABLE"
    return code, decision, reason


home = tempfile.mkdtemp()
repo = tempfile.mkdtemp()
state_dir = os.path.join(home, ".claude", "aidex", "first-test-write")
new = lambda rel: os.path.join(repo, rel)  # never created on disk

# ---- deny once, then release ----
code, d, reason = call(home, new("tests/test_a.py"))
check("first new test_*.py Write is denied", code == 0 and d == "deny")
check("reason names aidex:testing (the census detects the deny by it)", "aidex:testing" in reason)
check("reason is at most 8 lines", 0 < len(reason.splitlines()) <= 8)
m = re.search(r"Read (\S+SKILL\.md)", reason)
check("the SKILL.md the reason names exists", bool(m) and os.path.isfile(m.group(1)))
check("second new test Write by the same (session, main) is allowed",
      call(home, new("tests/test_b.py"))[1] == "allow")
check("a retry of the denied path itself is allowed", call(home, new("tests/test_a.py"))[1] == "allow")

# ---- keys: agent_id and session are separate budgets ----
check("a subagent in the same session is denied on its own",
      call(home, new("tests/test_c.py"), agent="a1")[1] == "deny")
check("... once", call(home, new("tests/test_d.py"), agent="a1")[1] == "allow")
check("a second subagent is denied on its own",
      call(home, new("tests/test_e.py"), agent="a2")[1] == "deny")
check("main of another session is denied on its own",
      call(home, new("tests/test_f.py"), session="s2")[1] == "deny")
check("a subagent first does not spend main's budget",
      call(home, new("tests/test_g.py"), session="s3", agent="x")[1] == "deny"
      and call(home, new("tests/test_h.py"), session="s3")[1] == "deny")

# Main sends no agent_id at all (the 2026-09-25 probe keyed every main call "MAIN" from
# an absent field). An empty string is therefore not main: it is keyed as its own value.
check("main of e1 is denied", call(home, new("tests/test_m.py"), session="e1")[1] == "deny")
check("agent_id \"\" is not main: denied on its own",
      call(home, new("tests/test_n.py"), session="e1", agent="")[1] == "deny")
check("... once", call(home, new("tests/test_o.py"), session="e1", agent="")[1] == "allow")

# Missing session_id: no key to hold the budget under, so allow and write nothing.
home2 = tempfile.mkdtemp()
code, out = run(home2, json.dumps({"tool_name": "Write", "tool_input": {"file_path": new("tests/test_z.py")}}))
check("missing session_id fails open", (code, out) == (0, ""))
check("... and writes no state", not os.path.exists(os.path.join(home2, ".claude", "aidex")))

# Concurrent first writes from one context (parallel tool calls): exactly one deny.
def race(session, n=8):
    ev = lambda i: json.dumps({"tool_name": "Write", "session_id": session,
                               "tool_input": {"file_path": new(f"tests/test_r{i}.py")}})
    procs = [subprocess.Popen(["sh", HOOK], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              text=True, env=dict(os.environ, HOME=home)) for _ in range(n)]
    for i, p in enumerate(procs):
        p.stdin.write(ev(i))
        p.stdin.close()
    return sum('"deny"' in p.stdout.read() for p in procs if p.wait() is not None)
counts = [race(f"race{k}") for k in range(10)]
check(f"8 concurrent new-test Writes from one context yield exactly one deny (10 rounds: {counts})",
      all(c == 1 for c in counts))

# ---- allows that write no state ----
existing = os.path.join(repo, "tests", "test_existing.py")
os.makedirs(os.path.dirname(existing), exist_ok=True)
open(existing, "w").close()
check("Write over an existing test file is allowed",
      call(home, existing, session="q1")[1] == "allow")
check("Edit of a new-looking test path is allowed", call(home, new("t/test_q.py"), tool="Edit", session="q1")[1] == "allow")
check("MultiEdit is allowed", call(home, new("t/test_q.py"), tool="MultiEdit", session="q1")[1] == "allow")
for rel in ("src/app.py", "tests/conftest.py", "tests/fixtures/data.json",
            "tests/helpers/dialog.ts", "src/latest.py", "src/attest_x.py",
            "mytests/run.sh", "scripts/contest.sh", "src/a.test.py", "src/a.test.tsx.bak"):
    check(f"non-test path {rel} is allowed", call(home, new(rel), session="q1")[1] == "allow")
check("the allows above wrote no state for their session",
      not os.path.exists(os.path.join(state_dir, "q1.tsv")))
check("... so the session's first real new test is still denied",
      call(home, new("tests/test_q.py"), session="q1")[1] == "deny")

# ---- every pattern is a test file (fresh session each) ----
POSITIVE = ["test_a.py", "pkg/a_test.py", "src/a.test.ts", "src/a.test.tsx", "src/a.spec.js",
            "src/a.spec.jsx", "src/a.test.mjs", "src/a.spec.cjs", "tests/test-x.sh",
            "bin/test-x.sh", "tests/run.sh", "tests/e2e/deep/run.sh"]
for i, rel in enumerate(POSITIVE):
    check(f"{rel} is gated", call(home, new(rel), session=f"p{i}")[1] == "deny")

# ---- census counts exactly what the hook gates ----
spec = importlib.util.spec_from_file_location("census", CENSUS)
census = importlib.util.module_from_spec(spec)
spec.loader.exec_module(census)
NEGATIVE = ["src/app.py", "tests/conftest.py", "tests/fixtures/data.json", "tests/helpers/dialog.ts",
            "src/latest.py", "src/attest_x.py", "mytests/run.sh", "scripts/contest.sh",
            "src/a.test.py", "src/a.test.tsx.bak"]
check("census is_test matches the hook on every table path",
      all(census.is_test(new(p)) for p in POSITIVE)
      and not any(census.is_test(new(p)) for p in NEGATIVE))

# ---- fail open ----
check("garbage stdin fails open", run(home, "not json") == (0, ""))
check("empty stdin fails open", run(home, "") == (0, ""))
check("missing tool_input fails open", run(home, json.dumps({"tool_name": "Write"})) == (0, ""))

print(f"\n{total - len(fails)}/{total}")
sys.exit(1 if fails else 0)
