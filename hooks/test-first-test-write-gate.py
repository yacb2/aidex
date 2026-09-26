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

# ---- Bash: a command that creates a new test file is gated like a Write ----
# The 2026-09-25 eval wrote its first test through Bash in 4 of 12 runs (cat > ... <<EOF,
# python - <<EOF ... open(p,'w')): a Write-only gate never fired there and the census
# dropped the writes. Paths are relative to the event's cwd, as Bash resolves them.
def bash(command, session, agent=None, cwd=repo):
    ev = {"tool_name": "Bash", "session_id": session, "cwd": cwd,
          "tool_input": {"command": command}}
    if agent is not None:
        ev["agent_id"] = agent
    code, out = run(home, json.dumps(ev))
    return "allow" if not out.strip() else json.loads(out)["hookSpecificOutput"]["permissionDecision"]

EVAL = json.load(open(os.path.join(HERE, "test-first-test-write-gate.eval-commands.json")))
# (command, the test paths it writes). Each is run through the hook (new path -> deny) and
# through census.bash_writes (the census counts exactly what the hook gates).
BASH_WRITES = [
    ("cat > tests/test_a.py <<'EOF'\nimport os\nx = 1 > 0\nEOF", ["tests/test_a.py"]),
    ("cat <<EOF >tests/test_a.py\nx\nEOF\npytest -q", ["tests/test_a.py"]),
    ("echo 'def test_x(): pass' >> tests/test_a.py", ["tests/test_a.py"]),
    ("printf x > \"tests/test_a.py\" 2>/dev/null", ["tests/test_a.py"]),
    ("echo x | tee tests/test_a.py >/dev/null", ["tests/test_a.py"]),
    ("tee -a src/a.test.ts <<'EOF'\nx\nEOF", ["src/a.test.ts"]),
    ("touch tests/__init__.py tests/test_a.py", ["tests/test_a.py"]),
    ("python3 - <<'EOF'\nopen('tests/test_a.py', 'w').write('x')\nEOF", ["tests/test_a.py"]),
    ("python - <<EOF\nt = 'tests/test_a.py'\nwith open(t, mode='a') as fh:\n    fh.write('x')\nEOF", ["tests/test_a.py"]),
    ("python3 -c \"from pathlib import Path; Path('tests/test_a.py').write_text('x')\"", ["tests/test_a.py"]),
    ("python3 -c \"open('pkg/a_test.py','x').close()\"", ["pkg/a_test.py"]),
    (EVAL["S3-2"][0], ["tests/test_shipping.py"]),   # cat > heredoc, first test write
    (EVAL["S3-2"][1], ["tests/test_shipping.py"]),   # python - heredoc, open(t,'w') via a name
    (EVAL["S4-1"][0], ["tests/test_shipping.py"]),   # cat > heredoc after a python - heredoc
    ("cd sub && cat > tests/test_a.py <<'EOF'\nx\nEOF", ["sub/tests/test_a.py"]),
    ("cd sub; cd ../other\npushd deep >/dev/null && touch test_a.py", ["other/deep/test_a.py"]),
    ("export D=pkg; W=$D/tests; echo x >> ${W}/test_a.py", ["pkg/tests/test_a.py"]),
    ("(cd sub && make) && echo x > tests/test_a.py", ["tests/test_a.py"]),
    ("cd sub && python3 - <<'EOF'\np = 'tests/test_a.py'\nopen(p, 'w').write('x')\nEOF", ["sub/tests/test_a.py"]),
    ("if true; then echo x > tests/test_a.py; fi", ["tests/test_a.py"]),
]
BASH_NOT_WRITES = [
    "pytest tests/test_x.py",
    "pytest -q tests/test_x.py 2>&1 | tail -3",
    "cat tests/test_x.py > /tmp/out.txt",
    "grep -n 'def test_' tests/test_x.py >/dev/null",
    "sed -i '' 's/a/b/' tests/test_existing.py",
    "cat > pricing.py <<'EOF'\n# writes tests/test_x.py later: open('tests/test_x.py','w')\nEOF",
    "python3 - <<'EOF'\nprint(open('tests/test_x.py').read())\nEOF",
    "echo \"x > tests/test_x.py\"",
    "cp tests/test_x.py /tmp/backup.py",
    "echo 'unbalanced",
    # cp/mv copy or move a test, they do not author one: never a write (README says why).
    "cp /tmp/draft.py tests/test_a.py && pytest -q",
    "mv -f draft.py tests/test_a.py",
    "cp /tmp/test_a.py tests/",
    # Only an unquoted operator is a redirect; a comment is not code.
    "echo 'a' # > tests/test_c.py",
    "echo '>' tests/test_a.py",
    "grep -n '>' tests/test_x.py",
    "echo \\> tests/test_a.py",
    # A python name reassigned: each open() resolves against the assignment in effect.
    "python3 - <<'EOF'\np='pricing.py'; open(p,'w'); p='tests/test_a.py'; print(open(p).read())\nEOF",
]
for i, (cmd, want) in enumerate(BASH_WRITES):
    check(f"Bash write #{i} ({cmd.splitlines()[0][:40]!r}) of a new test is denied",
          bash(cmd, session=f"b{i}") == "deny")
for i, cmd in enumerate(BASH_NOT_WRITES):
    check(f"Bash {cmd.splitlines()[0][:50]!r} is allowed", bash(cmd, session=f"bn{i}") == "allow")
check("the Bash allows above wrote no state",
      not any(os.path.exists(os.path.join(state_dir, f"bn{i}.tsv")) for i in range(len(BASH_NOT_WRITES))))
check("Bash: once per (session, agent) — the retry is allowed",
      bash(BASH_WRITES[0][0], session="b0") == "allow")
check("Bash and Write share one budget: a Write after a Bash deny is allowed",
      call(home, new("tests/test_zz.py"), session="b0")[1] == "allow")
check("Bash of a subagent is denied on its own", bash(BASH_WRITES[0][0], session="b0", agent="a") == "deny")
check("Bash redirect onto an existing test is allowed",
      bash("cat > tests/test_existing.py <<'EOF'\nx\nEOF", session="bx") == "allow")
check("Bash with an absolute path to a new test is denied",
      bash(f"touch {new('tests/test_abs.py')}", session="bx", cwd="/") == "deny")

# cd moves the directory a relative path resolves against. Subagents open nearly every
# command with `cd /abs && ...`; resolving against the event cwd instead denied appends
# to EXISTING tests and spent the one deny, so the next real new test landed ungated.
repo2 = tempfile.mkdtemp()  # no tests/test_existing.py at its root, only under sub/
sub = os.path.join(repo2, "sub")
os.makedirs(os.path.join(sub, "tests"), exist_ok=True)
open(os.path.join(sub, "tests", "test_existing.py"), "w").close()
check("cd sub && cat >> an existing sub/tests test is allowed",
      bash("cd sub && cat >> tests/test_existing.py <<'EOF'\nx\nEOF", session="cd1", cwd=repo2) == "allow")
check("... and did not spend the deny: a new test Write is denied",
      call(home, new("tests/test_new.py"), session="cd1")[1] == "deny")
check("cd <abs> && python3 - rewriting an existing test is allowed",
      bash(f"cd {sub} && python3 - <<'EOF'\np='tests/test_existing.py'\ns=open(p).read()\n"
           "open(p,'w').write(s)\nEOF", session="cd2", cwd="/") == "allow")
check("... and did not spend the deny", call(home, new("tests/test_new.py"), session="cd2")[1] == "deny")
check("D=<abs>; echo >> $D/tests/test_existing.py is allowed",
      bash(f"D={sub}; echo x >> $D/tests/test_existing.py", session="cd3", cwd=repo2) == "allow")
check("cd <abs> && touch a NEW test there is denied",
      bash(f"cd {sub} && touch tests/test_brand_new.py", session="cd4", cwd="/") == "deny")
# A path the detector cannot resolve is never denied; the census still counts it.
check("an unresolved $VAR path is allowed",
      bash("echo x >> $UNSET/tests/test_u.py", session="cd5") == "allow")
check("a relative path after cd \"$(...)\" is allowed",
      bash("cd \"$(git rev-parse --show-toplevel)\" && touch tests/test_u.py", session="cd5") == "allow")
check("... neither wrote state", not os.path.exists(os.path.join(state_dir, "cd5.tsv")))

# The hook imports the detector from ../skills/testing/scripts/census.py: in a copy of the
# shipped layout it denies, and without census.py it fails open (so the import is load-bearing).
import shutil
root = tempfile.mkdtemp()
os.makedirs(os.path.join(root, "hooks"))
shutil.copy(HOOK, os.path.join(root, "hooks"))
shutil.copytree(os.path.join(HERE, "..", "skills", "testing", "scripts"),
                os.path.join(root, "skills", "testing", "scripts"))
shutil.copy(os.path.join(HERE, "..", "skills", "testing", "SKILL.md"), os.path.join(root, "skills", "testing"))
def layout_call(session):
    ev = {"tool_name": "Write", "session_id": session, "tool_input": {"file_path": new("tests/test_l.py")}}
    return subprocess.run(["sh", os.path.join(root, "hooks", "first-test-write-gate.sh")],
                          input=json.dumps(ev), capture_output=True, text=True,
                          env=dict(os.environ, HOME=home)).stdout
check("from a copy of the shipped layout, a new-test Write is denied", '"deny"' in layout_call("lay1"))
os.remove(os.path.join(root, "skills", "testing", "scripts", "census.py"))
check("... and without census.py it fails open", layout_call("lay2") == "")

check("census.bash_writes finds exactly the test paths of every table command",
      all(sorted(p for p in census.bash_writes(c) if census.is_test(p)) == sorted(w)
          for c, w in BASH_WRITES))
check("census.bash_writes finds no test path in the non-write commands",
      not any(p for c in BASH_NOT_WRITES
              for p in census.bash_writes(c) if census.is_test(p)))
check("census.bash_writes resolves against a given cwd across cd",
      census.bash_writes("cd /w/a && cd ../b && echo x > tests/test_a.py", "/r") == ["/w/b/tests/test_a.py"])
check("census.bash_writes keeps an unresolved path (census counts it, the hook allows it)",
      census.bash_writes("echo x >> $U/tests/test_a.py") == ["$U/tests/test_a.py"])
check("_py_writes resolves each open() against the assignment in effect",
      census.bash_writes("python3 - <<'EOF'\np='pricing.py'; open(p,'w'); p='tests/test_a.py'; "
                         "print(open(p).read())\nEOF") == ["pricing.py"])
check("... also one statement per line",
      census.bash_writes("python3 - <<'EOF'\np='pricing.py'\nopen(p,'w')\np='tests/test_a.py'\n"
                         "print(open(p).read())\nEOF") == ["pricing.py"])

# ---- fail open ----
check("garbage stdin fails open", run(home, "not json") == (0, ""))
check("empty stdin fails open", run(home, "") == (0, ""))
check("missing tool_input fails open", run(home, json.dumps({"tool_name": "Write"})) == (0, ""))

print(f"\n{total - len(fails)}/{total}")
sys.exit(1 if fails else 0)
