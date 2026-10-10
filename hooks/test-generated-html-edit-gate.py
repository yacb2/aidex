#!/usr/bin/env python3
"""Test suite for generated-html-edit-gate.sh.

  python3 hooks/test-generated-html-edit-gate.py
"""
import json, os, subprocess, sys, tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "generated-html-edit-gate.sh")
fails = []
total = 0
MARKER = ("<!-- GENERATED from {spec} by /aidex:artifact spec_build.py"
          " — DO NOT EDIT: edit the spec and rebuild -->\n<!doctype html><p>x</p>\n")


def run(stdin):
    p = subprocess.run(["sh", HOOK], input=stdin, capture_output=True, text=True)
    return p.returncode, p.stdout


def call(path, tool="Edit"):
    return run(json.dumps({"tool_name": tool, "tool_input": {"file_path": path}}))


def reason(path):
    try:
        return json.loads(call(path)[1])["hookSpecificOutput"]["permissionDecisionReason"]
    except ValueError:
        return ""


def check(name, ok):
    global total
    total += 1
    print(("  PASS  " if ok else "  FAIL  ") + name)
    if not ok:
        fails.append(name)


def page(d, name, text):
    p = os.path.join(d, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)
    return p


with tempfile.TemporaryDirectory() as d:
    built = page(d, "report.html", MARKER.format(spec="report.spec.md"))
    spec = os.path.join(d, "report.spec.md")
    open(spec, "w").write("x\n")
    code, out = call(built)
    check("an Edit of a spec-built page is denied", code == 0 and '"deny"' in out)
    check("the reason names the spec resolved next to the page", spec in reason(built))
    check("the reason names spec_build.py", "spec_build.py" in reason(built))

    sub = os.path.join(d, "sub")
    os.mkdir(sub)
    page(d, "up.spec.md", "x\n")
    nested = page(sub, "p.html", MARKER.format(spec="../up.spec.md"))
    check("a relative spec path resolves against the page directory",
          os.path.normpath(os.path.join(sub, "../up.spec.md")) in reason(nested))

    page(d, "a & b.spec.md", "x\n")
    esc = page(d, "esc.html", MARKER.format(spec="a &amp; b.spec.md"))
    check("an HTML-escaped spec name is unescaped in the reason",
          os.path.join(d, "a & b.spec.md") in reason(esc))

    prev = os.path.join(d, ".aidex-artifact-prev")
    os.mkdir(prev)
    base = page(prev, "report.html", MARKER.format(spec="report.spec.md"))
    check("a baseline copy names the same spec as its page",
          spec in reason(base) and reason(base) != "")
    check("a marker whose spec does not exist passes",
          call(page(d, "gone.html", MARKER.format(spec="gone.spec.md"))) == (0, ""))

    # The hook against the marker spec_build.py really writes (not our copy of it).
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    real_spec = os.path.join(d, "real.spec.md")
    open(real_spec, "w", encoding="utf-8").write(
        '::: masthead {title="T" eyebrow="E" byline="b" lang="en" visual="none: test"}\nHi.\n:::\n')
    real = os.path.join(d, "real.html")
    subprocess.run([sys.executable, os.path.join(root, "skills/artifact/scripts/spec_build.py"),
                    real_spec, "-o", real], cwd=d, capture_output=True, text=True)
    check("a page built by the real spec_build.py is denied, naming its spec",
          os.path.isfile(real) and real_spec in reason(real))

    check("a page that does not exist yet passes", call(os.path.join(d, "new.html")) == (0, ""))
    check("an HTML without the marker passes",
          call(page(d, "plain.html", "<!doctype html><p>x</p>\n")) == (0, ""))
    board = page(d, "board.html",
                 "<!-- GENERATED 2026-10-10T00:00:00Z by /aidex:artifact backlog"
                 " — DO NOT EDIT, regenerate instead -->\n<!doctype html>\n")
    check("a board's different header passes", call(board) == (0, ""))
    check("the marker on line 2 does not count",
          call(page(d, "l2.html", "<!doctype html>\n" + MARKER.format(spec="s.md"))) == (0, ""))
    check("a non-HTML file with the marker passes",
          call(page(d, "notes.md", MARKER.format(spec="s.md"))) == (0, ""))

with open(os.path.join(os.path.dirname(HOOK), "hooks.json")) as f:
    pre = json.load(f)["hooks"]["PreToolUse"]
check("hooks.json wires the gate under the Write|Edit|MultiEdit matcher",
      any(g.get("matcher") == "Write|Edit|MultiEdit" and
          any("generated-html-edit-gate.sh" in h["command"] for h in g["hooks"]) for g in pre))
check("garbage stdin fails open", run("not json") == (0, ""))
check("empty stdin fails open", run("") == (0, ""))
check("missing file_path fails open", run(json.dumps({"tool_name": "Edit", "tool_input": {}})) == (0, ""))

print(f"\n{total - len(fails)}/{total}")
sys.exit(1 if fails else 0)
